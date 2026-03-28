import XCTest
@testable import VoiceInputMac

final class SenseVoiceBackendRunnerTests: XCTestCase {
    func testRunSenseVoiceBackendFromEnvironment() async throws {
        let env = ProcessInfo.processInfo.environment

        guard let audioPath = env["VOICEINPUT_SENSEVOICE_AUDIO_PATH"], !audioPath.isEmpty else {
            throw XCTSkip("Set VOICEINPUT_SENSEVOICE_AUDIO_PATH to run the SenseVoice backend experiment.")
        }

        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            XCTFail("Audio file does not exist at path: \(audioURL.path)")
            return
        }

        let backend = SenseVoiceSmallRecognitionBackend()
        XCTAssertTrue(SenseVoiceSmallRecognitionBackend.isAvailable, "SenseVoice-Small backend is not available.")

        let localeIdentifier = env["VOICEINPUT_SENSEVOICE_LOCALE"] ?? "zh-CN"
        let snapshot = try await backend.transcribeAudioFile(
            at: audioURL,
            configuration: RecognitionConfiguration(
                localeIdentifier: localeIdentifier,
                contextualPhrases: [],
                addsPunctuation: true,
                requiresOnDeviceRecognition: false
            )
        )

        XCTAssertFalse(snapshot.displayText.isEmpty)
        print("[SenseVoiceBackend] text=\(snapshot.displayText)")
    }
}
