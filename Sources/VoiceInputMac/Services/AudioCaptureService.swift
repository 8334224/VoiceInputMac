@preconcurrency import AVFoundation
import Foundation

protocol AudioCaptureRecordingSession: AnyObject {
    var artifact: SessionAudioArtifact { get }
    var activeInputDevice: ActiveInputDeviceInfo { get }

    func stop() throws -> SessionAudioArtifact
    func cancel()
}

protocol AudioCaptureBackend {
    func startSession(
        deviceID: String?,
        selectedDeviceName: String?,
        onBuffer: @escaping AudioCaptureService.AudioBufferHandler,
        onFailure: @escaping @Sendable (Error) -> Void
    ) throws -> any AudioCaptureRecordingSession
}

final class AudioCaptureService {
    enum AudioCaptureError: LocalizedError, Equatable {
        case alreadyRunning
        case noInputDevice
        case cannotStartEngine
        case noRecordedAudio
        case invalidClipRange
        case cannotAllocateBuffer
        case selectedInputDeviceUnavailable(String)
        case selectedInputDevicePermissionDenied(String)
        case selectedInputDeviceStartFailed(String)

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
            case let .selectedInputDeviceUnavailable(name):
                return "所选麦克风“\(name)”当前不可用或已移除。"
            case let .selectedInputDevicePermissionDenied(name):
                return "没有权限访问所选麦克风“\(name)”。"
            case let .selectedInputDeviceStartFailed(name):
                return "所选麦克风“\(name)”启动失败，请检查设备连接和系统输入设置。"
            }
        }
    }

    typealias AudioBufferHandler = (AVAudioPCMBuffer, AVAudioTime?) -> Void

    private let tempDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("VoiceInputMacSessions", isDirectory: true)
    private let deviceProvider: MicrophoneDeviceProviding
    private let backend: AudioCaptureBackend

    /// Maximum age (in seconds) of temporary audio files before cleanup. Default: 1 hour.
    private static let maxTempFileAge: TimeInterval = 3600
    /// Maximum number of temporary session files to keep.
    private static let maxTempFileCount = 10

    private var activeRecordingSession: (any AudioCaptureRecordingSession)?
    private var currentSession: SessionAudioArtifact?
    private var currentSelection: MicrophoneSelectionConfiguration?
    private var isRunning = false

    init(
        deviceProvider: MicrophoneDeviceProviding = MicrophoneDeviceService(),
        backend: AudioCaptureBackend? = nil
    ) {
        self.deviceProvider = deviceProvider
        self.backend = backend ?? AVCaptureAudioCaptureBackend(tempDirectory: tempDirectory)
        cleanupOldTempFiles()
    }

    func startSession(
        selection: MicrophoneSelectionConfiguration,
        onBuffer: @escaping AudioBufferHandler,
        onFailure: @escaping @Sendable (Error) -> Void = { _ in }
    ) throws -> SessionAudioArtifact {
        guard !isRunning else { throw AudioCaptureError.alreadyRunning }

        let availableDevices = try deviceProvider.availableInputDevices()
        let target = try resolveTargetDevice(for: selection, availableDevices: availableDevices)
        print("[AudioCaptureService] starting session targetDeviceID=\(target.deviceID ?? "system-default") targetDeviceName=\(target.displayName)")

        do {
            let recordingSession = try backend.startSession(
                deviceID: target.deviceID,
                selectedDeviceName: target.displayName,
                onBuffer: onBuffer,
                onFailure: { [weak self] error in
                    guard let self else { return }
                    print("[AudioCaptureService] runtime failure: \(error.localizedDescription)")
                    self.activeRecordingSession = nil
                    self.currentSession = nil
                    self.currentSelection = nil
                    self.isRunning = false
                    onFailure(error)
                }
            )
            activeRecordingSession = recordingSession
            currentSession = recordingSession.artifact
            currentSelection = selection
            isRunning = true
            return recordingSession.artifact
        } catch let error as AudioCaptureError {
            throw error
        } catch {
            if let deviceID = target.deviceID, !deviceID.isEmpty {
                throw AudioCaptureError.selectedInputDeviceStartFailed(target.displayName)
            }
            throw AudioCaptureError.cannotStartEngine
        }
    }

    @discardableResult
    func stopSession() throws -> SessionAudioArtifact? {
        guard isRunning else { return currentSession }
        guard let activeRecordingSession else { return currentSession }

        let finishedSession = try activeRecordingSession.stop()
        currentSession = finishedSession
        self.activeRecordingSession = nil
        currentSelection = nil
        isRunning = false
        cleanupOldTempFiles()
        return finishedSession
    }

    func cancelSession() {
        activeRecordingSession?.cancel()
        activeRecordingSession = nil
        currentSession = nil
        currentSelection = nil
        isRunning = false
    }

    func activeInputDeviceInfo() -> ActiveInputDeviceInfo? {
        currentSession?.inputDevice
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

    /// Removes stale temporary audio files that exceed the age or count limit.
    private func cleanupOldTempFiles() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        let currentFileURL = currentSession?.fileURL

        // Sort newest first so we can keep the most recent ones.
        let sorted = contents
            .compactMap { url -> (URL, Date)? in
                guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                      let created = attrs[.creationDate] as? Date else {
                    return (url, .distantPast)
                }
                return (url, created)
            }
            .sorted { $0.1 > $1.1 }

        for (index, entry) in sorted.enumerated() {
            let (fileURL, created) = entry
            // Never remove the file belonging to the current active session.
            if fileURL == currentFileURL { continue }

            let tooOld = now.timeIntervalSince(created) > Self.maxTempFileAge
            let overLimit = index >= Self.maxTempFileCount

            if tooOld || overLimit {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    private func resolveTargetDevice(
        for selection: MicrophoneSelectionConfiguration,
        availableDevices: [MicrophoneDeviceInfo]
    ) throws -> (deviceID: String?, displayName: String) {
        switch selection.mode {
        case .systemDefault:
            if let device = deviceProvider.systemDefaultInputDevice() {
                return (nil, device.name)
            }
            if let fallback = availableDevices.first {
                return (nil, fallback.name)
            }
            throw AudioCaptureError.noInputDevice

        case .specificDevice:
            guard let targetID = selection.resolvedDeviceID else {
                throw AudioCaptureError.selectedInputDeviceUnavailable("未指定设备")
            }
            guard let device = availableDevices.first(where: { $0.id == targetID }) else {
                let fallbackName = selection.selectedMicrophoneName.nilIfBlank ?? "已保存设备"
                throw AudioCaptureError.selectedInputDeviceUnavailable(fallbackName)
            }
            return (device.id, device.name)
        }
    }
}

private final class AVCaptureAudioCaptureBackend: AudioCaptureBackend {
    private let tempDirectory: URL

    init(tempDirectory: URL) {
        self.tempDirectory = tempDirectory
    }

    func startSession(
        deviceID: String?,
        selectedDeviceName: String?,
        onBuffer: @escaping AudioCaptureService.AudioBufferHandler,
        onFailure: @escaping @Sendable (Error) -> Void
    ) throws -> any AudioCaptureRecordingSession {
        let session = try AVCaptureAudioRecordingSession(
            deviceID: deviceID,
            selectedDeviceName: selectedDeviceName,
            tempDirectory: tempDirectory,
            onBuffer: onBuffer,
            onFailure: onFailure
        )
        try session.start()
        return session
    }
}

private final class AVCaptureAudioRecordingSession: NSObject, AudioCaptureRecordingSession, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let deviceID: String?
    private let selectedDeviceName: String?
    private let tempDirectory: URL
    private let onBuffer: AudioCaptureService.AudioBufferHandler
    private let onFailure: @Sendable (Error) -> Void
    private let captureSession = AVCaptureSession()
    private let sampleBufferQueue = DispatchQueue(label: "VoiceInputMac.AudioCapture.sample-buffer")
    private let stateQueue = DispatchQueue(label: "VoiceInputMac.AudioCapture.state")
    private let fileWriteQueue = DispatchQueue(label: "VoiceInputMac.AudioCapture.file-write")

    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var deviceInput: AVCaptureDeviceInput?
    private var audioFile: AVAudioFile?
    private var currentFormat: AVAudioFormat?
    private var recordedFrameCount: AVAudioFramePosition = 0
    private var didReportFailure = false
    private var isStopping = false
    private var isCancelled = false
    private var observers: [NSObjectProtocol] = []
    private var mutableArtifact: SessionAudioArtifact

    deinit {
        // Safety net: remove any lingering observers to prevent leaks
        // if cleanup() was not called due to an exception or early return.
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    var artifact: SessionAudioArtifact {
        stateQueue.sync { mutableArtifact }
    }

    var activeInputDevice: ActiveInputDeviceInfo {
        stateQueue.sync {
            mutableArtifact.inputDevice ?? ActiveInputDeviceInfo(
                id: deviceID,
                name: selectedDeviceName ?? "当前输入设备",
                selectionMode: deviceID == nil ? .systemDefault : .specificDevice
            )
        }
    }

    init(
        deviceID: String?,
        selectedDeviceName: String?,
        tempDirectory: URL,
        onBuffer: @escaping AudioCaptureService.AudioBufferHandler,
        onFailure: @escaping @Sendable (Error) -> Void
    ) throws {
        self.deviceID = deviceID
        self.selectedDeviceName = selectedDeviceName
        self.tempDirectory = tempDirectory
        self.onBuffer = onBuffer
        self.onFailure = onFailure

        let sessionID = UUID()
        self.mutableArtifact = SessionAudioArtifact(
            id: sessionID,
            fileURL: tempDirectory.appendingPathComponent("\(sessionID.uuidString).caf"),
            createdAt: Date(),
            sampleRate: 16_000,
            channelCount: 1,
            duration: 0,
            inputDevice: nil
        )

        super.init()
    }

    func start() throws {
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let device = try resolveCaptureDevice()
        updateArtifactInputDevice(using: device)
        updateArtifactFormat(using: device)

        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch authorizationStatus {
        case .denied, .restricted:
            throw AudioCaptureService.AudioCaptureError.selectedInputDevicePermissionDenied(device.localizedName)
        case .notDetermined, .authorized:
            break
        @unknown default:
            break
        }

        var isConfiguringSession = false

        do {
            captureSession.beginConfiguration()
            isConfiguringSession = true

            let input = try AVCaptureDeviceInput(device: device)
            guard captureSession.canAddInput(input) else {
                throw AudioCaptureService.AudioCaptureError.selectedInputDeviceStartFailed(device.localizedName)
            }
            captureSession.addInput(input)
            deviceInput = input

            let dataOutput = AVCaptureAudioDataOutput()
            dataOutput.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            dataOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)
            guard captureSession.canAddOutput(dataOutput) else {
                throw AudioCaptureService.AudioCaptureError.selectedInputDeviceStartFailed(device.localizedName)
            }
            captureSession.addOutput(dataOutput)
            audioDataOutput = dataOutput

            installObservers(for: device)
            captureSession.commitConfiguration()
            isConfiguringSession = false
            captureSession.startRunning()
            print("[AudioCaptureService] capture session started device=\(device.localizedName) (\(device.uniqueID))")
        } catch let error as AudioCaptureService.AudioCaptureError {
            if isConfiguringSession {
                captureSession.commitConfiguration()
            }
            cleanup()
            throw error
        } catch {
            if isConfiguringSession {
                captureSession.commitConfiguration()
            }
            cleanup()
            if deviceID != nil {
                throw AudioCaptureService.AudioCaptureError.selectedInputDeviceStartFailed(device.localizedName)
            }
            throw AudioCaptureService.AudioCaptureError.cannotStartEngine
        }
    }

    func stop() throws -> SessionAudioArtifact {
        stateQueue.sync {
            isStopping = true
        }

        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        cleanup()

        return stateQueue.sync {
            var updated = mutableArtifact
            if updated.sampleRate > 0 {
                updated.duration = Double(recordedFrameCount) / updated.sampleRate
            } else {
                updated.duration = 0
            }
            mutableArtifact = updated
            return updated
        }
    }

    func cancel() {
        stateQueue.sync {
            isCancelled = true
            isStopping = true
        }
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        cleanup(removeArtifact: true)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !stateQueue.sync(execute: { isStopping || isCancelled || didReportFailure }) else {
            return
        }

        do {
            let buffer = try makePCMBuffer(from: sampleBuffer)
            try write(buffer: buffer)
            onBuffer(buffer, nil)
        } catch {
            reportFailure(error)
        }
    }

    private func write(buffer: AVAudioPCMBuffer) throws {
        try fileWriteQueue.sync { [self] in
            if audioFile == nil {
                audioFile = try AVAudioFile(forWriting: artifact.fileURL, settings: buffer.format.settings)
                currentFormat = buffer.format
                let sampleRate = buffer.format.sampleRate
                let channelCount = buffer.format.channelCount
                stateQueue.async { [self] in
                    mutableArtifact = SessionAudioArtifact(
                        id: mutableArtifact.id,
                        fileURL: mutableArtifact.fileURL,
                        createdAt: mutableArtifact.createdAt,
                        sampleRate: sampleRate,
                        channelCount: channelCount,
                        duration: mutableArtifact.duration,
                        inputDevice: mutableArtifact.inputDevice
                    )
                }
            }

            try audioFile?.write(from: buffer)
            recordedFrameCount += AVAudioFramePosition(buffer.frameLength)
        }
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw AudioCaptureService.AudioCaptureError.cannotAllocateBuffer
        }

        guard let format = AVAudioFormat(streamDescription: asbdPointer) else {
            throw AudioCaptureService.AudioCaptureError.cannotAllocateBuffer
        }

        let frameCapacity = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw AudioCaptureService.AudioCaptureError.cannotAllocateBuffer
        }

        pcmBuffer.frameLength = frameCapacity

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw AudioCaptureService.AudioCaptureError.cannotAllocateBuffer
        }

        let dataLength = CMBlockBufferGetDataLength(blockBuffer)
        guard dataLength > 0 else {
            throw AudioCaptureService.AudioCaptureError.cannotAllocateBuffer
        }

        guard let destination = pcmBuffer.mutableAudioBufferList.pointee.mBuffers.mData else {
            throw AudioCaptureService.AudioCaptureError.cannotAllocateBuffer
        }

        let status = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: dataLength, destination: destination)
        guard status == kCMBlockBufferNoErr else {
            throw AudioCaptureService.AudioCaptureError.cannotAllocateBuffer
        }

        return pcmBuffer
    }

    private func resolveCaptureDevice() throws -> AVCaptureDevice {
        let availableDevices = microphoneCaptureDevices()

        if let deviceID {
            if let matchedDevice = availableDevices.first(where: { $0.uniqueID == deviceID }) {
                return matchedDevice
            }
            throw AudioCaptureService.AudioCaptureError.selectedInputDeviceUnavailable(selectedDeviceName ?? "已保存设备")
        }

        if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            return defaultDevice
        }

        if let fallbackDevice = availableDevices.first {
            return fallbackDevice
        }

        throw AudioCaptureService.AudioCaptureError.noInputDevice
    }

    private func updateArtifactFormat(using device: AVCaptureDevice) {
        var sampleRate = mutableArtifact.sampleRate
        var channelCount = mutableArtifact.channelCount

        if let description = device.activeFormat.formatDescription.audioStreamBasicDescription {
            sampleRate = description.mSampleRate
            channelCount = description.mChannelsPerFrame
        }

        mutableArtifact = SessionAudioArtifact(
            id: mutableArtifact.id,
            fileURL: mutableArtifact.fileURL,
            createdAt: mutableArtifact.createdAt,
            sampleRate: sampleRate,
            channelCount: channelCount,
            duration: mutableArtifact.duration,
            inputDevice: mutableArtifact.inputDevice
        )
    }

    private func updateArtifactInputDevice(using device: AVCaptureDevice) {
        let activeInputDevice = ActiveInputDeviceInfo(
            id: device.uniqueID,
            name: device.localizedName,
            selectionMode: deviceID == nil ? .systemDefault : .specificDevice
        )
        stateQueue.sync {
            mutableArtifact = SessionAudioArtifact(
                id: mutableArtifact.id,
                fileURL: mutableArtifact.fileURL,
                createdAt: mutableArtifact.createdAt,
                sampleRate: mutableArtifact.sampleRate,
                channelCount: mutableArtifact.channelCount,
                duration: mutableArtifact.duration,
                inputDevice: activeInputDevice
            )
        }
    }

    private func installObservers(for device: AVCaptureDevice) {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: captureSession,
                queue: nil
            ) { [weak self] notification in
                guard let self else { return }
                let runtimeError = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
                let deviceName = device.localizedName
                print("[AudioCaptureService] runtime notification error=\(runtimeError?.localizedDescription ?? "unknown")")
                self.reportFailure(
                    runtimeError.map { _ in
                        AudioCaptureService.AudioCaptureError.selectedInputDeviceStartFailed(deviceName)
                    } ?? AudioCaptureService.AudioCaptureError.selectedInputDeviceStartFailed(deviceName)
                )
            }
        )

        observers.append(
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: device,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                let deviceName = device.localizedName
                print("[AudioCaptureService] device disconnected name=\(deviceName) id=\(device.uniqueID)")
                self.reportFailure(AudioCaptureService.AudioCaptureError.selectedInputDeviceUnavailable(deviceName))
            }
        )
    }

    private func reportFailure(_ error: Error) {
        let shouldNotify = stateQueue.sync { () -> Bool in
            if didReportFailure || isStopping || isCancelled {
                return false
            }
            didReportFailure = true
            return true
        }

        guard shouldNotify else { return }
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        cleanup(removeArtifact: true)
        onFailure(error)
    }

    private func cleanup(removeArtifact: Bool = false) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        audioDataOutput?.setSampleBufferDelegate(nil, queue: nil)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        audioDataOutput = nil
        deviceInput = nil
        audioFile = nil
        currentFormat = nil
        if removeArtifact {
            try? FileManager.default.removeItem(at: mutableArtifact.fileURL)
        }
    }
}

private extension CMFormatDescription {
    var audioStreamBasicDescription: AudioStreamBasicDescription? {
        guard let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(self) else {
            return nil
        }
        return pointer.pointee
    }
}

extension AudioCaptureService: @unchecked Sendable {}
extension AVCaptureAudioRecordingSession: @unchecked Sendable {}
