import AVFoundation
import Foundation
import Speech
import WhisperKit

enum ReRecognitionBackendOption: String, CaseIterable, Sendable {
    case appleSpeech = "apple.speech"
    case appleSpeechOnDevice = "apple.speech.on_device"
    case whisperKitExperimental = "whisperkit.experimental"
    case senseVoiceSmall = "sensevoice.small"

    var shouldRunByDefault: Bool {
        switch self {
        case .appleSpeech, .appleSpeechOnDevice, .whisperKitExperimental:
            return true
        case .senseVoiceSmall:
            return SenseVoiceSmallRecognitionBackend.isAvailable
        }
    }

    var capabilities: BackendCapabilities {
        switch self {
        case .appleSpeech:
            return BackendCapabilities(
                backend: rawValue,
                displayName: "Apple Speech",
                experimental: false,
                supportsStreaming: true,
                supportsFileReRecognition: true,
                prefersOnDevice: false,
                intendedUseCases: ["general", "hotword_miss", "partial_final_jump"]
            )
        case .appleSpeechOnDevice:
            return BackendCapabilities(
                backend: rawValue,
                displayName: "Apple Speech On-Device",
                experimental: false,
                supportsStreaming: true,
                supportsFileReRecognition: true,
                prefersOnDevice: true,
                intendedUseCases: ["english_abbreviation", "number_unit_format", "privacy_sensitive"]
            )
        case .whisperKitExperimental:
            return BackendCapabilities(
                backend: rawValue,
                displayName: "WhisperKit Experimental",
                experimental: true,
                supportsStreaming: false,
                supportsFileReRecognition: true,
                prefersOnDevice: true,
                intendedUseCases: ["heavy_local_correction", "mixed_language", "accent_recheck"]
            )
        case .senseVoiceSmall:
            return BackendCapabilities(
                backend: rawValue,
                displayName: "SenseVoice Small",
                experimental: true,
                supportsStreaming: false,
                supportsFileReRecognition: true,
                prefersOnDevice: true,
                intendedUseCases: ["zh_cn_first_pass", "mixed_language", "accent_recheck", "content_word_confusion"]
            )
        }
    }

    func makeBackend() -> RecognitionBackend {
        switch self {
        case .appleSpeech:
            return AppleSpeechRecognitionBackend()
        case .appleSpeechOnDevice:
            return AppleSpeechOnDeviceRecognitionBackend()
        case .whisperKitExperimental:
            return WhisperKitRecognitionBackend()
        case .senseVoiceSmall:
            return SenseVoiceSmallRecognitionBackend()
        }
    }

    func effectiveConfiguration(from base: RecognitionConfiguration) -> RecognitionConfiguration {
        switch self {
        case .appleSpeech:
            return base
        case .appleSpeechOnDevice:
            return RecognitionConfiguration(
                localeIdentifier: base.localeIdentifier,
                contextualPhrases: base.contextualPhrases,
                addsPunctuation: base.addsPunctuation,
                requiresOnDeviceRecognition: true
            )
        case .whisperKitExperimental:
            return base
        case .senseVoiceSmall:
            return base
        }
    }
}

struct BackendCapabilities: Sendable {
    let backend: String
    let displayName: String
    let experimental: Bool
    let supportsStreaming: Bool
    let supportsFileReRecognition: Bool
    let prefersOnDevice: Bool
    let intendedUseCases: [String]
}

struct RecognitionConfiguration: Sendable {
    let localeIdentifier: String
    let contextualPhrases: [String]
    let addsPunctuation: Bool
    let requiresOnDeviceRecognition: Bool
}

protocol RecognitionBackend: AnyObject {
    var identifier: String { get }

    func startSession(
        configuration: RecognitionConfiguration,
        onUpdate: @escaping (RecognitionResultSnapshot) -> Void
    ) throws

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> RecognitionResultSnapshot
    func transcribeAudioFile(at url: URL, configuration: RecognitionConfiguration) async throws -> RecognitionResultSnapshot
    func cancel()
}

