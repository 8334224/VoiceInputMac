import XCTest
@testable import VoiceInputMac

final class AppSettingsMicrophoneTests: XCTestCase {
    func testDecodingLegacySettingsFallsBackToSystemDefaultMicrophone() throws {
        let data = Data("{}".utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.microphoneSelectionMode, .systemDefault)
        XCTAssertEqual(decoded.selectedMicrophoneID, "")
        XCTAssertEqual(decoded.selectedMicrophoneName, "")
    }

    func testMicrophoneFieldsRoundTripThroughCodable() throws {
        var settings = AppSettings()
        settings.microphoneSelectionMode = .specificDevice
        settings.selectedMicrophoneID = "usb-mic-1"
        settings.selectedMicrophoneName = "USB 麦克风"

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded.microphoneSelectionMode, .specificDevice)
        XCTAssertEqual(decoded.selectedMicrophoneID, "usb-mic-1")
        XCTAssertEqual(decoded.selectedMicrophoneName, "USB 麦克风")
    }

    func testSystemDefaultAndSpecificDeviceConfigurationsDecodeAsExpected() throws {
        var settings = AppSettings()
        settings.microphoneSelectionMode = .systemDefault
        XCTAssertNil(settings.microphoneSelection.resolvedDeviceID)

        settings.microphoneSelectionMode = .specificDevice
        settings.selectedMicrophoneID = "built-in-1"
        settings.selectedMicrophoneName = "MacBook 麦克风"

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded.microphoneSelection.mode, .specificDevice)
        XCTAssertEqual(decoded.microphoneSelection.resolvedDeviceID, "built-in-1")
    }

    func testEmptySpecificDeviceIDDoesNotResolveToConcreteDevice() {
        var settings = AppSettings()
        settings.microphoneSelectionMode = .specificDevice
        settings.selectedMicrophoneID = "   "
        settings.selectedMicrophoneName = "旧设备"

        XCTAssertNil(settings.microphoneSelection.resolvedDeviceID)
    }
}
