import AVFoundation
import Foundation

final class AudioCaptureService {
    enum AudioCaptureError: LocalizedError {
        case alreadyRunning
        case noInputDevice
        case cannotStartEngine
        case noRecordedAudio
        case invalidClipRange
        case cannotAllocateBuffer

        var errorDescription: String? {
            switch self {
            case .alreadyRunning:
                return "当前已有一段录音正在进行。"
            case .noInputDevice:
                return "没有可用的麦克风输入设备。"
            case .cannotStartEngine:
                return "麦克风当前不可用，请检查输入设备、系统输入源或是否被其他应用独占。"
            case .noRecordedAudio:
                return "当前会话没有可用的录音缓存。"
            case .invalidClipRange:
                return "音频片段时间范围无效。"
            case .cannotAllocateBuffer:
                return "无法为音频裁剪分配缓冲区。"
            }
        }
    }

    typealias AudioBufferHandler = (AVAudioPCMBuffer, AVAudioTime?) -> Void

    private let audioEngine = AVAudioEngine()
    private let tempDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("VoiceInputMacSessions", isDirectory: true)

    private var audioFile: AVAudioFile?
    private var currentSession: SessionAudioArtifact?
    private var currentFormat: AVAudioFormat?
    private var onBuffer: AudioBufferHandler?
    private var isRunning = false

    func startSession(onBuffer: @escaping AudioBufferHandler) throws -> SessionAudioArtifact {
        guard !isRunning else { throw AudioCaptureError.alreadyRunning }

        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw AudioCaptureError.noInputDevice
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let sessionID = UUID()
        let session = SessionAudioArtifact(
            id: sessionID,
            fileURL: tempDirectory.appendingPathComponent("\(sessionID.uuidString).caf"),
            createdAt: Date(),
            sampleRate: inputFormat.sampleRate,
            channelCount: inputFormat.channelCount,
            duration: 0
        )

        let audioFile = try AVAudioFile(forWriting: session.fileURL, settings: inputFormat.settings)

        self.audioFile = audioFile
        self.currentSession = session
        self.currentFormat = inputFormat
        self.onBuffer = onBuffer

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { [weak self] buffer, time in
            guard let self else { return }

            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                // Keep recognition running even if caching fails for a single write.
            }

            self.onBuffer?(buffer, time)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioFile = nil
            self.currentSession = nil
            self.currentFormat = nil
            self.onBuffer = nil
            throw AudioCaptureError.cannotStartEngine
        }
        isRunning = true
        return session
    }

    @discardableResult
    func stopSession() -> SessionAudioArtifact? {
        guard isRunning else { return currentSession }

        let sampleRate = currentFormat?.sampleRate ?? currentSession?.sampleRate ?? 0
        let frameLength = audioFile?.length ?? 0

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        isRunning = false
        onBuffer = nil
        currentFormat = nil
        audioFile = nil

        if var session = currentSession {
            session.duration = sampleRate > 0 ? Double(frameLength) / sampleRate : 0
            currentSession = session
        }

        return currentSession
    }

    func cancelSession() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
        onBuffer = nil
        currentFormat = nil
        audioFile = nil
        currentSession = nil
    }

    func extractClip(from session: SessionAudioArtifact, startTime: TimeInterval, endTime: TimeInterval) throws -> URL {
        guard FileManager.default.fileExists(atPath: session.fileURL.path) else {
            throw AudioCaptureError.noRecordedAudio
        }

        let boundedStart = max(0, startTime)
        let boundedEnd = min(max(endTime, 0), session.duration)
        guard boundedEnd > boundedStart else {
            throw AudioCaptureError.invalidClipRange
        }

        let inputFile = try AVAudioFile(forReading: session.fileURL)
        let sampleRate = inputFile.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(boundedStart * sampleRate)
        let endFrame = AVAudioFramePosition(boundedEnd * sampleRate)
        let totalFrames = max(endFrame - startFrame, 0)

        let clipURL = tempDirectory.appendingPathComponent(
            "\(session.id.uuidString)-\(Int(boundedStart * 1000))-\(Int(boundedEnd * 1000)).caf"
        )

        if FileManager.default.fileExists(atPath: clipURL.path) {
            try? FileManager.default.removeItem(at: clipURL)
        }

        let outputFile = try AVAudioFile(forWriting: clipURL, settings: inputFile.fileFormat.settings)
        inputFile.framePosition = startFrame

        var framesRemaining = AVAudioFrameCount(totalFrames)
        let chunkSize: AVAudioFrameCount = 4096

        while framesRemaining > 0 {
            let framesToRead = min(chunkSize, framesRemaining)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: inputFile.processingFormat,
                frameCapacity: framesToRead
            ) else {
                throw AudioCaptureError.cannotAllocateBuffer
            }

            try inputFile.read(into: buffer, frameCount: framesToRead)
            if buffer.frameLength == 0 {
                break
            }

            try outputFile.write(from: buffer)
            framesRemaining -= buffer.frameLength
        }

        return clipURL
    }
}

extension AudioCaptureService: @unchecked Sendable {}
