import XCTest
@testable import VoiceInputMac

final class FixedAudioExperimentRunnerTests: XCTestCase {
    func testRunLocalAudioExperimentFromEnvironment() async throws {
        let env = ProcessInfo.processInfo.environment

        guard let audioPath = env["VOICEINPUT_FIXED_AUDIO_PATH"], !audioPath.isEmpty else {
            throw XCTSkip("Set VOICEINPUT_FIXED_AUDIO_PATH to run the fixed-audio experiment.")
        }

        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            XCTFail("Audio file does not exist at path: \(audioURL.path)")
            return
        }

        let pipeline = DictationPipeline()
        let settings = AppSettings()

        if let modeValue = env["VOICEINPUT_FIXED_AUDIO_MODE"],
           let mode = ReRecognitionOrderMode(rawValue: modeValue) {
            pipeline.setReRecognitionOrderMode(mode)
        }

        let sampleLabel = env["VOICEINPUT_FIXED_AUDIO_SAMPLE_LABEL"]
            .flatMap(ReRecognitionExperimentSampleLabel.init(rawValue:))
        let sessionTag = env["VOICEINPUT_FIXED_AUDIO_SESSION_TAG"]
        pipeline.setReRecognitionExperimentTag(sampleLabel: sampleLabel, sessionTag: sessionTag)

        let exportURL = try await pipeline.runFixedAudioExperimentAndSave(
            audioFileURL: audioURL,
            settings: settings
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        print("[FixedAudioExperiment] saved JSON to \(exportURL.path)")
    }
}
