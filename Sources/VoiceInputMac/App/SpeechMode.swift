import Foundation

enum SpeechMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case general
    case technical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "通用模式"
        case .technical:
            return "技术模式"
        }
    }

    var description: String {
        switch self {
        case .general:
            return "适合日常聊天、普通中文输入。"
        case .technical:
            return "优先识别技术词。"
        }
    }
}
