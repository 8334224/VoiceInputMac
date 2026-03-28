import Foundation
import XCTest
@testable import VoiceInputMac

final class AudioCaptureServiceDeviceDisconnectTests: XCTestCase {
    func testRuntimeDisconnectReportsExpectedErrorAndAllowsRestart() throws {
        let backend = RuntimeFailureAudioCaptureBackend()
        let provider = FixedCaptureDeviceProvider(
            devices: [.init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false)],
            defaultDevice: nil
        )
        let service = AudioCaptureService(deviceProvider: provider, backend: backend)

        let failureExpectation = expectation(description: "runtime failure callback")
        let receivedError = RuntimeLockedValueBox<Error?>(nil)

        _ = try service.startSession(
            selection: .init(mode: .specificDevice, selectedMicrophoneID: "usb-1", selectedMicrophoneName: "USB 麦克风"),
            onBuffer: { _, _ in },
            onFailure: { error in
                receivedError.withLock { $0 = error }
                failureExpectation.fulfill()
            }
        )

        backend.emitRuntimeFailure(AudioCaptureService.AudioCaptureError.selectedInputDeviceUnavailable("USB 麦克风"))

        wait(for: [failureExpectation], timeout: 1.0)
        XCTAssertEqual(receivedError.value as? AudioCaptureService.AudioCaptureError, .selectedInputDeviceUnavailable("USB 麦克风"))

        _ = try service.startSession(
            selection: .init(mode: .specificDevice, selectedMicrophoneID: "usb-1", selectedMicrophoneName: "USB 麦克风"),
            onBuffer: { _, _ in }
        )
        XCTAssertEqual(backend.startCallCount, 2)
    }

    func testRuntimeFailureCancelsExistingSessionWithoutSwitchingDevice() throws {
        let backend = RuntimeFailureAudioCaptureBackend()
        let provider = FixedCaptureDeviceProvider(
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

        backend.emitRuntimeFailure(AudioCaptureService.AudioCaptureError.selectedInputDeviceStartFailed("USB 麦克风"))

        XCTAssertEqual(backend.lastStartedDeviceID, "usb-1")
        XCTAssertFalse(backend.didFallbackToDefault)
    }
}

private final class RuntimeLockedValueBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ storage: Value) {
        self.storage = storage
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withLock(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}

private struct FixedCaptureDeviceProvider: MicrophoneDeviceProviding {
    let devices: [MicrophoneDeviceInfo]
    let defaultDevice: MicrophoneDeviceInfo?

    func availableInputDevices() throws -> [MicrophoneDeviceInfo] { devices }
    func systemDefaultInputDevice() -> MicrophoneDeviceInfo? { defaultDevice }
}

private final class RuntimeFailureAudioCaptureBackend: AudioCaptureBackend {
    var lastStartedDeviceID: String?
    var startCallCount = 0
    var didFallbackToDefault = false

    private var runtimeFailureHandler: ((Error) -> Void)?

    func startSession(
        deviceID: String?,
        selectedDeviceName: String?,
        onBuffer: @escaping AudioCaptureService.AudioBufferHandler,
        onFailure: @escaping @Sendable (Error) -> Void
    ) throws -> any AudioCaptureRecordingSession {
        startCallCount += 1
        lastStartedDeviceID = deviceID
        if deviceID == nil {
            didFallbackToDefault = true
        }
        runtimeFailureHandler = onFailure
        return RuntimeFailureRecordingSession()
    }

    func emitRuntimeFailure(_ error: Error) {
        runtimeFailureHandler?(error)
    }
}

private final class RuntimeFailureRecordingSession: AudioCaptureRecordingSession {
    let artifact = SessionAudioArtifact(
        id: UUID(),
        fileURL: URL(fileURLWithPath: "/tmp/runtime-failure-audio.caf"),
        createdAt: Date(),
        sampleRate: 16_000,
        channelCount: 1,
        duration: 0.5,
        inputDevice: nil
    )
    var activeInputDevice: ActiveInputDeviceInfo {
        artifact.inputDevice ?? ActiveInputDeviceInfo(id: nil, name: "当前输入设备", selectionMode: .systemDefault)
    }

    func stop() throws -> SessionAudioArtifact {
        artifact
    }

    func cancel() {}
}
