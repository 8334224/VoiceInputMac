import XCTest
@testable import VoiceInputMac

final class DefaultInputDeviceChangeMonitorTests: XCTestCase {
    func testDefaultInputDeviceChangeTriggersCallback() async {
        let provider = FixedDefaultDeviceProvider(
            defaultDevice: .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: true)
        )
        let backend = FakeDefaultInputDeviceMonitoringBackend(currentUID: "built-in")
        let monitor = CoreAudioDefaultInputDeviceChangeMonitor(
            deviceProvider: provider,
            backend: backend
        )

        let expectation = expectation(description: "default input changed")
        let box = LockedDefaultInputValueBox<DefaultInputDeviceChangeEvent?>(nil)
        monitor.startObserving { event in
            box.withLock { $0 = event }
            expectation.fulfill()
        }

        backend.currentUID = "usb-1"
        backend.emitChange()

        await fulfillment(of: [expectation], timeout: 1.0)
        let event = box.value
        XCTAssertEqual(event?.deviceID, "usb-1")
        XCTAssertEqual(event?.deviceName, "USB 麦克风")
    }

    func testRepeatedSameDefaultDeviceDoesNotTriggerStateChurn() async {
        let provider = FixedDefaultDeviceProvider(
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let backend = FakeDefaultInputDeviceMonitoringBackend(currentUID: "built-in")
        let monitor = CoreAudioDefaultInputDeviceChangeMonitor(
            deviceProvider: provider,
            backend: backend
        )

        let box = LockedDefaultInputValueBox(0)
        monitor.startObserving { _ in
            box.withLock { $0 += 1 }
        }

        backend.currentUID = "built-in"
        backend.emitChange()
        backend.emitChange()

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(box.value, 0)
    }

    func testStopObservingPreventsFurtherCallbacks() async {
        let provider = FixedDefaultDeviceProvider(
            defaultDevice: .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: true)
        )
        let backend = FakeDefaultInputDeviceMonitoringBackend(currentUID: "built-in")
        let monitor = CoreAudioDefaultInputDeviceChangeMonitor(
            deviceProvider: provider,
            backend: backend
        )

        let box = LockedDefaultInputValueBox(0)
        monitor.startObserving { _ in
            box.withLock { $0 += 1 }
        }
        monitor.stopObserving()

        backend.currentUID = "usb-1"
        backend.emitChange()

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(box.value, 0)
    }
}

private struct FixedDefaultDeviceProvider: MicrophoneDeviceProviding {
    let defaultDevice: MicrophoneDeviceInfo?

    func availableInputDevices() throws -> [MicrophoneDeviceInfo] {
        defaultDevice.map { [$0] } ?? []
    }

    func systemDefaultInputDevice() -> MicrophoneDeviceInfo? {
        defaultDevice
    }
}

private final class FakeDefaultInputDeviceMonitoringBackend: DefaultInputDeviceMonitoringBackend, @unchecked Sendable {
    var currentUID: String?
    private var onChange: (() -> Void)?

    init(currentUID: String?) {
        self.currentUID = currentUID
    }

    func currentDefaultInputDeviceUID() -> String? {
        currentUID
    }

    func startObserving(_ onChange: @escaping @Sendable () -> Void) throws {
        self.onChange = onChange
    }

    func stopObserving() {
        onChange = nil
    }

    func emitChange() {
        onChange?()
    }
}

private final class LockedDefaultInputValueBox<Value>: @unchecked Sendable {
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
