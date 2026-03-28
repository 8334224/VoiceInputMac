import XCTest
@testable import VoiceInputMac

@MainActor
final class SettingsStoreMicrophoneTests: XCTestCase {
    func testUpdatingSpecificMicrophonePersistsAcrossStoreReinitialization() {
        let defaults = makeDefaults()
        let provider = FakeMicrophoneDeviceProvider(
            devices: [
                .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true),
                .init(id: "usb-1", name: "USB 麦克风", isSystemDefault: false)
            ],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )

        let store = SettingsStore(userDefaults: defaults, microphoneDeviceProvider: provider)
        store.selectMicrophoneDevice(id: "usb-1")

        let restored = SettingsStore(userDefaults: defaults, microphoneDeviceProvider: provider)
        XCTAssertEqual(restored.settings.microphoneSelectionMode, .specificDevice)
        XCTAssertEqual(restored.settings.selectedMicrophoneID, "usb-1")
        XCTAssertEqual(restored.settings.selectedMicrophoneName, "USB 麦克风")
    }

    func testSystemDefaultSelectionPersists() {
        let defaults = makeDefaults()
        let provider = FakeMicrophoneDeviceProvider(
            devices: [.init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)],
            defaultDevice: .init(id: "built-in", name: "MacBook 麦克风", isSystemDefault: true)
        )

        let store = SettingsStore(userDefaults: defaults, microphoneDeviceProvider: provider)
        store.selectMicrophoneDevice(id: "built-in")
        store.useSystemDefaultMicrophone()

        let restored = SettingsStore(userDefaults: defaults, microphoneDeviceProvider: provider)
        XCTAssertEqual(restored.settings.microphoneSelectionMode, .systemDefault)
    }

    func testInvalidStoredMicrophoneValueDoesNotCrashAndNormalizesToDefault() throws {
        let defaults = makeDefaults()
        let invalidJSON = """
        {
          "microphoneSelectionMode": "specificDevice",
          "selectedMicrophoneID": "   ",
          "selectedMicrophoneName": "旧 USB 麦克风"
        }
        """.data(using: .utf8)!
        defaults.set(invalidJSON, forKey: "voice_input_mac_settings")

        let provider = FakeMicrophoneDeviceProvider(devices: [], defaultDevice: nil)
        let store = SettingsStore(userDefaults: defaults, microphoneDeviceProvider: provider)

        XCTAssertEqual(store.settings.microphoneSelectionMode, .systemDefault)
        XCTAssertEqual(store.settings.selectedMicrophoneID, "")
        XCTAssertEqual(store.settings.selectedMicrophoneName, "")
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "SettingsStoreMicrophoneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private struct FakeMicrophoneDeviceProvider: MicrophoneDeviceProviding {
    let devices: [MicrophoneDeviceInfo]
    let defaultDevice: MicrophoneDeviceInfo?

    func availableInputDevices() throws -> [MicrophoneDeviceInfo] { devices }
    func systemDefaultInputDevice() -> MicrophoneDeviceInfo? { defaultDevice }
}
