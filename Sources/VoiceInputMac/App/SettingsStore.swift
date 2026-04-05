import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    struct MicrophoneSelectionStatus: Equatable {
        let title: String
        let detail: String
        let isError: Bool
    }

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
            // Only reset test results when online-relevant fields actually change,
            // and never while a test is in progress.
            if case .testing = onlineTestState {
                // Don't interrupt an active test.
            } else if onlineConfigChanged(old: oldValue, new: settings) {
                onlineTestState = .idle
            }
        }
    }

    private func onlineConfigChanged(old: AppSettings, new: AppSettings) -> Bool {
        old.apiKey != new.apiKey
            || old.apiEndpoint != new.apiEndpoint
            || old.modelName != new.modelName
            || old.onlineProvider != new.onlineProvider
    }
    @Published private(set) var onlineTestState: OnlineTestState = .idle
    @Published private(set) var microphoneDevices: [MicrophoneDeviceInfo] = []
    @Published private(set) var microphoneStatus: MicrophoneSelectionStatus = .init(
        title: "使用系统默认输入设备",
        detail: "开始听写时跟随当前系统默认麦克风。",
        isError: false
    )

    private let defaultsKey = "voice_input_mac_settings"
    private static let keychainAPIKeyKey = "api_key"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults: UserDefaults
    private let optimizer = OnlineOptimizer()
    private let microphoneDeviceProvider: MicrophoneDeviceProviding
    private let microphoneDeviceChangeMonitor: MicrophoneDeviceChangeObserving
    private let defaultInputDeviceChangeMonitor: DefaultInputDeviceChangeObserving

    init(
        userDefaults: UserDefaults = .standard,
        microphoneDeviceProvider: MicrophoneDeviceProviding = MicrophoneDeviceService(),
        microphoneDeviceChangeMonitor: MicrophoneDeviceChangeObserving = AVFoundationMicrophoneDeviceChangeMonitor(),
        defaultInputDeviceChangeMonitor: DefaultInputDeviceChangeObserving? = nil
    ) {
        self.userDefaults = userDefaults
        self.microphoneDeviceProvider = microphoneDeviceProvider
        self.microphoneDeviceChangeMonitor = microphoneDeviceChangeMonitor
        self.defaultInputDeviceChangeMonitor = defaultInputDeviceChangeMonitor ?? CoreAudioDefaultInputDeviceChangeMonitor(deviceProvider: microphoneDeviceProvider)

        // Load API Key from Keychain (or migrate from legacy UserDefaults) BEFORE
        // assigning to `settings`, because didSet triggers save() which would
        // overwrite the Keychain with an empty value.
        let restoredAPIKey = Self.loadAPIKey(
            from: userDefaults, defaultsKey: defaultsKey
        )

        if let data = userDefaults.data(forKey: defaultsKey),
           let stored = try? decoder.decode(AppSettings.self, from: data) {
            var normalized = stored
            normalized.onlineProvider = Self.inferredOnlineProvider(for: stored)
            if normalized.onlineProvider == .volcengineCodingPlan,
               normalized.requestTimeoutSeconds == 4 {
                normalized.requestTimeoutSeconds = 8
            }
            if normalized.onlineSoftTimeoutSeconds <= 0 {
                normalized.onlineSoftTimeoutSeconds = 8
            }
            if normalized.requestTimeoutSeconds < normalized.onlineSoftTimeoutSeconds {
                normalized.requestTimeoutSeconds = normalized.onlineSoftTimeoutSeconds
            }
            normalized = Self.migrateDefaultOnlineProvider(in: normalized)
            normalized = Self.migrateBundledPromptTemplates(in: normalized)
            normalized = Self.ensureDefaultPersonalRules(in: normalized)
            normalized = Self.normalizeMicrophoneSelection(in: normalized)
            normalized.apiKey = restoredAPIKey
            settings = normalized
        } else {
            var fresh = Self.normalizeMicrophoneSelection(in: Self.ensureDefaultPersonalRules(in: AppSettings()))
            fresh.apiKey = restoredAPIKey
            settings = fresh
        }

        reloadMicrophoneDevices()
        startObservingMicrophoneDeviceChanges()
        startObservingDefaultInputDeviceChanges()
        save()
    }

    deinit {
        microphoneDeviceChangeMonitor.stopObserving()
        defaultInputDeviceChangeMonitor.stopObserving()
    }

    func binding<Value>(for keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = $0 }
        )
    }

    func promptAssetBinding(for keyPath: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: {
                self.settings[keyPath: keyPath] = $0
                self.syncLegacyPromptTemplates()
            }
        )
    }

    func restoreBuiltInFujianPack() {
        settings.enableBuiltInFujianPack = true
    }

    func restorePromptTemplates() {
        settings.onlinePromptAssets = BuiltInFujianPreset.promptAssets(for: settings.speechMode)
    }

    func setSpeechMode(_ mode: SpeechMode) {
        let previousAssets = settings.onlinePromptAssets
        let oldDefaultAssets = BuiltInFujianPreset.promptAssets(for: settings.speechMode)

        settings.speechMode = mode

        if previousAssets == oldDefaultAssets {
            settings.onlinePromptAssets = BuiltInFujianPreset.promptAssets(for: mode)
        } else {
            syncLegacyPromptTemplates()
        }
    }

    func setOnlineProvider(_ provider: OnlineProvider) {
        settings.onlineProvider = provider
        settings.apiEndpoint = provider.defaultEndpoint
        settings.modelName = provider.defaultModel
        if settings.requestTimeoutSeconds < settings.onlineSoftTimeoutSeconds {
            settings.requestTimeoutSeconds = settings.onlineSoftTimeoutSeconds
        }
    }

    func applyOnlineProviderDefaults() {
        let provider = settings.onlineProvider
        settings.apiEndpoint = provider.defaultEndpoint
        settings.modelName = provider.defaultModel
        if provider == .volcengineCodingPlan || provider == .googleGemini, settings.requestTimeoutSeconds < 8 {
            settings.requestTimeoutSeconds = 8
        }
        if settings.onlineSoftTimeoutSeconds < 8 {
            settings.onlineSoftTimeoutSeconds = 8
        }
        if settings.requestTimeoutSeconds < settings.onlineSoftTimeoutSeconds {
            settings.requestTimeoutSeconds = settings.onlineSoftTimeoutSeconds
        }
    }

    func testOnlineOptimization() async {
        let snapshot = settings
        let correctionPipeline = TextCorrectionPipeline(settings: snapshot)
        let start = Date()

        onlineTestState = .testing

        do {
            let (response, quota) = try await optimizer.testConnection(settings: snapshot, correctionPipeline: correctionPipeline)
            let elapsed = Date().timeIntervalSince(start)
            var message = "连接成功，耗时 \(String(format: "%.1f", elapsed)) 秒，返回：\(response)"
            if let quotaSummary = quota?.summary {
                message += "（\(quotaSummary)）"
            }
            onlineTestState = .success(message)
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

    func reloadMicrophoneDevices() {
        reloadMicrophoneDevices(reason: "manual")
    }

    private func reloadMicrophoneDevices(reason: String) {
        print("[SettingsStore] reloading microphone devices reason=\(reason)")
        do {
            microphoneDevices = try microphoneDeviceProvider.availableInputDevices()
        } catch {
            microphoneDevices = []
            print("[SettingsStore] microphone device reload failed: \(error.localizedDescription)")
        }

        updateMicrophoneStatus()
    }

    func useSystemDefaultMicrophone() {
        settings.microphoneSelectionMode = .systemDefault
        updateMicrophoneStatus()
    }

    func selectMicrophoneDevice(id: String) {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            useSystemDefaultMicrophone()
            return
        }

        let matchedDevice = microphoneDevices.first { $0.id == trimmedID }
        settings.microphoneSelectionMode = .specificDevice
        settings.selectedMicrophoneID = trimmedID
        if let matchedDevice {
            settings.selectedMicrophoneName = matchedDevice.name
        }
        updateMicrophoneStatus()
    }

    func microphoneMenuLabel() -> String {
        switch settings.microphoneSelectionMode {
        case .systemDefault:
            if let device = microphoneDeviceProvider.systemDefaultInputDevice() {
                return "系统默认（\(device.name)）"
            }
            return "系统默认"
        case .specificDevice:
            return selectedMicrophoneDisplayName()
        }
    }

    func selectedMicrophoneDisplayName() -> String {
        if let matchedDevice = microphoneDevices.first(where: { $0.id == settings.selectedMicrophoneID }) {
            return matchedDevice.name
        }

        let fallback = settings.selectedMicrophoneName.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "未指定设备" : fallback
    }

    private func save() {
        guard let data = try? encoder.encode(settings) else { return }
        userDefaults.set(data, forKey: defaultsKey)
        // API Key is stored separately in the Keychain, never in UserDefaults.
        KeychainHelper.save(key: Self.keychainAPIKeyKey, value: settings.apiKey)
    }

    /// Load API Key from Keychain, with one-time migration from legacy UserDefaults.
    /// Called as a static method so it can run BEFORE the first `settings` assignment.
    private static func loadAPIKey(from userDefaults: UserDefaults, defaultsKey: String) -> String {
        // 1. Try reading from Keychain first.
        if let keychainValue = KeychainHelper.read(key: keychainAPIKeyKey),
           !keychainValue.isEmpty {
            return keychainValue
        }

        // 2. Migration: check if apiKey exists in the old UserDefaults JSON.
        if let data = userDefaults.data(forKey: defaultsKey),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let legacyKey = json["apiKey"] as? String,
           !legacyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            KeychainHelper.save(key: keychainAPIKeyKey, value: legacyKey)
            print("[SettingsStore] 已将 API Key 从 UserDefaults 迁移到 Keychain。")
            return legacyKey
        }

        return ""
    }

    private static func inferredOnlineProvider(for settings: AppSettings) -> OnlineProvider {
        let endpoint = settings.apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if endpoint.contains("volces.com/api/coding/v3") {
            return .volcengineCodingPlan
        }

        if endpoint.contains("generativelanguage.googleapis.com") {
            return .googleGemini
        }

        if endpoint.contains("models.inference.ai.azure.com") {
            return .githubModels
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

    private static func migrateDefaultOnlineProvider(in settings: AppSettings) -> AppSettings {
        var updated = settings

        let endpoint = updated.apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = updated.modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        let isLegacyDefaultVolcengine =
            updated.onlineProvider == .volcengineCodingPlan &&
            endpoint == OnlineProvider.volcengineCodingPlan.defaultEndpoint &&
            model == OnlineProvider.volcengineCodingPlan.defaultModel

        if isLegacyDefaultVolcengine {
            updated.onlineProvider = .googleGemini
            updated.apiEndpoint = OnlineProvider.googleGemini.defaultEndpoint
            updated.modelName = OnlineProvider.googleGemini.defaultModel
        }

        return updated
    }

    private static func migrateBundledPromptTemplates(in settings: AppSettings) -> AppSettings {
        var updated = settings

        if updated.speechMode == .general,
           isLegacyGeneralSystemPrompt(updated.optimizerSystemPromptTemplate) {
            updated.onlinePromptAssets = BuiltInFujianPreset.promptAssets(for: .general)
        }

        return updated
    }

    private func updateMicrophoneStatus() {
        switch settings.microphoneSelectionMode {
        case .systemDefault:
            if let device = microphoneDeviceProvider.systemDefaultInputDevice() {
                microphoneStatus = .init(
                    title: "使用系统默认输入设备",
                    detail: "当前默认设备：\(device.name)。开始听写时会自动跟随系统设置。",
                    isError: false
                )
            } else {
                microphoneStatus = .init(
                    title: "使用系统默认输入设备",
                    detail: "当前没有检测到可用麦克风，连接设备后可直接重试。",
                    isError: true
                )
            }
        case .specificDevice:
            let selectedID = settings.selectedMicrophoneID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selectedID.isEmpty else {
                microphoneStatus = .init(
                    title: "未指定具体设备",
                    detail: "当前配置为空，已回退为系统默认输入设备。",
                    isError: true
                )
                return
            }

            if let device = microphoneDevices.first(where: { $0.id == selectedID }) {
                microphoneStatus = .init(
                    title: "已指定麦克风",
                    detail: "当前选择：\(device.name)。修改后会在下次开始听写时生效。",
                    isError: false
                )
            } else {
                let name = selectedMicrophoneDisplayName()
                microphoneStatus = .init(
                    title: "所选麦克风不可用",
                    detail: "“\(name)” 当前不可用或已移除。你可以继续保留该选择，或改回系统默认。",
                    isError: true
                )
            }
        }
    }

    private func startObservingMicrophoneDeviceChanges() {
        microphoneDeviceChangeMonitor.startObserving { [weak self] event in
            self?.reloadMicrophoneDevices(reason: "hotplug:\(event.logDescription)")
        }
    }

    private func startObservingDefaultInputDeviceChanges() {
        defaultInputDeviceChangeMonitor.startObserving { [weak self] event in
            self?.reloadMicrophoneDevices(reason: "default-input:\(event.logDescription)")
        }
    }

    private static func normalizeMicrophoneSelection(in settings: AppSettings) -> AppSettings {
        var updated = settings
        let selectedID = updated.selectedMicrophoneID.trimmingCharacters(in: .whitespacesAndNewlines)

        if updated.microphoneSelectionMode == .specificDevice, selectedID.isEmpty {
            updated.microphoneSelectionMode = .systemDefault
            updated.selectedMicrophoneID = ""
            updated.selectedMicrophoneName = ""
        } else {
            updated.selectedMicrophoneID = selectedID
            updated.selectedMicrophoneName = updated.selectedMicrophoneName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return updated
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

    private func syncLegacyPromptTemplates() {
        settings.optimizerSystemPromptTemplate = settings.renderedOptimizerSystemPromptTemplate
        settings.optimizerUserPromptTemplate = settings.onlinePromptAssets.userPromptTemplate
    }
}
