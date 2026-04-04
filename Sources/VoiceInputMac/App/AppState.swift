import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    typealias PermissionsRequester = () async -> PermissionsCoordinator.Snapshot
    typealias AccessibilityTrustChecker = (Bool) -> Bool

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
    @Published var completionDetail = ""
    @Published var activeInputDeviceName = ""
    @Published var recentHistory: [RecentDictationHistoryEntry] = []
    @Published var speechHUDPhase: SpeechHUDPhase = .hidden
    @Published var audioLevel: Float = 0
    @Published var experimentOrderMode: ReRecognitionOrderMode = .blended
    @Published var experimentSampleLabel: ReRecognitionExperimentSampleLabel?
    @Published var experimentSessionTag = ""
    @Published var lastExperimentExportPath = ""

    /// Prevents re-entrant start/stop calls while an async transition is in progress.
    private var isTransitioning = false

    let isExperimentUIEnabled: Bool

    var hotKeyDescription: String {
        HotKeyCatalog.label(for: settingsStore.settings.hotKey)
    }

    private let settingsStore: SettingsStore
    private let dictationPipeline: DictationPipelineControlling
    private let recentHistoryStore: RecentDictationHistoryStoring
    private let textInjector = TextInjector()
    private var hotKeyController: HotKeyController?
    private var cancellables: Set<AnyCancellable> = []
    private var recoveryTarget: PermissionsCoordinator.SettingsTarget?
    private let requestPermissions: PermissionsRequester
    private let accessibilityTrustChecker: AccessibilityTrustChecker

    init(
        settingsStore: SettingsStore,
        dictationPipeline: DictationPipelineControlling = DictationPipeline(),
        recentHistoryStore: RecentDictationHistoryStoring = RecentDictationHistoryStore(),
        requestPermissions: @escaping PermissionsRequester = { await PermissionsCoordinator.requestAll() },
        accessibilityTrustChecker: @escaping AccessibilityTrustChecker = { AccessibilityCoordinator.isTrusted(prompt: $0) }
    ) {
        self.settingsStore = settingsStore
        self.dictationPipeline = dictationPipeline
        self.recentHistoryStore = recentHistoryStore
        self.requestPermissions = requestPermissions
        self.accessibilityTrustChecker = accessibilityTrustChecker
        self.isExperimentUIEnabled =
            ProcessInfo.processInfo.environment["VOICEINPUTMAC_ENABLE_EXPERIMENTS"] == "1" ||
            ProcessInfo.processInfo.arguments.contains("--enable-experiments")
        self.hotKeyController = HotKeyController(
            onPressed: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.handleHotKeyPressed()
                }
            },
            onReleased: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.handleHotKeyReleased()
                }
            }
        )
        self.recentHistory = recentHistoryStore.load()
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

    private func handleHotKeyPressed() async {
        switch settingsStore.settings.hotKeyMode {
        case .toggle:
            await toggleRecording()
        case .pushToTalk:
            if !isRecording {
                await startRecording()
            }
        }
    }

    private func handleHotKeyReleased() async {
        switch settingsStore.settings.hotKeyMode {
        case .toggle:
            break
        case .pushToTalk:
            if isRecording {
                await stopRecording()
            }
        }
    }

    func startRecording() async {
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        lastError = ""
        accessibilityWarning = ""
        recoveryActionTitle = ""
        completionDetail = ""
        activeInputDeviceName = ""
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

        let permissions = await requestPermissions()
        guard permissions.allAuthorized else {
            statusText = "权限不足"
            lastError = permissions.recoveryMessage
            recoveryTarget = permissions.recoveryTarget
            recoveryActionTitle = recoveryTarget == nil ? "" : "打开相关隐私设置"
            speechHUDPhase = .hidden
            return
        }

        if settingsStore.settings.autoPaste, !accessibilityTrustChecker(false) {
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
            }, onActiveInputDevice: { [weak self] device in
                Task { @MainActor in
                    self?.applyActiveInputDevice(device)
                }
            }, onAudioLevel: { [weak self] level in
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }, onFailure: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handlePipelineFailure(error, duringStart: false)
                }
            })
            isRecording = true
            speechHUDPhase = .recording
            updateRecordingStatusText()
        } catch {
            handlePipelineFailure(error, duringStart: true)
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false
        audioLevel = 0
        speechHUDPhase = .transcribing
        statusText = "正在收尾..."

        do {
            let result = try await dictationPipeline.stop(settings: settingsStore.settings, onStatus: { [weak self] text in
                Task { @MainActor in self?.statusText = text }
            }, onSegments: { [weak self] segments in
                Task { @MainActor in
                    self?.transcriptSegments = segments
                }
            })
            let text = result.text
            finalTranscript = text
            transcriptPreview = text
            switch result.onlineOptimizationStatus {
            case .disabled:
                statusText = "已完成"
                completionDetail = ""
            case .optimized:
                statusText = "已完成（已使用在线纠错）"
                completionDetail = "本次结果已使用在线纠错。"
            case let .fallback(reason):
                statusText = "已完成（已回退本地结果）"
                completionDetail = reason
            }
            speechHUDPhase = .hidden
            recordRecentHistoryEntry(text: text, onlineOptimizationStatus: result.onlineOptimizationStatus)
            clearActiveInputDevice()

            if settingsStore.settings.autoPaste {
                let trusted = accessibilityTrustChecker(false)
                if trusted {
                    accessibilityWarning = ""
                    textInjector.paste(
                        text,
                        preserveClipboard: settingsStore.settings.preserveClipboard,
                        switchInputMethod: settingsStore.settings.switchInputMethodBeforePaste
                    )
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
        completionDetail = ""
        clearActiveInputDevice()
        recoveryTarget = nil
        lastExperimentExportPath = ""
        statusText = "就绪"
        speechHUDPhase = .hidden
    }

    func clearRecentHistory() {
        recentHistory = recentHistoryStore.clear()
    }

    func copyRecentHistoryEntry(_ entry: RecentDictationHistoryEntry) {
        textInjector.copyToClipboard(entry.text)
        if !isRecording {
            statusText = "历史记录已复制"
        }
        completionDetail = "已复制一条历史记录。"
    }

    func restoreRecentHistoryEntry(_ entry: RecentDictationHistoryEntry) {
        transcriptPreview = entry.text
        finalTranscript = entry.text
        lastError = ""
        if !isRecording {
            statusText = "已载入历史记录"
        }
        if let inputDeviceName = entry.inputDeviceName {
            completionDetail = "已载入来自 \(inputDeviceName) 的历史记录。"
        } else {
            completionDetail = "已载入一条历史记录。"
        }
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
        clearActiveInputDevice()
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

    func applyActiveInputDevice(_ device: ActiveInputDeviceInfo) {
        activeInputDeviceName = device.name
        updateRecordingStatusText()
    }

    func clearActiveInputDevice() {
        activeInputDeviceName = ""
    }

    private func updateRecordingStatusText() {
        if isRecording, !activeInputDeviceName.isEmpty {
            statusText = "正在通过\(activeInputDeviceName)听写..."
        } else if isRecording {
            statusText = "正在听写..."
        }
    }

    private func handlePipelineFailure(_ error: Error, duringStart: Bool) {
        isRecording = false
        speechHUDPhase = .hidden
        clearActiveInputDevice()
        recoveryActionTitle = ""
        completionDetail = ""
        recoveryTarget = nil

        if let captureError = error as? AudioCaptureService.AudioCaptureError {
            switch captureError {
            case .selectedInputDeviceUnavailable:
                statusText = "所选麦克风不可用"
                lastError = "\(captureError.localizedDescription)\n可能原因：设备已断开或被移除。\n解决方法：重新连接设备，或在设置中改回「系统默认」。"
            case .selectedInputDevicePermissionDenied:
                statusText = "所选麦克风无权限"
                lastError = "\(captureError.localizedDescription)\n可能原因：系统未授权本应用使用麦克风。\n解决方法：前往 系统设置 > 隐私与安全性 > 麦克风，勾选本应用。"
                recoveryTarget = .microphone
                recoveryActionTitle = "打开麦克风设置"
            case .selectedInputDeviceStartFailed:
                statusText = "所选麦克风启动失败"
                lastError = "\(captureError.localizedDescription)\n可能原因：设备被其他应用独占，或连接不稳定。\n解决方法：检查设备连接，关闭占用麦克风的应用，然后重试。"
            default:
                statusText = duringStart ? "麦克风不可用" : "录音已中断"
                lastError = "\(captureError.localizedDescription)\n解决方法：检查麦克风连接，确认系统输入设备正常后重试。"
            }
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
                lastError = "\(backendError.localizedDescription)\n解决方法：在设置中切换到已安装的语言区域（如简体中文或 English）。"
            case .recognizerUnavailable:
                statusText = "语音识别不可用"
                lastError = "\(backendError.localizedDescription)\n可能原因：系统语音识别服务暂时不可用，或未授权。\n解决方法：检查语音识别权限，或稍后重试。"
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

    private func recordRecentHistoryEntry(
        text: String,
        onlineOptimizationStatus: DictationPipeline.OnlineOptimizationStatus
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let entry = RecentDictationHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            text: trimmedText,
            inputDeviceName: activeInputDeviceName.trimmedNilIfEmpty,
            optimizationStatus: mapHistoryOptimizationStatus(onlineOptimizationStatus)
        )
        recentHistory = recentHistoryStore.record(entry)
    }

    private func mapHistoryOptimizationStatus(
        _ status: DictationPipeline.OnlineOptimizationStatus
    ) -> RecentDictationHistoryEntry.OptimizationStatus {
        switch status {
        case .disabled:
            return .localOnly
        case .optimized:
            return .optimized
        case .fallback:
            return .fallbackToLocal
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
