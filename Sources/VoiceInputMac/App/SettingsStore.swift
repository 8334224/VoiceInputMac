import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    enum OnlineTestState {
        case idle
        case testing
        case success(String)
        case failure(String)

        var message: String? {
            switch self {
            case .idle, .testing:
                return nil
            case let .success(message), let .failure(message):
                return message
            }
        }

        var isError: Bool {
            if case .failure = self { return true }
            return false
        }
    }

    @Published var settings: AppSettings {
        didSet {
            save()
            if case .testing = onlineTestState {
            } else {
                onlineTestState = .idle
            }
        }
    }
    @Published private(set) var onlineTestState: OnlineTestState = .idle

    private let defaultsKey = "voice_input_mac_settings"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults
    private let optimizer = OnlineOptimizer()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if let data = userDefaults.data(forKey: defaultsKey),
           let stored = try? decoder.decode(AppSettings.self, from: data) {
            var normalized = stored
            normalized.onlineProvider = Self.inferredOnlineProvider(for: stored)
            if normalized.onlineProvider == .volcengineCodingPlan,
               normalized.requestTimeoutSeconds == 4 {
                normalized.requestTimeoutSeconds = 8
            }
            normalized = Self.ensureDefaultPersonalRules(in: normalized)
            settings = normalized
        } else {
            settings = Self.ensureDefaultPersonalRules(in: AppSettings())
        }

        save()
    }

    func binding<Value>(for keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = $0 }
        )
    }

    func restoreBuiltInFujianPack() {
        settings.enableBuiltInFujianPack = true
    }

    func restorePromptTemplates() {
        settings.optimizerSystemPromptTemplate = BuiltInFujianPreset.systemPromptTemplate(for: settings.speechMode)
        settings.optimizerUserPromptTemplate = BuiltInFujianPreset.userPromptTemplate(for: settings.speechMode)
    }

    func setSpeechMode(_ mode: SpeechMode) {
        let previousSystemPrompt = settings.optimizerSystemPromptTemplate
        let previousUserPrompt = settings.optimizerUserPromptTemplate
        let oldDefaultSystem = BuiltInFujianPreset.systemPromptTemplate(for: settings.speechMode)
        let oldDefaultUser = BuiltInFujianPreset.userPromptTemplate(for: settings.speechMode)

        settings.speechMode = mode

        if previousSystemPrompt == oldDefaultSystem {
            settings.optimizerSystemPromptTemplate = BuiltInFujianPreset.systemPromptTemplate(for: mode)
        }
        if previousUserPrompt == oldDefaultUser {
            settings.optimizerUserPromptTemplate = BuiltInFujianPreset.userPromptTemplate(for: mode)
        }
    }

    func setOnlineProvider(_ provider: OnlineProvider) {
        settings.onlineProvider = provider
        settings.apiEndpoint = provider.defaultEndpoint
        settings.modelName = provider.defaultModel
    }

    func applyOnlineProviderDefaults() {
        let provider = settings.onlineProvider
        settings.apiEndpoint = provider.defaultEndpoint
        settings.modelName = provider.defaultModel
        if provider == .volcengineCodingPlan, settings.requestTimeoutSeconds < 8 {
            settings.requestTimeoutSeconds = 8
        }
    }

    func testOnlineOptimization() async {
        let snapshot = settings
        let correctionPipeline = TextCorrectionPipeline(settings: snapshot)
        let start = Date()

        onlineTestState = .testing

        do {
            let response = try await optimizer.testConnection(settings: snapshot, correctionPipeline: correctionPipeline)
            let elapsed = Date().timeIntervalSince(start)
            onlineTestState = .success("连接成功，耗时 \(String(format: "%.1f", elapsed)) 秒，返回：\(response)")
        } catch {
            onlineTestState = .failure(error.localizedDescription)
        }
    }

    func appendBuiltInSamplesToEditors() {
        let phraseBlock = BuiltInFujianPreset.phrases(for: settings.speechMode).joined(separator: "\n")
        let ruleBlock = BuiltInFujianPreset.replacementRules(for: settings.speechMode)
            .map { "\($0.source) => \($0.target)" }
            .joined(separator: "\n")

        if settings.customPhrasesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.customPhrasesText = phraseBlock
        }
        if settings.replacementRulesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.replacementRulesText = ruleBlock
        }
    }

    func setHotKeyKeyCode(_ keyCode: UInt32) {
        settings.hotKey.keyCode = keyCode
    }

    func setHotKey(_ descriptor: HotKeyDescriptor) {
        settings.hotKey = descriptor
    }

    func setHotKeyModifier(_ modifier: UInt32, enabled: Bool) {
        if enabled {
            settings.hotKey.modifiers |= modifier
        } else {
            settings.hotKey.modifiers &= ~modifier
        }
    }

    private func save() {
        guard let data = try? encoder.encode(settings) else { return }
        userDefaults.set(data, forKey: defaultsKey)
    }

    private static func inferredOnlineProvider(for settings: AppSettings) -> OnlineProvider {
        let endpoint = settings.apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if endpoint.contains("volces.com/api/coding/v3") {
            return .volcengineCodingPlan
        }

        if endpoint.contains("api.openai.com")
            || endpoint.contains("openai-compatible")
            || endpoint.contains("/v1/chat/completions")
            || endpoint.contains("/api/v3/chat/completions") {
            return .openAICompatible
        }

        return settings.onlineProvider
    }

    private static func ensureDefaultPersonalRules(in settings: AppSettings) -> AppSettings {
        var updated = settings
        let lines = updated.replacementRulesText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { $0 != "的话 =>" && $0 != "的话 => " }

        updated.replacementRulesText = lines.joined(separator: "\n")
        return updated
    }
}