final class AppleSpeechRecognitionBackend: RecognitionBackend {
    enum BackendError: LocalizedError {
        case unsupportedLocale
        case recognizerUnavailable
        case notRunning

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale:
                return "当前系统不支持这个语言区域，请在设置中换一个 locale。"
            case .recognizerUnavailable:
                return "当前语音识别服务不可用，请稍后再试。"
            case .notRunning:
                return "当前没有可用的识别会话。"
            }
        }
    }

    let identifier: String
    private let forcedOnDeviceRecognition: Bool?

    init(
        identifier: String = "apple.speech",
        forcedOnDeviceRecognition: Bool? = nil
    ) {
        self.identifier = identifier
        self.forcedOnDeviceRecognition = forcedOnDeviceRecognition
        self.latestSnapshot = RecognitionResultSnapshot.empty(source: identifier)
    }

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finishContinuation: CheckedContinuation<RecognitionResultSnapshot, Error>?
    /// Guards all reads/writes of `finishContinuation` to prevent a race
    /// between the recognition callback thread and the timeout Task.
    private let continuationLock = NSLock()
    private var latestSnapshot: RecognitionResultSnapshot
    private var onUpdate: ((RecognitionResultSnapshot) -> Void)?
    private var isStopping = false

    func startSession(
        configuration: RecognitionConfiguration,
        onUpdate: @escaping (RecognitionResultSnapshot) -> Void
    ) throws {
        cancel()

        let locale = Locale(identifier: configuration.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw BackendError.unsupportedLocale
        }
        guard recognizer.isAvailable else {
            throw BackendError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = Array(configuration.contextualPhrases.prefix(100))
        request.addsPunctuation = configuration.addsPunctuation
        request.requiresOnDeviceRecognition = resolvedRequiresOnDevice(from: configuration.requiresOnDeviceRecognition)

        self.recognizer = recognizer
        self.request = request
        self.onUpdate = onUpdate
        self.isStopping = false
        self.latestSnapshot = RecognitionResultSnapshot.empty(source: identifier)

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let snapshot = self.makeSnapshot(from: result)
                self.latestSnapshot = snapshot
                self.onUpdate?(snapshot)

                if result.isFinal {
                    self.finishIfNeeded(with: .success(snapshot))
                }
            }

            if let error {
                let nsError = error as NSError
                if self.isStopping,
                   nsError.domain == "kLSRErrorDomain",
                   nsError.code == 301 {
                    self.finishIfNeeded(with: .success(self.latestSnapshot))
                    return
                }
                self.finishIfNeeded(with: .failure(error))
            }
        }
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func finish() async throws -> RecognitionResultSnapshot {
        guard request != nil || recognitionTask != nil else {
            throw BackendError.notRunning
        }

        isStopping = true
        request?.endAudio()
        let snapshot = try await waitForFinalSnapshot(timeoutNanoseconds: 6_000_000_000)
        cleanup(cancelTask: false)
        return snapshot
    }

    func transcribeAudioFile(at url: URL, configuration: RecognitionConfiguration) async throws -> RecognitionResultSnapshot {
        let locale = Locale(identifier: configuration.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw BackendError.unsupportedLocale
        }
        guard recognizer.isAvailable else {
            throw BackendError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.contextualStrings = Array(configuration.contextualPhrases.prefix(100))
        request.requiresOnDeviceRecognition = resolvedRequiresOnDevice(from: configuration.requiresOnDeviceRecognition)
        request.addsPunctuation = configuration.addsPunctuation

        return try await withCheckedThrowingContinuation { continuation in
            var localTask: SFSpeechRecognitionTask?
            var completed = false

            func resumeOnce(with result: Result<RecognitionResultSnapshot, Error>) {
                guard !completed else { return }
                completed = true
                continuation.resume(with: result)
                localTask?.cancel()
            }

            localTask = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    resumeOnce(with: .success(self.makeSnapshot(from: result)))
                    return
                }

                if let error {
                    resumeOnce(with: .failure(error))
                }
            }
        }
    }

    func cancel() {
        cleanup(cancelTask: true)
    }

    private func waitForFinalSnapshot(timeoutNanoseconds: UInt64) async throws -> RecognitionResultSnapshot {
        let fallback = latestSnapshot

        return try await withCheckedThrowingContinuation { continuation in
            continuationLock.lock()
            finishContinuation = continuation
            continuationLock.unlock()

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard let self else { return }
                // finishIfNeeded is already guarded by continuationLock internally,
                // so it's safe to call from here — duplicate calls are no-ops.
                self.finishIfNeeded(with: .success(self.latestSnapshot.rawText.isEmpty ? fallback : self.latestSnapshot))
            }
        }
    }

    private func makeSnapshot(from result: SFSpeechRecognitionResult) -> RecognitionResultSnapshot {
        let transcription = result.bestTranscription
        let rawText = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = transcription.segments.enumerated().map { index, segment in
            let startTime = max(0, segment.timestamp)
            let endTime = max(startTime, segment.timestamp + segment.duration)
            let cleanText = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)

            return TranscriptSegment(
                id: Self.segmentID(
                    source: identifier,
                    index: index,
                    startTime: startTime,
                    endTime: endTime,
                    text: cleanText
                ),
                text: cleanText,
                startTime: startTime,
                endTime: endTime,
                isFinal: result.isFinal,
                source: identifier,
                suspicionFlags: []
            )
        }

        return RecognitionResultSnapshot(
            rawText: rawText,
            displayText: rawText,
            segments: segments,
            isFinal: result.isFinal,
            source: identifier
        )
    }

    private func finishIfNeeded(with result: Result<RecognitionResultSnapshot, Error>) {
        continuationLock.lock()
        guard let continuation = finishContinuation else {
            continuationLock.unlock()
            return
        }
        finishContinuation = nil
        continuationLock.unlock()
        continuation.resume(with: result)
    }

    private func resolvedRequiresOnDevice(from requested: Bool) -> Bool {
        forcedOnDeviceRecognition ?? requested
    }

    private func cleanup(cancelTask: Bool) {
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        request = nil
        recognizer = nil
        // Resume any pending continuation before dropping it to avoid
        // a leaked continuation (undefined behavior / crash in debug).
        continuationLock.lock()
        let pendingContinuation = finishContinuation
        finishContinuation = nil
        continuationLock.unlock()
        if let pendingContinuation {
            pendingContinuation.resume(returning: latestSnapshot)
        }
        onUpdate = nil
        isStopping = false
    }

    private static func segmentID(
        source: String,
        index: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String
    ) -> String {
        let normalizedText = text.replacingOccurrences(of: " ", with: "_")
        return "\(source)-\(index)-\(Int(startTime * 1000))-\(Int(endTime * 1000))-\(normalizedText)"
    }
}

