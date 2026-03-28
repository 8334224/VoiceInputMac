import Foundation
import XCTest
@testable import VoiceInputMac

final class FirstPassBackendComparisonRunnerTests: XCTestCase {
    private struct ComparisonExport: Codable {
        struct BackendResult: Codable {
            let backend: String
            let displayText: String
            let rawText: String
            let source: String
        }

        let sessionTag: String
        let exportedAt: Date
        let audioPath: String
        let localeIdentifier: String
        let results: [BackendResult]
    }

    func testRunFirstPassComparisonFromEnvironment() async throws {
        let env = ProcessInfo.processInfo.environment

        guard let audioPath = env["VOICEINPUT_BASELINE_AUDIO_PATH"], !audioPath.isEmpty else {
            throw XCTSkip("Set VOICEINPUT_BASELINE_AUDIO_PATH to run first-pass backend comparison.")
        }

        let audioURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            XCTFail("Audio file does not exist at path: \(audioURL.path)")
            return
        }

        let localeIdentifier = env["VOICEINPUT_BASELINE_LOCALE"] ?? "zh-CN"
        let sessionTag = (env["VOICEINPUT_BASELINE_SESSION_TAG"]?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "baseline"

        let configuration = RecognitionConfiguration(
            localeIdentifier: localeIdentifier,
            contextualPhrases: [],
            addsPunctuation: true,
            requiresOnDeviceRecognition: false
        )

        let backends: [RecognitionBackend] = [
            AppleSpeechRecognitionBackend(),
            SenseVoiceSmallRecognitionBackend()
        ]

        let results = try await backends.asyncMap { backend in
            let snapshot = try await backend.transcribeAudioFile(at: audioURL, configuration: configuration)
            return ComparisonExport.BackendResult(
                backend: backend.identifier,
                displayText: snapshot.displayText,
                rawText: snapshot.rawText,
                source: snapshot.source
            )
        }

        let export = ComparisonExport(
            sessionTag: sessionTag,
            exportedAt: Date(),
            audioPath: audioURL.path,
            localeIdentifier: localeIdentifier,
            results: results
        )

        let exportURL = try save(export: export)
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        print("[FirstPassComparison] saved JSON to \(exportURL.path)")
    }

    private func save(export: ComparisonExport) throws -> URL {
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = appSupportURL
            .appendingPathComponent("VoiceInputMac", isDirectory: true)
            .appendingPathComponent("ReRecognitionExperiments", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: export.exportedAt)
        let fileURL = directoryURL.appendingPathComponent("\(export.sessionTag)__first-pass__\(timestamp).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(export).write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private extension Array {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async throws -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            try Task.checkCancellation()
            results.append(try await transform(element))
        }
        return results
    }
}
