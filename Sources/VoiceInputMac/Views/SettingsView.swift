import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    private struct LocaleOption: Identifiable {
        let id: String
        let title: String
    }

    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var showsOnlinePanel = false
    @State private var showsCorrectionEditors = false
    @State private var showsPromptTemplates = false
    @State private var isRecordingHotKey = false
    @State private var hotKeyMonitor: Any?

    private let pageGradient = LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.95, blue: 0.92),
            Color(red: 0.93, green: 0.95, blue: 0.98),
            Color(red: 0.98, green: 0.94, blue: 0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private let textPrimary = Color(red: 0.14, green: 0.16, blue: 0.20)
    private let textSecondary = Color(red: 0.41, green: 0.45, blue: 0.52)
    private let fieldFill = Color.white.opacity(0.97)
    private let fieldStroke = Color(red: 0.84, green: 0.86, blue: 0.90)
    private let panelFill = Color.white.opacity(0.88)
    private let maxContentWidth: CGFloat = 860
    private let topCardHeight: CGFloat = 212
    private let topCardSpacing: CGFloat = 16
    private let isDebugSettingsEnabled =
        ProcessInfo.processInfo.environment["VOICEINPUTMAC_ENABLE_EXPERIMENTS"] == "1" ||
        ProcessInfo.processInfo.arguments.contains("--enable-experiments")
    private let localeOptions: [LocaleOption] = [
        .init(id: "zh-CN", title: "简体中文"),
        .init(id: "zh-HK", title: "中文（香港）"),
        .init(id: "zh-TW", title: "繁体中文"),
        .init(id: "en-US", title: "English (US)")
    ]

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = 24
            let trackWidth = min(maxContentWidth, geometry.size.width - horizontalInset * 2)

            ZStack {
                pageGradient.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        topBar
                        topGrid(trackWidth: trackWidth)
                        onlinePanel
                        correctionPanel
                        if isDebugSettingsEnabled {
                            promptPanel
                        }
                    }
                    .frame(width: trackWidth, alignment: .leading)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, horizontalInset)
                }
            }
        }
        .frame(width: 900, height: 660)
        .preferredColorScheme(.light)
        .onDisappear {
            stopHotKeyCapture()
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MOMO语音输入法")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("把常用项放前面：语言、热键、在线优化、热词词库。调试级配置默认隐藏。")
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            HStack(spacing: 8) {
                pill(settingsStore.settings.speechMode.title, tint: Color(red: 0.79, green: 0.30, blue: 0.22))
                pill(settingsStore.settings.onlineProvider.title, tint: Color(red: 0.13, green: 0.46, blue: 0.77))
            }
        }
    }

    private func topGrid(trackWidth: CGFloat) -> some View {
        let basicRatio: CGFloat = 1.42
        let hotKeyRatio: CGFloat = 1.00
        let accentRatio: CGFloat = 0.82
        let unitWidth = (trackWidth - topCardSpacing * 2) / (basicRatio + hotKeyRatio + accentRatio)

        return HStack(alignment: .top, spacing: topCardSpacing) {
            basicPanel
                .frame(width: unitWidth * basicRatio, height: topCardHeight, alignment: .top)
            hotKeyPanel
                .frame(width: unitWidth * hotKeyRatio, height: topCardHeight, alignment: .top)
            accentPanel
                .frame(width: unitWidth * accentRatio, height: topCardHeight, alignment: .top)
        }
        .frame(width: trackWidth, height: topCardHeight, alignment: .leading)
    }

    private var basicPanel: some View {
        panel(icon: "slider.horizontal.3", title: "基础", subtitle: "高频配置") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    fieldBlock("语言区域") {
                        Menu {
                            ForEach(localeOptions) { option in
                                Button(option.title) {
                                    settingsStore.settings.localeIdentifier = option.id
                                }
                            }
                        } label: {
                            HStack {
                                Text(localeTitle(for: settingsStore.settings.localeIdentifier))
                                    .foregroundStyle(textPrimary)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(textSecondary)
                            }
                        }
                    }
                    .frame(width: 168)

                    fieldBlock("识别模式") {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("识别模式", selection: Binding(
                                get: { settingsStore.settings.speechMode },
                                set: { settingsStore.setSpeechMode($0) }
                            )) {
                                ForEach(SpeechMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .controlSize(.small)

                            Text(settingsStore.settings.speechMode.description)
                                .font(.caption)
                                .foregroundStyle(textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(width: 150, alignment: .leading)
                }

                HStack(spacing: 12) {
                    compactSwitch("自动粘贴", isOn: settingsStore.binding(for: \.autoPaste))
                        .frame(width: 168, alignment: .leading)
                    compactSwitch("恢复剪贴板", isOn: settingsStore.binding(for: \.preserveClipboard))
                        .frame(width: 150, alignment: .leading)
                }
            }
        }
    }

    private var hotKeyPanel: some View {
        panel(icon: "command.square", title: "快捷键", subtitle: "") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    fieldShell {
                        Text(HotKeyCatalog.label(for: settingsStore.settings.hotKey))
                            .font(.body.weight(.medium))
                            .foregroundStyle(textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 8) {
                    Button(isRecordingHotKey ? "按键中..." : "录入快捷键") {
                        toggleHotKeyCapture()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .fixedSize()

                    Button("默认") {
                        stopHotKeyCapture()
                        settingsStore.setHotKey(.default)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()

                    Spacer(minLength: 0)
                }

                Text(isRecordingHotKey ? "现在直接按你想绑定的组合键；按 Esc 取消。" : "支持直接录入任意组合键。Fn 单键在 macOS 上仍然不稳定。")
                    .font(.caption)
                    .foregroundStyle(textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var accentPanel: some View {
        panel(icon: "waveform.path.ecg", title: "福建口音", subtitle: "默认关闭，口音明显时再开") {
            VStack(alignment: .leading, spacing: 12) {
                compactSwitch("启用内置纠错包", isOn: settingsStore.binding(for: \.enableBuiltInFujianPack))

                Text("自动加入福建地名、常见误识别和模式相关词汇。")
                    .font(.caption)
                    .foregroundStyle(textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var onlinePanel: some View {
        panel(
            icon: "bolt.horizontal.circle",
            title: "在线优化",
            subtitle: "默认关闭，需要时再开",
            accessory: {
                compactSwitch("启用在线纠错", isOn: settingsStore.binding(for: \.onlineOptimizationEnabled))
            }
        ) {
            DisclosureGroup(isExpanded: $showsOnlinePanel) {
                VStack(alignment: .leading, spacing: 12) {
                    if isDebugSettingsEnabled {
                        HStack(spacing: 12) {
                            Picker("提供方", selection: Binding(
                                get: { settingsStore.settings.onlineProvider },
                                set: { settingsStore.setOnlineProvider($0) }
                            )) {
                                ForEach(OnlineProvider.allCases) { provider in
                                    Text(provider.title).tag(provider)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .frame(width: 320)
                            Spacer(minLength: 0)
                            Button {
                                Task { await settingsStore.testOnlineOptimization() }
                            } label: {
                                Text(testButtonTitle)
                                    .frame(minWidth: 96)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(isTestingOnlineOptimization)
                        }

                        Text(settingsStore.settings.onlineProvider.description)
                            .font(.caption)
                            .foregroundStyle(textSecondary)

                        HStack(alignment: .top, spacing: 12) {
                            fieldBlock("接口地址") {
                                HStack(spacing: 8) {
                                    fieldShell {
                                        TextField("接口地址", text: settingsStore.binding(for: \.apiEndpoint))
                                            .textFieldStyle(.plain)
                                            .foregroundStyle(textPrimary)
                                    }
                                    Button("预设") {
                                        settingsStore.applyOnlineProviderDefaults()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            fieldBlock("模型") {
                                fieldShell {
                                    TextField("模型名", text: settingsStore.binding(for: \.modelName))
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(textPrimary)
                                }
                            }
                            .frame(width: 180)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            fieldBlock("API Key") {
                                fieldShell {
                                    SecureField("API Key", text: settingsStore.binding(for: \.apiKey))
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(textPrimary)
                                }
                            }

                            fieldBlock("超时") {
                                fieldShell {
                                    TextField("8", value: settingsStore.binding(for: \.requestTimeoutSeconds), format: .number)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(textPrimary)
                                }
                            }
                            .frame(width: 88)
                        }

                        fieldBlock("补充要求") {
                            fieldShell {
                                TextField("可留空", text: settingsStore.binding(for: \.extraPrompt), axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(textPrimary)
                                    .lineLimit(1 ... 2)
                            }
                        }
                    } else {
                        Text("开启后会在首轮结果基础上做一次在线纠错。普通 Beta 使用只需要填 API Key；接口和模型保持默认即可。")
                            .font(.caption)
                            .foregroundStyle(textSecondary)

                        fieldBlock("API Key") {
                            HStack(spacing: 12) {
                                fieldShell {
                                    SecureField("API Key", text: settingsStore.binding(for: \.apiKey))
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(textPrimary)
                                }

                                Button {
                                    Task { await settingsStore.testOnlineOptimization() }
                                } label: {
                                    Text(testButtonTitle)
                                        .frame(minWidth: 96)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isTestingOnlineOptimization)
                            }
                        }
                    }

                    if let message = settingsStore.onlineTestState.message {
                        HStack(spacing: 8) {
                            Image(systemName: settingsStore.onlineTestState.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(settingsStore.onlineTestState.isError ? Color.red : Color.green)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(settingsStore.onlineTestState.isError ? Color.red : textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text(isDebugSettingsEnabled ? "展开在线优化配置" : "展开在线优化设置")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Spacer()
                    Text(settingsStore.settings.onlineOptimizationEnabled ? "已开启" : "已关闭")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }
            }
            .tint(textPrimary)
        }
    }

    private var correctionPanel: some View {
        panel(
            icon: "text.quote",
            title: "热词与词库",
            subtitle: "个人短语、术语和替换规则",
            accessory: {
                HStack(spacing: 8) {
                    Button("填入样例") {
                        settingsStore.appendBuiltInSamplesToEditors()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    compactSwitch("启用词库", isOn: settingsStore.binding(for: \.enableCustomCorrectionLexicon))
                }
            }
        ) {
            DisclosureGroup(isExpanded: $showsCorrectionEditors) {
                HStack(alignment: .top, spacing: 12) {
                    editorColumn(
                        title: "补充短语，每行一个",
                        text: settingsStore.binding(for: \.customPhrasesText),
                        minHeight: 130
                    )
                    editorColumn(
                        title: "替换规则，格式：错词 => 正词",
                        text: settingsStore.binding(for: \.replacementRulesText),
                        minHeight: 130
                    )
                }
                .padding(.top, 8)

                Text("技术模式推荐：open cloud => OpenClaw、步数 => 部署、sky => skill")
                    .font(.caption)
                    .foregroundStyle(textSecondary)
                    .padding(.top, 6)
            } label: {
                HStack {
                    Text("展开编辑热词与词库")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Spacer()
                    Text("热词 + 替换规则")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }
            }
            .tint(textPrimary)
        }
    }

    private var promptPanel: some View {
        panel(icon: "sparkles.rectangle.stack", title: "高级提示词", subtitle: "默认折叠，深调时再开") {
            DisclosureGroup(isExpanded: $showsPromptTemplates) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Button("恢复默认提示词") {
                            settingsStore.restorePromptTemplates()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        Spacer(minLength: 0)
                    }

                    editorColumn(
                        title: "系统模板，可用变量：{{EXTRA_PROMPT}} {{PRIORITY_PHRASES}} {{RULE_HINTS}} {{TEXT}}",
                        text: settingsStore.binding(for: \.optimizerSystemPromptTemplate),
                        minHeight: 120
                    )
                    editorColumn(
                        title: "用户模板，可用变量：{{EXTRA_PROMPT}} {{PRIORITY_PHRASES}} {{RULE_HINTS}} {{TEXT}}",
                        text: settingsStore.binding(for: \.optimizerUserPromptTemplate),
                        minHeight: 140
                    )
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text("展开高级模板")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Spacer()
                    Text("通常不需要常改")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }
            }
            .tint(textPrimary)
        }
    }

    private func panel<Accessory: View, Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.85))
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.16, green: 0.47, blue: 0.83))
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(textPrimary)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(textSecondary)
                        }
                    }
                }
                Spacer(minLength: 8)
                accessory()
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 8)
        )
    }

    private func fieldBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fieldFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(fieldStroke, lineWidth: 1)
                )
        )
    }

    private func panel<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        panel(icon: icon, title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }

    private func editorColumn(title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(textSecondary)
            TextEditor(text: text)
                .font(.body.monospaced())
                .foregroundStyle(textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(fieldStroke, lineWidth: 1)
                        )
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactSwitch(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(BrandedSwitchToggleStyle())
            .foregroundStyle(textPrimary)
            .fixedSize()
            .controlSize(.small)
    }

    private func pill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }

    private var isTestingOnlineOptimization: Bool {
        if case .testing = settingsStore.onlineTestState { return true }
        return false
    }

    private var testButtonTitle: String {
        isTestingOnlineOptimization ? "测试中..." : "测试在线配置"
    }

    private func localeTitle(for identifier: String) -> String {
        localeOptions.first(where: { $0.id == identifier })?.title ?? "简体中文"
    }

    private func toggleHotKeyCapture() {
        if isRecordingHotKey {
            stopHotKeyCapture()
        } else {
            startHotKeyCapture()
        }
    }

    private func startHotKeyCapture() {
        stopHotKeyCapture()
        isRecordingHotKey = true

        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingHotKey else { return event }

            let keyCode = UInt32(event.keyCode)
            if keyCode == UInt32(kVK_Escape) {
                stopHotKeyCapture()
                return nil
            }

            if HotKeyCatalog.isModifierKey(keyCode) {
                return nil
            }

            let modifiers = hotKeyModifiers(from: event.modifierFlags)
            settingsStore.setHotKey(.init(keyCode: keyCode, modifiers: modifiers))
            stopHotKeyCapture()
            return nil
        }
    }

    private func stopHotKeyCapture() {
        isRecordingHotKey = false
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
            self.hotKeyMonitor = nil
        }
    }

    private func hotKeyModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        let deviceIndependent = flags.intersection(.deviceIndependentFlagsMask)

        if deviceIndependent.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if deviceIndependent.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if deviceIndependent.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if deviceIndependent.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        return modifiers
    }
}

private struct BrandedSwitchToggleStyle: ToggleStyle {
    private let onTrack = Color(red: 0.16, green: 0.50, blue: 0.94)
    private let offTrack = Color(red: 0.88, green: 0.54, blue: 0.38)
    private let thumb = Color.white
    private let onLabel = Color(red: 0.12, green: 0.17, blue: 0.25)
    private let offLabel = Color(red: 0.40, green: 0.27, blue: 0.20)

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                configuration.label
                    .foregroundStyle(configuration.isOn ? onLabel : offLabel)

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? onTrack : offTrack)
                        .frame(width: 44, height: 26)

                    Circle()
                        .fill(thumb)
                        .frame(width: 22, height: 22)
                        .padding(2)
                        .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