final class AppleSpeechOnDeviceRecognitionBackend: RecognitionBackend {
    private let backend = AppleSpeechRecognitionBackend(
        identifier: "apple.speech.on_device",
        forcedOnDeviceRecognition: true
    )

    var identifier: String { backend.identifier }

    func startSession(
        configuration: RecognitionConfiguration,
        onUpdate: @escaping (RecognitionResultSnapshot) -> Void
    ) throws {
        try backend.startSession(configuration: configuration, onUpdate: onUpdate)
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        backend.appendAudioBuffer(buffer)
    }

    func finish() async throws -> RecognitionResultSnapshot {
        try await backend.finish()
    }

    func transcribeAudioFile(at url: URL, configuration: RecognitionConfiguration) async throws -> RecognitionResultSnapshot {
        try await backend.transcribeAudioFile(at: url, configuration: configuration)
    }

    func cancel() {
        backend.cancel()
    }
}

final class WhisperKitRecognitionBackend: RecognitionBackend {
    enum WhisperKitError: LocalizedError {
        case streamingUnsupported
        case transcriptionFailed
        case invalidAudio

        var errorDescription: String? {
            switch self {
            case .streamingUnsupported:
                return "WhisperKit 当前只接入了文件级局部重识别，不支持主链路流式会话。"
            case .transcriptionFailed:
                return "WhisperKit 未返回可用的转写结果。"
            case .invalidAudio:
                return "WhisperKit 无法读取当前音频片段。"
            }
        }
    }

    let identifier = "whisperkit.experimental"
    private let modelName = ProcessInfo.processInfo.environment["VOICEINPUT_WHISPERKIT_MODEL"] ?? "small"

    func startSession(
        configuration: RecognitionConfiguration,
        onUpdate: @escaping (RecognitionResultSnapshot) -> Void
    ) throws {
        _ = configuration
        _ = onUpdate
        throw WhisperKitError.streamingUnsupported
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        _ = buffer
    }

    func finish() async throws -> RecognitionResultSnapshot {
        throw WhisperKitError.streamingUnsupported
    }

    func transcribeAudioFile(at url: URL, configuration: RecognitionConfiguration) async throws -> RecognitionResultSnapshot {
        _ = configuration
        let config = WhisperKitConfig(model: modelName)
        let whisperKit = try await WhisperKit(config)
        let results = try await whisperKit.transcribe(audioPath: url.path())
        guard let first = results.first else {
            throw WhisperKitError.transcriptionFailed
        }

        let text = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = try audioDuration(for: url)
        let segments = makeSegments(from: first, fallbackText: text, duration: duration)

        return RecognitionResultSnapshot(
            rawText: text,
            displayText: text,
            segments: segments,
            isFinal: true,
            source: identifier
        )
    }

