import Foundation

enum HotKeyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case toggle
    case pushToTalk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggle: return "按一下切换"
        case .pushToTalk: return "按住说话"
        }
    }
}

struct AppSettings: Codable {
    var localeIdentifier: String
    var autoPaste: Bool
    var preserveClipboard: Bool
    var microphoneSelectionMode: MicrophoneSelectionMode
    var selectedMicrophoneID: String
    var selectedMicrophoneName: String
    var hotKey: HotKeyDescriptor
    var hotKeyMode: HotKeyMode
    var switchInputMethodBeforePaste: Bool
    var speechMode: SpeechMode
    var onlineOptimizationEnabled: Bool
    var onlineProvider: OnlineProvider
    var apiEndpoint: String
    /// API Key is stored in the macOS Keychain, NOT serialized to UserDefaults.
    /// This property is populated by `SettingsStore` after loading.
    var apiKey: String
    var modelName: String
    var enableBuiltInFujianPack: Bool
    var enableCustomCorrectionLexicon: Bool
    var customPhrasesText: String
    var replacementRulesText: String
    var extraPrompt: String
    var optimizerRolePromptAsset: String
    var optimizerStylePromptAsset: String
    var optimizerVocabularyPromptAsset: String
    var optimizerOutputPromptAsset: String
    var optimizerSystemPromptTemplate: String
    var optimizerUserPromptTemplate: String
    var onlineSoftTimeoutSeconds: Double
    var requestTimeoutSeconds: Double

    // Explicitly list CodingKeys to EXCLUDE apiKey from serialization.
    private enum CodingKeys: String, CodingKey {
        case localeIdentifier, autoPaste, preserveClipboard
        case microphoneSelectionMode, selectedMicrophoneID, selectedMicrophoneName
        case hotKey, hotKeyMode, switchInputMethodBeforePaste
        case speechMode, onlineOptimizationEnabled, onlineProvider
        case apiEndpoint, modelName
        case enableBuiltInFujianPack, enableCustomCorrectionLexicon
        case customPhrasesText, replacementRulesText, extraPrompt
        case optimizerRolePromptAsset, optimizerStylePromptAsset
        case optimizerVocabularyPromptAsset, optimizerOutputPromptAsset
        case optimizerSystemPromptTemplate, optimizerUserPromptTemplate
        case onlineSoftTimeoutSeconds, requestTimeoutSeconds
    }

    init() {
        let promptAssets = BuiltInFujianPreset.promptAssets(for: .general)
        localeIdentifier = "zh-CN"
        autoPaste = true
        preserveClipboard = true
        microphoneSelectionMode = .systemDefault
        selectedMicrophoneID = ""
        selectedMicrophoneName = ""
        hotKey = .default
        hotKeyMode = .toggle
        switchInputMethodBeforePaste = true
        speechMode = .general
        onlineOptimizationEnabled = false
        onlineProvider = .googleGemini
        apiEndpoint = onlineProvider.defaultEndpoint
        apiKey = ""
        modelName = onlineProvider.defaultModel
        enableBuiltInFujianPack = false
        enableCustomCorrectionLexicon = true
        customPhrasesText = ""
        replacementRulesText = ""
        extraPrompt = ""
        optimizerRolePromptAsset = promptAssets.rolePrompt
        optimizerStylePromptAsset = promptAssets.stylePrompt
        optimizerVocabularyPromptAsset = promptAssets.vocabularyPrompt
        optimizerOutputPromptAsset = promptAssets.outputPrompt
        optimizerSystemPromptTemplate = promptAssets.renderedSystemPromptTemplate
        optimizerUserPromptTemplate = promptAssets.userPromptTemplate
        onlineSoftTimeoutSeconds = 8.0
        requestTimeoutSeconds = 8.0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        localeIdentifier = try container.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? defaults.localeIdentifier
        autoPaste = try container.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? defaults.autoPaste
        preserveClipboard = try container.decodeIfPresent(Bool.self, forKey: .preserveClipboard) ?? defaults.preserveClipboard
        microphoneSelectionMode = try container.decodeIfPresent(MicrophoneSelectionMode.self, forKey: .microphoneSelectionMode) ?? defaults.microphoneSelectionMode
        selectedMicrophoneID = try container.decodeIfPresent(String.self, forKey: .selectedMicrophoneID) ?? defaults.selectedMicrophoneID
        selectedMicrophoneName = try container.decodeIfPresent(String.self, forKey: .selectedMicrophoneName) ?? defaults.selectedMicrophoneName
        hotKey = try container.decodeIfPresent(HotKeyDescriptor.self, forKey: .hotKey) ?? defaults.hotKey
        hotKeyMode = try container.decodeIfPresent(HotKeyMode.self, forKey: .hotKeyMode) ?? defaults.hotKeyMode
        switchInputMethodBeforePaste = try container.decodeIfPresent(Bool.self, forKey: .switchInputMethodBeforePaste) ?? defaults.switchInputMethodBeforePaste
        speechMode = try container.decodeIfPresent(SpeechMode.self, forKey: .speechMode) ?? defaults.speechMode
        onlineOptimizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .onlineOptimizationEnabled) ?? defaults.onlineOptimizationEnabled
        onlineProvider = try container.decodeIfPresent(OnlineProvider.self, forKey: .onlineProvider) ?? defaults.onlineProvider
        apiEndpoint = try container.decodeIfPresent(String.self, forKey: .apiEndpoint) ?? defaults.apiEndpoint
        // apiKey is NOT decoded from JSON — it is loaded from Keychain by SettingsStore.
        apiKey = ""
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? defaults.modelName
        enableBuiltInFujianPack = try container.decodeIfPresent(Bool.self, forKey: .enableBuiltInFujianPack) ?? defaults.enableBuiltInFujianPack
        enableCustomCorrectionLexicon = try container.decodeIfPresent(Bool.self, forKey: .enableCustomCorrectionLexicon) ?? defaults.enableCustomCorrectionLexicon
        customPhrasesText = try container.decodeIfPresent(String.self, forKey: .customPhrasesText) ?? defaults.customPhrasesText
        replacementRulesText = try container.decodeIfPresent(String.self, forKey: .replacementRulesText) ?? defaults.replacementRulesText
        extraPrompt = try container.decodeIfPresent(String.self, forKey: .extraPrompt) ?? defaults.extraPrompt
        let defaultPromptAssets = BuiltInFujianPreset.promptAssets(for: speechMode)
        let legacySystemPrompt = try container.decodeIfPresent(String.self, forKey: .optimizerSystemPromptTemplate)
        let decodedRolePrompt = try container.decodeIfPresent(String.self, forKey: .optimizerRolePromptAsset)
        let decodedStylePrompt = try container.decodeIfPresent(String.self, forKey: .optimizerStylePromptAsset)
        let decodedVocabularyPrompt = try container.decodeIfPresent(String.self, forKey: .optimizerVocabularyPromptAsset)
        let decodedOutputPrompt = try container.decodeIfPresent(String.self, forKey: .optimizerOutputPromptAsset)

