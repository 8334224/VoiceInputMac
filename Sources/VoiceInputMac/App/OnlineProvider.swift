import Foundation

enum OnlineProvider: String, Codable, CaseIterable, Identifiable {
    case volcengineCodingPlan
    case googleGemini
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volcengineCodingPlan:
            return "火山引擎 Coding Plan"
        case .googleGemini:
            return "Google Gemini"
        case .openAICompatible:
            return "通用 OpenAI 兼容"
        }
    }

    var description: String {
        switch self {
        case .volcengineCodingPlan:
            return "使用火山方舟 Coding Plan 的专用地址和 ark-code-latest 模型，适合当前这个语音纠错场景。"
        case .googleGemini:
            return "使用 Google Generative Language v1beta 接口和 Gemini 模型，适合在线纠错与轻量整理。"
        case .openAICompatible:
            return "用于标准 OpenAI 兼容聊天补全接口，可自定义地址和模型。"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .volcengineCodingPlan:
            return "https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions"
        case .googleGemini:
            return "https://generativelanguage.googleapis.com/v1beta"
        case .openAICompatible:
            return "https://your-openai-compatible-endpoint/v1/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .volcengineCodingPlan:
            return "ark-code-latest"
        case .googleGemini:
            return "gemini-3-flash-preview"
        case .openAICompatible:
            return ""
        }
    }

    func normalizedEndpoint(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch self {
        case .volcengineCodingPlan:
            if trimmed.hasSuffix("/api/coding/v3") {
                return trimmed + "/chat/completions"
            }
        case .googleGemini:
            return trimmed
        case .openAICompatible:
            if trimmed.hasSuffix("/v1") || trimmed.hasSuffix("/api/v3") {
                return trimmed + "/chat/completions"
            }
        }

        return trimmed
    }
}
