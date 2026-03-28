import AVFoundation
import XCTest
@testable import VoiceInputMac

final class AudioCaptureServiceMicrophoneSelectionTests: XCTestCase {
    func testSystemDefaultModeUsesDefaultPath() throws {
        let backend = FakeAudioCaptureBackend()
        let provider = FakeCaptureDeviceProvider(
            devices: [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let service = AudioCaptureService(deviceProvider: provider, backend: backend)

        let artifact = try service.startSession(
            selection: .init(mode: .systemDefault, selectedMicrophoneID: "", selectedMicrophoneName: ""),
            onBuffer: { _, _ in }
        )

        XCTAssertEqual(backend.lastStartedDeviceID, nil)
        XCTAssertEqual(artifact.id, backend.recordingSession.artifact.id)
    }

    func testSpecificDeviceModePassesSelectedIDToBackend() throws {
        let backend = FakeAudioCaptureBackend()
        let provider = FakeCaptureDeviceProvider(
            devices: [
                .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true),
                .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false)
            ],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let service = AudioCaptureService(deviceProvider: provider, backend: backend)

        _ = try service.startSession(
            selection: .init(mode: .specificDevice, selectedMicrophoneID: "usb-1", selectedMicrophoneName: "USB 麦克风"),
            onBuffer: { _, _ in }
        )

        XCTAssertEqual(backend.lastStartedDeviceID, "usb-1")
    }

    func testMissingSelectedDeviceThrowsExpectedError() {
        let backend = FakeAudioCaptureBackend()
        let provider = FakeCaptureDeviceProvider(
            devices: [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let service = AudioCaptureService(deviceProvider: provider, backend: backend)

        XCTAssertThrowsError(
            try service.startSession(
                selection: .init(mode: .specificDevice, selectedMicrophoneID: "usb-missing", selectedMicrophoneName: "USB 麦克风"),
                onBuffer: { _, _ in }
            )
        ) { error in
            XCTAssertEqual(
                error as? AudioCaptureService.AudioCaptureError,
                .selectedInputDeviceUnavailable("USB 麦克风")
            )
        }
    }

    func testStartupFailureDoesNotLeaveServiceInRunningState() throws {
        let backend = FakeAudioCaptureBackend()
        backend.startError = AudioCaptureService.AudioCaptureError.selectedInputDeviceStartFailed("USB 麦克风")
        let provider = FakeCaptureDeviceProvider(
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

        backend.startError = nil
        _ = try service.startSession(
            selection: .init(mode: .specificDevice, selectedMicrophoneID: "usb-1", selectedMicrophoneName: "USB 麦克风"),
            onBuffer: { _, _ in }
        )

        XCTAssertEqual(backend.startCallCount, 2)
    }

    func testAlreadyRunningBehaviorIsPreserved() throws {
        let backend = FakeAudioCaptureBackend()
        let provider = FakeCaptureDeviceProvider(
            devices: [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let service = AudioCaptureService(deviceProvider: provider, backend: backend)

        _ = try service.startSession(
            selection: .init(mode: .systemDefault, selectedMicrophoneID: "", selectedMicrophoneName: ""),
            onBuffer: { _, _ in }
        )

        XCTAssertThrowsError(
            try service.startSession(
                selection: .init(mode: .systemDefault, selectedMicrophoneID: "", selectedMicrophoneName: ""),
                onBuffer: { _, _ in }
            )
        ) { error in
            XCTAssertEqual(error as? AudioCaptureService.AudioCaptureError, .alreadyRunning)
        }
    }
}

private struct FakeCaptureDeviceProvider: MicrophoneDeviceProviding {
    let devices: [MicrophoneDeviceInfo]
    let defaultDevice: MicrophoneDeviceInfo?

    func availableInputDevices() throws -> [MicrophoneDeviceInfo] { devices }
    func systemDefaultInputDevice() -> MicrophoneDeviceInfo? { defaultDevice }
}

private final class FakeAudioCaptureBackend: AudioCaptureBackend {
    var startError: Error?
    var lastStartedDeviceID: String?
    var startCallCount = 0
    let recordingSession = FakeRecordingSession()

    func startSession(
        deviceID: String?,
        selectedDeviceName: String?,
        onBuffer: @escaping AudioCaptureService.AudioBufferHandler,
        onFailure: @escaping @Sendable (Error) -> Void
    ) throws -> any AudioCaptureRecordingSession {
        startCallCount += 1
        lastStartedDeviceID = deviceID
        if let startError {
            throw startError
        }
        return recordingSession
    }
}

private final class FakeRecordingSession: AudioCaptureRecordingSession {
    let artifact = SessionAudioArtifact(
        id: UUID(),
        fileURL: URL(fileURLWithPath: "/tmp/fake-audio.caf"),
        createdAt: Date(),
        sampleRate: 16_000,
        channelCount: 1,
        duration: 0.25,
        inputDevice: nil
    )
    var activeInputDevice: ActiveInputDeviceInfo {
        artifact.inputDevice ?? ActiveInputDeviceInfo(id: nil, name: "当前输入设备", selectionMode: .systemDefault)
    }

    private(set) var didStop = false
    private(set) var didCancel = false

    func stop() throws -> SessionAudioArtifact {
        didStop = true
        return artifact
    }

    func cancel() {
        didCancel = true
    }
}
