import Foundation

struct AppSettings: Codable {
    var localeIdentifier: String
    var autoPaste: Bool
    var preserveClipboard: Bool
    var hotKey: HotKeyDescriptor
    var speechMode: SpeechMode
    var onlineOptimizationEnabled: Bool
    var onlineProvider: OnlineProvider
    var apiEndpoint: String
    var apiKey: String
    var modelName: String
    var enableBuiltInFujianPack: Bool
    var enableCustomCorrectionLexicon: Bool
    var customPhrasesText: String
    var replacementRulesText: String
    var extraPrompt: String
    var optimizerSystemPromptTemplate: String
    var optimizerUserPromptTemplate: String
    var requestTimeoutSeconds: Double

    init() {
        localeIdentifier = "zh-CN"
        autoPaste = true
        preserveClipboard = true
        hotKey = .default
        speechMode = .general
        onlineOptimizationEnabled = false
        onlineProvider = .volcengineCodingPlan
        apiEndpoint = onlineProvider.defaultEndpoint
        apiKey = ""
        modelName = onlineProvider.defaultModel
        enableBuiltInFujianPack = false
        enableCustomCorrectionLexicon = true
        customPhrasesText = ""
        replacementRulesText = ""
        extraPrompt = ""
        optimizerSystemPromptTemplate = BuiltInFujianPreset.systemPromptTemplate(for: .general)
        optimizerUserPromptTemplate = BuiltInFujianPreset.userPromptTemplate(for: .general)
        requestTimeoutSeconds = 8.0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        localeIdentifier = try container.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? defaults.localeIdentifier
        autoPaste = try container.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? defaults.autoPaste
        preserveClipboard = try container.decodeIfPresent(Bool.self, forKey: .preserveClipboard) ?? defaults.preserveClipboard
        hotKey = try container.decodeIfPresent(HotKeyDescriptor.self, forKey: .hotKey) ?? defaults.hotKey
        speechMode = try container.decodeIfPresent(SpeechMode.self, forKey: .speechMode) ?? defaults.speechMode
        onlineOptimizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .onlineOptimizationEnabled) ?? defaults.onlineOptimizationEnabled
        onlineProvider = try container.decodeIfPresent(OnlineProvider.self, forKey: .onlineProvider) ?? defaults.onlineProvider
        apiEndpoint = try container.decodeIfPresent(String.self, forKey: .apiEndpoint) ?? defaults.apiEndpoint
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? defaults.apiKey
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? defaults.modelName
        enableBuiltInFujianPack = try container.decodeIfPresent(Bool.self, forKey: .enableBuiltInFujianPack) ?? defaults.enableBuiltInFujianPack
        enableCustomCorrectionLexicon = try container.decodeIfPresent(Bool.self, forKey: .enableCustomCorrectionLexicon) ?? defaults.enableCustomCorrectionLexicon
        customPhrasesText = try container.decodeIfPresent(String.self, forKey: .customPhrasesText) ?? defaults.customPhrasesText
        replacementRulesText = try container.decodeIfPresent(String.self, forKey: .replacementRulesText) ?? defaults.replacementRulesText
        extraPrompt = try container.decodeIfPresent(String.self, forKey: .extraPrompt) ?? defaults.extraPrompt
        optimizerSystemPromptTemplate = try container.decodeIfPresent(String.self, forKey: .optimizerSystemPromptTemplate) ?? BuiltInFujianPreset.systemPromptTemplate(for: speechMode)
        optimizerUserPromptTemplate = try container.decodeIfPresent(String.self, forKey: .optimizerUserPromptTemplate) ?? BuiltInFujianPreset.userPromptTemplate(for: speechMode)
        requestTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .requestTimeoutSeconds) ?? defaults.requestTimeoutSeconds
    }
}
