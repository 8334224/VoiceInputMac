import XCTest
@testable import VoiceInputMac

@MainActor
final class SettingsStoreMicrophoneHotplugTests: XCTestCase {
    func testSpecificDeviceDisconnectMarksSelectionUnavailableWithoutClearingChoice() async {
        let defaults = makeDefaults()
        let provider = MutableMicrophoneDeviceProvider(
            devices: [
                .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true),
                .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false)
            ],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let monitor = FakeMicrophoneDeviceChangeMonitor()
        let store = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: provider,
            microphoneDeviceChangeMonitor: monitor
        )

        store.selectMicrophoneDevice(id: "usb-1")
        provider.devices = [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)]

        monitor.emit(.init(kind: .disconnected, deviceID: "usb-1", deviceName: "USB 麦克风"))
        await settleHotplugReload()

        XCTAssertEqual(store.settings.microphoneSelectionMode, .specificDevice)
        XCTAssertEqual(store.settings.selectedMicrophoneID, "usb-1")
        XCTAssertTrue(store.microphoneStatus.isError)
        XCTAssertEqual(store.microphoneStatus.title, "所选麦克风不可用")
    }

    func testSpecificDeviceReconnectRestoresAvailableStatus() async {
        let defaults = makeDefaults()
        let provider = MutableMicrophoneDeviceProvider(
            devices: [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let monitor = FakeMicrophoneDeviceChangeMonitor()
        let store = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: provider,
            microphoneDeviceChangeMonitor: monitor
        )

        store.settings.microphoneSelectionMode = .specificDevice
        store.settings.selectedMicrophoneID = "usb-1"
        store.settings.selectedMicrophoneName = "USB 麦克风"
        store.reloadMicrophoneDevices()
        XCTAssertTrue(store.microphoneStatus.isError)

        provider.devices.append(.init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false))
        monitor.emit(.init(kind: .connected, deviceID: "usb-1", deviceName: "USB 麦克风"))
        await settleHotplugReload()

        XCTAssertFalse(store.microphoneStatus.isError)
        XCTAssertEqual(store.microphoneStatus.title, "已指定麦克风")
    }

    func testSystemDefaultModeRefreshesStatusWhenDefaultDeviceChanges() async {
        let defaults = makeDefaults()
        let provider = MutableMicrophoneDeviceProvider(
            devices: [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let monitor = FakeMicrophoneDeviceChangeMonitor()
        let store = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: provider,
            microphoneDeviceChangeMonitor: monitor
        )

        XCTAssertTrue(store.microphoneStatus.detail.contains("MacBook 麦克风"))

        provider.devices = [.init(id: "usb-2", name: "USB 麦克风", isSystemDefault: true)]
        provider.defaultDevice = .init(id: "usb-2", name: "USB 麦克风", isSystemDefault: true)
        monitor.emit(.init(kind: .connected, deviceID: "usb-2", deviceName: "USB 麦克风"))
        await settleHotplugReload()

        XCTAssertTrue(store.microphoneStatus.detail.contains("USB 麦克风"))
    }

    func testHotplugDoesNotRequireSettingsViewToBeOpen() async {
        let defaults = makeDefaults()
        let provider = MutableMicrophoneDeviceProvider(
            devices: [],
            defaultDevice: nil
        )
        let monitor = FakeMicrophoneDeviceChangeMonitor()
        let store = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: provider,
            microphoneDeviceChangeMonitor: monitor
        )

        XCTAssertTrue(store.microphoneDevices.isEmpty)

        provider.devices = [.init(id: "usb-1", name: "USB 麦克风", isSystemDefault: true)]
        provider.defaultDevice = .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: true)
        monitor.emit(.init(kind: .connected, deviceID: "usb-1", deviceName: "USB 麦克风"))
        await settleHotplugReload()

        XCTAssertEqual(store.microphoneDevices.map(\.id), ["usb-1"])
    }

    func testRepeatedHotplugNotificationsDoNotDuplicateState() async {
        let defaults = makeDefaults()
        let provider = MutableMicrophoneDeviceProvider(
            devices: [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let monitor = FakeMicrophoneDeviceChangeMonitor()
        let store = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: provider,
            microphoneDeviceChangeMonitor: monitor
        )

        provider.devices.append(.init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false))
        monitor.emit(.init(kind: .connected, deviceID: "usb-1", deviceName: "USB 麦克风"))
        monitor.emit(.init(kind: .connected, deviceID: "usb-1", deviceName: "USB 麦克风"))
        await settleHotplugReload()

        XCTAssertEqual(store.microphoneDevices.filter { $0.id == "usb-1" }.count, 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "SettingsStoreMicrophoneHotplugTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func settleHotplugReload() async {
        await Task.yield()
        await Task.yield()
    }
}

private final class MutableMicrophoneDeviceProvider: MicrophoneDeviceProviding, @unchecked Sendable {
    var devices: [MicrophoneDeviceInfo]
    var defaultDevice: MicrophoneDeviceInfo?

    init(devices: [MicrophoneDeviceInfo], defaultDevice: MicrophoneDeviceInfo?) {
        self.devices = devices
        self.defaultDevice = defaultDevice
    }

    func availableInputDevices() throws -> [MicrophoneDeviceInfo] { devices }
    func systemDefaultInputDevice() -> MicrophoneDeviceInfo? { defaultDevice }
}

private final class FakeMicrophoneDeviceChangeMonitor: MicrophoneDeviceChangeObserving, @unchecked Sendable {
    private var callback: (@MainActor (MicrophoneDeviceChangeEvent) -> Void)?

    func startObserving(_ onChange: @escaping @MainActor (MicrophoneDeviceChangeEvent) -> Void) {
        callback = onChange
    }

    func stopObserving() {
        callback = nil
    }

    @MainActor
    func emit(_ event: MicrophoneDeviceChangeEvent) {
        callback?(event)
    }
}
