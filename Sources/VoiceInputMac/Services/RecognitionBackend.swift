import AVFoundation
import Foundation
import Speech
import WhisperKit

enum ReRecognitionBackendOption: String, CaseIterable, Sendable {
    case appleSpeech = "apple.speech"
    case appleSpeechOnDevice = "apple.speech.on_device"
    case whisperKitExperimental = "whisperkit.experimental"

    var shouldRunByDefault: Bool {
        switch self {
        case .appleSpeech, .appleSpeechOnDevice, .whisperKitExperimental:
            return true
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
            finishContinuation = continuation

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard let self, self.finishContinuation != nil else { return }
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
        guard let continuation = finishContinuation else { return }
        finishContinuation = nil
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
        finishContinuation = nil
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

extension AppleSpeechRecognitionBackend: @unchecked Sendable {}