        if let decodedRolePrompt, let decodedStylePrompt, let decodedVocabularyPrompt, let decodedOutputPrompt {
            optimizerRolePromptAsset = decodedRolePrompt
            optimizerStylePromptAsset = decodedStylePrompt
            optimizerVocabularyPromptAsset = decodedVocabularyPrompt
            optimizerOutputPromptAsset = decodedOutputPrompt
        } else if let legacySystemPrompt {
            let trimmedLegacySystemPrompt = legacySystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLegacySystemPrompt.isEmpty || Self.isLegacyGeneralSystemPrompt(trimmedLegacySystemPrompt) {
                optimizerRolePromptAsset = defaultPromptAssets.rolePrompt
                optimizerStylePromptAsset = defaultPromptAssets.stylePrompt
                optimizerVocabularyPromptAsset = defaultPromptAssets.vocabularyPrompt
                optimizerOutputPromptAsset = defaultPromptAssets.outputPrompt
            } else {
                let legacyAssets = OnlinePromptAssets.legacy(
                    systemPrompt: trimmedLegacySystemPrompt,
                    userPromptTemplate: try container.decodeIfPresent(String.self, forKey: .optimizerUserPromptTemplate) ?? defaultPromptAssets.userPromptTemplate
                )
                optimizerRolePromptAsset = legacyAssets.rolePrompt
                optimizerStylePromptAsset = legacyAssets.stylePrompt
                optimizerVocabularyPromptAsset = legacyAssets.vocabularyPrompt
                optimizerOutputPromptAsset = legacyAssets.outputPrompt
            }
        } else {
            optimizerRolePromptAsset = defaultPromptAssets.rolePrompt
            optimizerStylePromptAsset = defaultPromptAssets.stylePrompt
            optimizerVocabularyPromptAsset = defaultPromptAssets.vocabularyPrompt
            optimizerOutputPromptAsset = defaultPromptAssets.outputPrompt
        }

        optimizerUserPromptTemplate = try container.decodeIfPresent(String.self, forKey: .optimizerUserPromptTemplate) ?? defaultPromptAssets.userPromptTemplate
        optimizerSystemPromptTemplate = OnlinePromptAssets(
            rolePrompt: optimizerRolePromptAsset,
            stylePrompt: optimizerStylePromptAsset,
            vocabularyPrompt: optimizerVocabularyPromptAsset,
            outputPrompt: optimizerOutputPromptAsset,
            userPromptTemplate: optimizerUserPromptTemplate
        ).renderedSystemPromptTemplate
        onlineSoftTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .onlineSoftTimeoutSeconds) ?? defaults.onlineSoftTimeoutSeconds
        requestTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .requestTimeoutSeconds) ?? defaults.requestTimeoutSeconds
    }

    var microphoneSelection: MicrophoneSelectionConfiguration {
        MicrophoneSelectionConfiguration(
            mode: microphoneSelectionMode,
            selectedMicrophoneID: selectedMicrophoneID,
            selectedMicrophoneName: selectedMicrophoneName
        )
    }

    var onlinePromptAssets: OnlinePromptAssets {
        get {
            OnlinePromptAssets(
                rolePrompt: optimizerRolePromptAsset,
                stylePrompt: optimizerStylePromptAsset,
                vocabularyPrompt: optimizerVocabularyPromptAsset,
                outputPrompt: optimizerOutputPromptAsset,
                userPromptTemplate: optimizerUserPromptTemplate
            )
        }
        set {
            optimizerRolePromptAsset = newValue.rolePrompt
            optimizerStylePromptAsset = newValue.stylePrompt
            optimizerVocabularyPromptAsset = newValue.vocabularyPrompt
            optimizerOutputPromptAsset = newValue.outputPrompt
            optimizerUserPromptTemplate = newValue.userPromptTemplate
            optimizerSystemPromptTemplate = newValue.renderedSystemPromptTemplate
        }
    }

    var renderedOptimizerSystemPromptTemplate: String {
        onlinePromptAssets.renderedSystemPromptTemplate
    }

    private static func isLegacyGeneralSystemPrompt(_ template: String) -> Bool {
        let normalized = template.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty { return false }
        if normalized.contains("Role: 你是 Typeless app 的极简核心") { return false }

        let legacyPrefixes = [
            "你是中文语音转写纠错器。",
            "任务是把语音识别结果修正成最终可直接发送或输入的文本。"
        ]

        return legacyPrefixes.contains { normalized.hasPrefix($0) }
    }
}
