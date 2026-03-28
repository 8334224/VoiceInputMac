import XCTest
@testable import VoiceInputMac

@MainActor
final class SettingsStoreDefaultInputChangeTests: XCTestCase {
    func testSystemDefaultModeUpdatesStatusWhenDefaultInputChanges() {
        let defaults = makeDefaults()
        let provider = MutableDefaultAwareMicrophoneDeviceProvider(
            devices: [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let hotplugMonitor = LocalFakeMicrophoneDeviceChangeMonitor()
        let defaultMonitor = FakeDefaultInputDeviceChangeMonitor()
        let store = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: provider,
            microphoneDeviceChangeMonitor: hotplugMonitor,
            defaultInputDeviceChangeMonitor: defaultMonitor
        )

        XCTAssertTrue(store.microphoneStatus.detail.contains("MacBook 麦克风"))
        XCTAssertTrue(store.microphoneMenuLabel().contains("MacBook 麦克风"))

        provider.devices = [.init(id: "usb-1", name: "USB 麦克风", isSystemDefault: true)]
        provider.defaultDevice = .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: true)

        defaultMonitor.emit(.init(deviceID: "usb-1", deviceName: "USB 麦克风"))

        XCTAssertTrue(store.microphoneStatus.detail.contains("USB 麦克风"))
        XCTAssertTrue(store.microphoneMenuLabel().contains("USB 麦克风"))
    }

    func testSpecificDeviceModeDoesNotOverrideSelectionWhenDefaultInputChanges() {
        let defaults = makeDefaults()
        let provider = MutableDefaultAwareMicrophoneDeviceProvider(
            devices: [
                .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true),
                .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false)
            ],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let defaultMonitor = FakeDefaultInputDeviceChangeMonitor()
        let store = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: provider,
            microphoneDeviceChangeMonitor: LocalFakeMicrophoneDeviceChangeMonitor(),
            defaultInputDeviceChangeMonitor: defaultMonitor
        )

        store.selectMicrophoneDevice(id: "usb-1")
        provider.devices = [
            .init(id: "usb-2", name: "USB 麦克风 2", isSystemDefault: true),
            .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false)
        ]
        provider.defaultDevice = .init(id: "usb-2", name: "USB 麦克风 2", isSystemDefault: true)

        defaultMonitor.emit(.init(deviceID: "usb-2", deviceName: "USB 麦克风 2"))

        XCTAssertEqual(store.settings.microphoneSelectionMode, MicrophoneSelectionMode.specificDevice)
        XCTAssertEqual(store.settings.selectedMicrophoneID, "usb-1")
        XCTAssertEqual(store.selectedMicrophoneDisplayName(), "USB 麦克风")
    }

    func testDefaultInputChangeAndHotplugRemainConsistentTogether() {
        let defaults = makeDefaults()
        let provider = MutableDefaultAwareMicrophoneDeviceProvider(
            devices: [
                .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true),
                .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false)
            ],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let hotplugMonitor = LocalFakeMicrophoneDeviceChangeMonitor()
        let defaultMonitor = FakeDefaultInputDeviceChangeMonitor()
        let store = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: provider,
            microphoneDeviceChangeMonitor: hotplugMonitor,
            defaultInputDeviceChangeMonitor: defaultMonitor
        )

        provider.devices = [
            .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: true),
            .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: false)
        ]
        provider.defaultDevice = .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: true)

        hotplugMonitor.emit(.init(kind: .connected, deviceID: "usb-1", deviceName: "USB 麦克风"))
        defaultMonitor.emit(.init(deviceID: "usb-1", deviceName: "USB 麦克风"))

        XCTAssertEqual(store.microphoneDevices.first?.id, "usb-1")
        XCTAssertTrue(store.microphoneStatus.detail.contains("USB 麦克风"))
    }

    func testDefaultInputChangeUpdatesStateWithoutSettingsViewOpen() {
        let defaults = makeDefaults()
        let provider = MutableDefaultAwareMicrophoneDeviceProvider(
            devices: [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )
        let defaultMonitor = FakeDefaultInputDeviceChangeMonitor()
        let store = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: provider,
            microphoneDeviceChangeMonitor: LocalFakeMicrophoneDeviceChangeMonitor(),
            defaultInputDeviceChangeMonitor: defaultMonitor
        )

        provider.devices = [.init(id: "usb-1", name: "USB 麦克风", isSystemDefault: true)]
        provider.defaultDevice = .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: true)
        defaultMonitor.emit(.init(deviceID: "usb-1", deviceName: "USB 麦克风"))

        XCTAssertTrue(store.microphoneStatus.detail.contains("USB 麦克风"))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "SettingsStoreDefaultInputChangeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class MutableDefaultAwareMicrophoneDeviceProvider: MicrophoneDeviceProviding, @unchecked Sendable {
    var devices: [MicrophoneDeviceInfo]
    var defaultDevice: MicrophoneDeviceInfo?

    init(devices: [MicrophoneDeviceInfo], defaultDevice: MicrophoneDeviceInfo?) {
        self.devices = devices
        self.defaultDevice = defaultDevice
    }

    func availableInputDevices() throws -> [MicrophoneDeviceInfo] { devices }
    func systemDefaultInputDevice() -> MicrophoneDeviceInfo? { defaultDevice }
}

private final class LocalFakeMicrophoneDeviceChangeMonitor: MicrophoneDeviceChangeObserving, @unchecked Sendable {
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

private final class FakeDefaultInputDeviceChangeMonitor: DefaultInputDeviceChangeObserving, @unchecked Sendable {
    private var callback: (@MainActor (DefaultInputDeviceChangeEvent) -> Void)?

    func startObserving(_ onChange: @escaping @MainActor (DefaultInputDeviceChangeEvent) -> Void) {
        callback = onChange
    }

    func stopObserving() {
        callback = nil
    }

    @MainActor
    func emit(_ event: DefaultInputDeviceChangeEvent) {
        callback?(event)
    }
}