    func cancel() {}

    private func makeSegments(
        from result: TranscriptionResult,
        fallbackText: String,
        duration: TimeInterval
    ) -> [TranscriptSegment] {
        let timestampSegments = result.segments.compactMap { segment -> TranscriptSegment? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let startTime = TimeInterval(max(0, segment.start))
            let endTime = TimeInterval(max(segment.start, segment.end))

            return TranscriptSegment(
                id: "\(identifier)-\(Int(startTime * 1000))-\(Int(endTime * 1000))-\(text.replacingOccurrences(of: " ", with: "_"))",
                text: text,
                startTime: startTime,
                endTime: endTime,
                isFinal: true,
                source: identifier,
                suspicionFlags: []
            )
        }

        if !timestampSegments.isEmpty {
            return timestampSegments
        }

        guard !fallbackText.isEmpty else { return [] }
        return [
            TranscriptSegment(
                id: "\(identifier)-0-\(Int(duration * 1000))-\(fallbackText.replacingOccurrences(of: " ", with: "_"))",
                text: fallbackText,
                startTime: 0,
                endTime: max(0, duration),
                isFinal: true,
                source: identifier,
                suspicionFlags: []
            )
        ]
    }

    private func audioDuration(for url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else { throw WhisperKitError.invalidAudio }
        return Double(file.length) / sampleRate
    }
}

final class SenseVoiceSmallRecognitionBackend: RecognitionBackend {
    enum SenseVoiceError: LocalizedError {
        case streamingUnsupported
        case pythonUnavailable
        case helperScriptUnavailable
        case modelDirectoryUnavailable
        case inferenceFailed(String)
        case invalidAudio

        var errorDescription: String? {
            switch self {
            case .streamingUnsupported:
                return "SenseVoice-Small 当前只接入了文件级重识别，不支持主链路流式会话。"
            case .pythonUnavailable:
                return "未找到可用的 SenseVoice Python 运行环境。"
            case .helperScriptUnavailable:
                return "未找到 SenseVoice 推理脚本。"
            case .modelDirectoryUnavailable:
                return "未找到本地 SenseVoice-Small 模型目录。"
            case let .inferenceFailed(reason):
                return "SenseVoice-Small 推理失败：\(reason)"
            case .invalidAudio:
                return "SenseVoice-Small 无法读取当前音频片段。"
            }
        }
    }

    private struct ScriptResponse: Decodable {
        let text: String
        let rawText: String?

        enum CodingKeys: String, CodingKey {
            case text
            case rawText = "raw_text"
        }
    }

    let identifier = "sensevoice.small"

    static var isAvailable: Bool {
        resolvePythonURL() != nil && resolveHelperScriptURL() != nil && resolveModelDirectoryURL() != nil
    }

    func startSession(
        configuration: RecognitionConfiguration,
        onUpdate: @escaping (RecognitionResultSnapshot) -> Void
    ) throws {
        _ = configuration
        _ = onUpdate
        throw SenseVoiceError.streamingUnsupported
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        _ = buffer
    }

    func finish() async throws -> RecognitionResultSnapshot {
        throw SenseVoiceError.streamingUnsupported
    }

