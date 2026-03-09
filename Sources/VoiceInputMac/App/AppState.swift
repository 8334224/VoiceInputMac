import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    enum SpeechHUDPhase: Equatable {
        case hidden
        case recording
        case transcribing
    }

    @Published var isRecording = false
    @Published var statusText = "就绪"
    @Published var transcriptPreview = ""
    @Published var finalTranscript = ""
    @Published var transcriptSegments: [TranscriptSegment] = []
    @Published var lastError = ""
    @Published var accessibilityWarning = ""
    @Published var hotKeyWarning = ""
    @Published var speechHUDPhase: SpeechHUDPhase = .hidden
    @Published var experimentOrderMode: ReRecognitionOrderMode = .blended
    @Published var experimentSampleLabel: ReRecognitionExperimentSampleLabel?
    @Published var experimentSessionTag = ""
    @Published var lastExperimentExportPath = ""

    var hotKeyDescription: String {
        HotKeyCatalog.label(for: settingsStore.settings.hotKey)
    }

    private let settingsStore: SettingsStore
    private let dictationPipeline = DictationPipeline()
    private let textInjector = TextInjector()
    private var hotKeyController: HotKeyController?
    private var cancellables: Set<AnyCancellable> = []

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.hotKeyController = HotKeyController { [weak self] in
            Task { @MainActor [weak self] in
                await self?.toggleRecording()
            }
        }
        registerHotKey(settingsStore.settings.hotKey)

        settingsStore.$settings
            .map(\.hotKey)
            .removeDuplicates()
            .sink { [weak self] hotKey in
                self?.registerHotKey(hotKey)
            }
            .store(in: &cancellables)

        dictationPipeline.setReRecognitionOrderMode(experimentOrderMode)
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        lastError = ""
        accessibilityWarning = ""
        transcriptPreview = ""
        finalTranscript = ""
        transcriptSegments = []
        speechHUDPhase = .hidden
        lastExperimentExportPath = ""
        statusText = "请求麦克风与语音识别权限..."
        applyExperimentConfiguration()

        let granted = await PermissionsCoordinator.requestAll()
        guard granted else {
            statusText = "权限不足"
            lastError = "请在 系统设置 > 隐私与安全性 中允许麦克风和语音识别权限。"
            return
        }

        if settingsStore.settings.autoPaste, !AccessibilityCoordinator.isTrusted(prompt: false) {
            accessibilityWarning = "自动粘贴需要在 系统设置 > 隐私与安全性 > 辅助功能 中允许本应用。"
        }

        do {
            try await dictationPipeline.start(settings: settingsStore.settings, onStatus: { [weak self] text in
                Task { @MainActor in self?.statusText = text }
            }, onPreview: { [weak self] text in
                Task { @MainActor in
                    self?.transcriptPreview = text
                    self?.finalTranscript = text
                }
            }, onSegments: { [weak self] segments in
                Task { @MainActor in
                    self?.transcriptSegments = segments
                }
            })
            isRecording = true
            speechHUDPhase = .recording
            statusText = "正在听写..."
        } catch {
            speechHUDPhase = .hidden
            statusText = "启动失败"
            lastError = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false
        speechHUDPhase = .transcribing
        statusText = "正在收尾..."

        do {
            let text = try await dictationPipeline.stop(settings: settingsStore.settings, onStatus: { [weak self] text in
                Task { @MainActor in self?.statusText = text }
            }, onSegments: { [weak self] segments in
                Task { @MainActor in
                    self?.transcriptSegments = segments
                }
            })
            finalTranscript = text
            transcriptPreview = text
            statusText = "已完成"
            speechHUDPhase = .hidden

            if settingsStore.settings.autoPaste {
                let trusted = AccessibilityCoordinator.isTrusted(prompt: false)
                if trusted {
                    accessibilityWarning = ""
                    textInjector.paste(text, preserveClipboard: settingsStore.settings.preserveClipboard)
                } else {
                    accessibilityWarning = "辅助功能权限未生效，结果已保留在应用里。如果你刚刚勾选了权限，请完全退出并重新打开应用。"
                }
            }
        } catch {
            speechHUDPhase = .hidden
            statusText = "听写失败"
            lastError = error.localizedDescription
        }
    }

    func clearTranscript() {
        transcriptPreview = ""
        finalTranscript = ""
        transcriptSegments = []
        lastError = ""
        lastExperimentExportPath = ""
        statusText = "就绪"
        speechHUDPhase = .hidden
    }

    func openAccessibilitySettings() {
        AccessibilityCoordinator.openSettings()
    }

    func exportLatestExperimentJSON() async {
        lastError = ""
        applyExperimentConfiguration()

        do {
            let fileURL = try await dictationPipeline.saveLatestReRecognitionExperimentJSON(prettyPrinted: true)
            lastExperimentExportPath = fileURL.path
            statusText = "实验结果已导出"
        } catch {
            lastError = error.localizedDescription
            statusText = "导出失败"
        }
    }

    func experimentExportDirectoryPath() -> String {
        (try? dictationPipeline.reRecognitionExperimentExportDirectoryURL().path) ?? "-"
    }

    private func applyExperimentConfiguration() {
        dictationPipeline.setReRecognitionOrderMode(experimentOrderMode)
        dictationPipeline.setReRecognitionExperimentTag(
            sampleLabel: experimentSampleLabel,
            sessionTag: experimentSessionTag
        )
    }

    private func registerHotKey(_ descriptor: HotKeyDescriptor) {
        hotKeyWarning = hotKeyController?.update(descriptor: descriptor) ?? ""
    }
}
