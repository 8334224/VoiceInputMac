import Foundation

struct SuspicionFlag: Equatable, Sendable {
    let code: String
    let detail: String
    let severity: Int
}

struct TranscriptSegment: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let isFinal: Bool
    let source: String
    let suspicionFlags: [SuspicionFlag]
}

struct RecognitionResultSnapshot: Equatable, Sendable {
    let rawText: String
    let displayText: String
    let segments: [TranscriptSegment]
    let isFinal: Bool
    let source: String

    static func empty(source: String) -> RecognitionResultSnapshot {
        RecognitionResultSnapshot(
            rawText: "",
            displayText: "",
            segments: [],
            isFinal: false,
            source: source
        )
    }
}

struct SessionAudioArtifact: Equatable, Sendable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
    let sampleRate: Double
    let channelCount: UInt32
    var duration: TimeInterval
    let inputDevice: ActiveInputDeviceInfo?
}

struct ActiveInputDeviceInfo: Equatable, Sendable {
    let id: String?
    let name: String
    let selectionMode: MicrophoneSelectionMode

    var isSystemDefaultSelection: Bool {
        selectionMode == .systemDefault
    }
}

struct DictationSessionRecord: Equatable, Sendable {
    let id: UUID
    let transcript: RecognitionResultSnapshot
    let audio: SessionAudioArtifact?
}