    func transcribeAudioFile(at url: URL, configuration: RecognitionConfiguration) async throws -> RecognitionResultSnapshot {
        guard let pythonURL = Self.resolvePythonURL() else {
            throw SenseVoiceError.pythonUnavailable
        }
        guard let scriptURL = Self.resolveHelperScriptURL() else {
            throw SenseVoiceError.helperScriptUnavailable
        }
        guard let modelDirectoryURL = Self.resolveModelDirectoryURL() else {
            throw SenseVoiceError.modelDirectoryUnavailable
        }

        let language = Self.languageCode(for: configuration.localeIdentifier)
        let response = try await Self.runHelper(
            pythonURL: pythonURL,
            scriptURL: scriptURL,
            modelDirectoryURL: modelDirectoryURL,
            audioURL: url,
            language: language
        )

        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawText = (response.rawText ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = try audioDuration(for: url)
        let segmentText = text.isEmpty ? rawText : text

        let segments = segmentText.isEmpty ? [] : [
            TranscriptSegment(
                id: "\(identifier)-0-\(Int(duration * 1000))-\(segmentText.replacingOccurrences(of: " ", with: "_"))",
                text: segmentText,
                startTime: 0,
                endTime: max(0, duration),
                isFinal: true,
                source: identifier,
                suspicionFlags: []
            )
        ]

        return RecognitionResultSnapshot(
            rawText: rawText,
            displayText: segmentText,
            segments: segments,
            isFinal: true,
            source: identifier
        )
    }

    func cancel() {}

    private func audioDuration(for url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else { throw SenseVoiceError.invalidAudio }
        return Double(file.length) / sampleRate
    }

    /// Maximum time (in seconds) to wait for the SenseVoice Python process.
    private static let processTimeoutSeconds: TimeInterval = 60

    private static func runHelper(
        pythonURL: URL,
        scriptURL: URL,
        modelDirectoryURL: URL,
        audioURL: URL,
        language: String
    ) async throws -> ScriptResponse {
        try await withCheckedThrowingContinuation { continuation in
            nonisolated(unsafe) var didResume = false
            let lock = NSLock()

            @Sendable func resumeOnce(with result: Result<ScriptResponse, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = pythonURL
            process.arguments = [
                scriptURL.path,
                "--model-dir", modelDirectoryURL.path,
                "--audio-path", audioURL.path,
                "--language", language,
                "--use-itn"
            ]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(decoding: stdoutData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let stderr = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                guard process.terminationStatus == 0 else {
                    resumeOnce(with: .failure(SenseVoiceError.inferenceFailed(stderr.isEmpty ? stdout : stderr)))
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(ScriptResponse.self, from: Data(stdout.utf8))
                    resumeOnce(with: .success(decoded))
                } catch {
                    resumeOnce(with: .failure(SenseVoiceError.inferenceFailed("无法解析输出：\(stdout)")))
                }
            }

            do {
                try process.run()
            } catch {
                resumeOnce(with: .failure(SenseVoiceError.inferenceFailed(error.localizedDescription)))
                return
            }

            // Timeout watchdog: terminate the process if it exceeds the limit.
            DispatchQueue.global().asyncAfter(deadline: .now() + processTimeoutSeconds) {
                guard process.isRunning else { return }
                process.terminate()
                resumeOnce(with: .failure(SenseVoiceError.inferenceFailed(
                    "SenseVoice 推理超时（\(Int(processTimeoutSeconds)) 秒），进程已终止。"
                )))
            }
        }
    }

    private static func languageCode(for localeIdentifier: String) -> String {
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.hasPrefix("zh") { return "zh" }
        if normalized.hasPrefix("en") { return "en" }
        if normalized.hasPrefix("ja") { return "ja" }
        if normalized.hasPrefix("ko") { return "ko" }
        if normalized.hasPrefix("yue") || normalized.contains("hant-hk") || normalized.contains("zh-hk") { return "yue" }
        return "auto"
    }

    private static func resolveModelDirectoryURL() -> URL? {
        let fm = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["VOICEINPUT_SENSEVOICE_MODEL_DIR"],
            "\(NSHomeDirectory())/Library/Application Support/Shandianshuo/models/sensevoice-small"
        ].compactMap { $0 }.map(URL.init(fileURLWithPath:))

        return candidates.first(where: { fm.fileExists(atPath: $0.path) })
    }

    private static func resolveHelperScriptURL() -> URL? {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let bundleScript = Bundle.main.resourceURL?.appendingPathComponent("sensevoice_transcribe.py")
        let candidates = [
            ProcessInfo.processInfo.environment["VOICEINPUT_SENSEVOICE_SCRIPT"].map(URL.init(fileURLWithPath:)),
            bundleScript,
            cwd.appendingPathComponent("scripts/sensevoice_transcribe.py")
        ].compactMap { $0 }

        return candidates.first(where: { fm.fileExists(atPath: $0.path) })
    }

    private static func resolvePythonURL() -> URL? {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let scriptURL = resolveHelperScriptURL()
        let repoRoot = scriptURL?.deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [
            ProcessInfo.processInfo.environment["VOICEINPUT_SENSEVOICE_PYTHON"].map(URL.init(fileURLWithPath:)),
            repoRoot?.appendingPathComponent(".sensevoice-venv/bin/python"),
            cwd.appendingPathComponent(".sensevoice-venv/bin/python")
        ].compactMap { $0 }

        return candidates.first(where: { fm.isExecutableFile(atPath: $0.path) })
    }
}

extension AppleSpeechRecognitionBackend: @unchecked Sendable {}
