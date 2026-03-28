import Foundation

enum MicrophoneSelectionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case systemDefault
    case specificDevice

    var id: String { rawValue }
}

struct MicrophoneSelectionConfiguration: Equatable, Sendable {
    let mode: MicrophoneSelectionMode
    let selectedMicrophoneID: String
    let selectedMicrophoneName: String

    var resolvedDeviceID: String? {
        guard mode == .specificDevice else { return nil }
        let trimmed = selectedMicrophoneID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
