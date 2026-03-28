import XCTest
@testable import VoiceInputMac

final class AudioCaptureServiceActiveInputDeviceTests: XCTestCase {
    func testSystemDefaultModeReturnsActualInputDeviceName() throws {
        let backend = ActiveInputBackend(recordingSession: ActiveInputRecordingSession(
            artifact: makeArtifact(device: .init(id: "built-in", name: "MacBook 麦克风", selectionMode: .systemDefault))
        ))
        let provider = ActiveInputProvider(
            devices: [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let service = AudioCaptureService(deviceProvider: provider, backend: backend)

        let artifact = try service.startSession(
            selection: .init(mode: .systemDefault, selectedMicrophoneID: "", selectedMicrophoneName: ""),
            onBuffer: { _, _ in }
        )

        XCTAssertEqual(artifact.inputDevice?.name, "MacBook 麦克风")
        XCTAssertEqual(artifact.inputDevice?.selectionMode, .systemDefault)
        XCTAssertEqual(service.activeInputDeviceInfo()?.name, "MacBook 麦克风")
    }

    func testSpecificDeviceModeReturnsBoundDeviceName() throws {
        let backend = ActiveInputBackend(recordingSession: ActiveInputRecordingSession(
            artifact: makeArtifact(device: .init(id: "usb-1", name: "USB 麦克风", selectionMode: .specificDevice))
        ))
        let provider = ActiveInputProvider(
            devices: [.init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false)],
            defaultDevice: nil
        )
        let service = AudioCaptureService(deviceProvider: provider, backend: backend)

        let artifact = try service.startSession(
            selection: .init(mode: .specificDevice, selectedMicrophoneID: "usb-1", selectedMicrophoneName: "旧名字"),
            onBuffer: { _, _ in }
        )

        XCTAssertEqual(artifact.inputDevice?.name, "USB 麦克风")
        XCTAssertEqual(artifact.inputDevice?.selectionMode, .specificDevice)
        XCTAssertEqual(service.activeInputDeviceInfo()?.id, "usb-1")
    }

    func testStartFailureDoesNotRetainPreviousActiveDevice() {
        let backend = ActiveInputBackend(recordingSession: ActiveInputRecordingSession(
            artifact: makeArtifact(device: .init(id: "usb-1", name: "USB 麦克风", selectionMode: .specificDevice))
        ))
        backend.startError = AudioCaptureService.AudioCaptureError.selectedInputDeviceStartFailed("USB 麦克风")
        let provider = ActiveInputProvider(
            devices: [.init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false)],
            defaultDevice: nil
        )
        let service = AudioCaptureService(deviceProvider: provider, backend: backend)

        XCTAssertThrowsError(
            try service.startSession(
                selection: .init(mode: .specificDevice, selectedMicrophoneID: "usb-1", selectedMicrophoneName: "USB 麦克风"),
                onBuffer: { _, _ in }
            )
        )

        XCTAssertNil(service.activeInputDeviceInfo())
    }

    func testRuntimeFailureClearsActiveDeviceInfo() throws {
        let backend = ActiveInputBackend(recordingSession: ActiveInputRecordingSession(
            artifact: makeArtifact(device: .init(id: "usb-1", name: "USB 麦克风", selectionMode: .specificDevice))
        ))
        let provider = ActiveInputProvider(
            devices: [.init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false)],
            defaultDevice: nil
        )
        let service = AudioCaptureService(deviceProvider: provider, backend: backend)
        let expectation = expectation(description: "runtime failure")

        _ = try service.startSession(
            selection: .init(mode: .specificDevice, selectedMicrophoneID: "usb-1", selectedMicrophoneName: "USB 麦克风"),
            onBuffer: { _, _ in },
            onFailure: { _ in expectation.fulfill() }
        )

        XCTAssertEqual(service.activeInputDeviceInfo()?.name, "USB 麦克风")
        backend.emitFailure(AudioCaptureService.AudioCaptureError.selectedInputDeviceUnavailable("USB 麦克风"))
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNil(service.activeInputDeviceInfo())
    }

    private func makeArtifact(device: ActiveInputDeviceInfo?) -> SessionAudioArtifact {
        SessionAudioArtifact(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/active-input.caf"),
            createdAt: Date(),
            sampleRate: 16_000,
            channelCount: 1,
            duration: 0.25,
            inputDevice: device
        )
    }
}

private struct ActiveInputProvider: MicrophoneDeviceProviding {
    let devices: [MicrophoneDeviceInfo]
    let defaultDevice: MicrophoneDeviceInfo?

    func availableInputDevices() throws -> [MicrophoneDeviceInfo] { devices }
    func systemDefaultInputDevice() -> MicrophoneDeviceInfo? { defaultDevice }
}

private final class ActiveInputBackend: AudioCaptureBackend {
    var startError: Error?
    private let recordingSession: ActiveInputRecordingSession
    private var onFailure: ((Error) -> Void)?

    init(recordingSession: ActiveInputRecordingSession) {
        self.recordingSession = recordingSession
    }

    func startSession(
        deviceID: String?,
        selectedDeviceName: String?,
        onBuffer: @escaping AudioCaptureService.AudioBufferHandler,
        onFailure: @escaping @Sendable (Error) -> Void
    ) throws -> any AudioCaptureRecordingSession {
        if let startError { throw startError }
        self.onFailure = onFailure
        return recordingSession
    }

    func emitFailure(_ error: Error) {
        onFailure?(error)
    }
}

private final class ActiveInputRecordingSession: AudioCaptureRecordingSession {
    let artifact: SessionAudioArtifact
    var activeInputDevice: ActiveInputDeviceInfo {
        artifact.inputDevice ?? ActiveInputDeviceInfo(id: nil, name: "当前输入设备", selectionMode: .systemDefault)
    }

    init(artifact: SessionAudioArtifact) {
        self.artifact = artifact
    }

    func stop() throws -> SessionAudioArtifact { artifact }
    func cancel() {}
}
