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
    @Published var recoveryActionTitle = ""
    @Published var speechHUDPhase: SpeechHUDPhase = .hidden
    @Published var experimentOrderMode: ReRecognitionOrderMode = .blended
    @Published var experimentSampleLabel: ReRecognitionExperimentSampleLabel?
    @Published var experimentSessionTag = ""
    @Published var lastExperimentExportPath = ""

    let isExperimentUIEnabled: Bool

    var hotKeyDescription: String {
        HotKeyCatalog.label(for: settingsStore.settings.hotKey)
    }

    private let settingsStore: SettingsStore
    private let dictationPipeline = DictationPipeline()
    private let textInjector = TextInjector()
    private var hotKeyController: HotKeyController?
    private var cancellables: Set<AnyCancellable> = []
    private var recoveryTarget: PermissionsCoordinator.SettingsTarget?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.isExperimentUIEnabled =
            ProcessInfo.processInfo.environment["VOICEINPUTMAC_ENABLE_EXPERIMENTS"] == "1" ||
            ProcessInfo.processInfo.arguments.contains("--enable-experiments")
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
        recoveryActionTitle = ""
        recoveryTarget = nil
        transcriptPreview = ""
        finalTranscript = ""
        transcriptSegments = []
        speechHUDPhase = .hidden
        lastExperimentExportPath = ""
        statusText = "请求麦克风与语音识别权限..."
        if isExperimentUIEnabled {
            applyExperimentConfiguration()
        } else {
            dictationPipeline.setExperimentPathEnabled(false)
        }

        let permissions = await PermissionsCoordinator.requestAll()
        guard permissions.allAuthorized else {
            statusText = "权限不足"
            lastError = permissions.recoveryMessage
            recoveryTarget = permissions.recoveryTarget
            recoveryActionTitle = recoveryTarget == nil ? "" : "打开相关隐私设置"
            speechHUDPhase = .hidden
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
            handlePipelineFailure(error, duringStart: true)
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
            dictationPipeline.cancelCurrentSession()
            handlePipelineFailure(error, duringStart: false)
        }
    }

    func clearTranscript() {
        transcriptPreview = ""
        finalTranscript = ""
        transcriptSegments = []
        lastError = ""
        recoveryActionTitle = ""
        recoveryTarget = nil
        lastExperimentExportPath = ""
        statusText = "就绪"
        speechHUDPhase = .hidden
    }

    func openAccessibilitySettings() {
        AccessibilityCoordinator.openSettings()
    }

    func performRecoveryAction() {
        guard let recoveryTarget else { return }
        PermissionsCoordinator.openSettings(for: recoveryTarget)
    }

    func terminateApplication() {
        dictationPipeline.cancelCurrentSession()
        isRecording = false
        speechHUDPhase = .hidden
        NSApplication.shared.terminate(nil)
    }

    func exportLatestExperimentJSON() async {
        guard isExperimentUIEnabled else { return }
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
        dictationPipeline.setExperimentPathEnabled(true)
        dictationPipeline.setReRecognitionOrderMode(experimentOrderMode)
        dictationPipeline.setReRecognitionExperimentTag(
            sampleLabel: experimentSampleLabel,
            sessionTag: experimentSessionTag
        )
    }

    private func registerHotKey(_ descriptor: HotKeyDescriptor) {
        hotKeyWarning = hotKeyController?.update(descriptor: descriptor) ?? ""
    }

    private func handlePipelineFailure(_ error: Error, duringStart: Bool) {
        isRecording = false
        speechHUDPhase = .hidden
        recoveryActionTitle = ""
        recoveryTarget = nil

        if let captureError = error as? AudioCaptureService.AudioCaptureError {
            statusText = duringStart ? "麦克风不可用" : "录音已中断"
            lastError = "\(captureError.localizedDescription) 修复后可直接再次开始听写。"
            if captureError == .noInputDevice || captureError == .cannotStartEngine {
                recoveryTarget = .microphone
                recoveryActionTitle = "打开麦克风设置"
            }
            return
        }

        if let backendError = error as? AppleSpeechRecognitionBackend.BackendError {
            switch backendError {
            case .unsupportedLocale:
                statusText = "语言不可用"
                lastError = backendError.localizedDescription
            case .recognizerUnavailable:
                statusText = "语音识别不可用"
                lastError = "\(backendError.localizedDescription) 请稍后重试，或检查系统语音识别权限。"
                recoveryTarget = .speechRecognition
                recoveryActionTitle = "打开语音识别设置"
            case .notRunning:
                statusText = "已停止"
                lastError = "当前听写会话已经结束，你可以直接再次开始听写。"
            }
            return
        }

        statusText = duringStart ? "启动失败" : "听写失败"
        lastError = "\(error.localizedDescription) 你可以直接再次开始听写。"
    }
}
