import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    private struct LocaleOption: Identifiable {
        let id: String
        let title: String
    }

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appState: AppState
    @State private var showsOnlinePanel = true
    @State private var showsCorrectionEditors = false
    @State private var showsPromptTemplates = false
    @State private var showsHistoryPanel = true
    @State private var isRecordingHotKey = false
    @State private var hotKeyMonitor: Any?

    @Environment(\.colorScheme) private var colorScheme

    private var pageGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.12, blue: 0.14),
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.14, green: 0.11, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.95, blue: 0.92),
                Color(red: 0.93, green: 0.95, blue: 0.98),
                Color(red: 0.98, green: 0.94, blue: 0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var textPrimary: Color { colorScheme == .dark ? Color(red: 0.90, green: 0.90, blue: 0.92) : Color(red: 0.14, green: 0.16, blue: 0.20) }
    private var textSecondary: Color { colorScheme == .dark ? Color(red: 0.58, green: 0.60, blue: 0.64) : Color(red: 0.41, green: 0.45, blue: 0.52) }
    private var fieldFill: Color { colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.97) }
    private var fieldStroke: Color { colorScheme == .dark ? Color.white.opacity(0.15) : Color(red: 0.84, green: 0.86, blue: 0.90) }
    private var panelFill: Color { colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.88) }
    private let maxContentWidth: CGFloat = 860
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
                    VStack(alignment: .leading, spacing: 10) {
                        topBar
                        topRow(trackWidth: trackWidth)
                        behaviorStrip
                        onlinePanel
                        correctionPanel
                        historyPanel
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
        .frame(minWidth: 780, idealWidth: 900, maxWidth: 1040, minHeight: 580, idealHeight: 660, maxHeight: 820)
        .task {
            settingsStore.reloadMicrophoneDevices()
        }
        .onDisappear {
            stopHotKeyCapture()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MOMO语音输入法")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                Text("语音输入设置与偏好")
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            HStack(spacing: 8) {
                pill(settingsStore.settings.speechMode.title, tint: Color(red: 0.79, green: 0.30, blue: 0.22))
                if settingsStore.settings.onlineOptimizationEnabled {
                    pill(settingsStore.settings.onlineProvider.title, tint: Color(red: 0.13, green: 0.46, blue: 0.77))
                }
            }
        }
    }

    // MARK: - Top Row (2 cards: Basics + HotKey — equal height)

    private func topRow(trackWidth: CGFloat) -> some View {
        let leftWidth = (trackWidth - topCardSpacing) * 0.55
        let rightWidth = trackWidth - topCardSpacing - leftWidth

        return EqualHeightHStack(spacing: topCardSpacing) {
            basicPanel
                .frame(width: leftWidth)
            hotKeyPanel
                .frame(width: rightWidth)
        }
        .frame(width: trackWidth, alignment: .leading)
    }

    // MARK: - Basic Panel

    private var basicPanel: some View {
        panel(icon: "slider.horizontal.3", title: "基础", subtitle: "语言、模式、麦克风") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    fieldBlock("语言区域") {
                        fieldShell {
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
                    }
                    .frame(width: 170)

                    fieldBlock("识别模式") {
                        VStack(alignment: .leading, spacing: 5) {
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
                }

                fieldBlock("麦克风") {
                    fieldShell {
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                                .font(.caption)
                                .foregroundStyle(settingsStore.microphoneStatus.isError ? Color.red : textSecondary)

                            Menu {
                                Button("使用系统默认输入设备") {
                                    settingsStore.useSystemDefaultMicrophone()
                                }

                                if !settingsStore.microphoneDevices.isEmpty {
                                    Divider()
                                    ForEach(settingsStore.microphoneDevices) { device in
                                        Button(device.name) {
                                            settingsStore.selectMicrophoneDevice(id: device.id)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(settingsStore.microphoneMenuLabel())
                                        .foregroundStyle(settingsStore.microphoneStatus.isError ? Color.red : textPrimary)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(textSecondary)
                                }
                            }
                            .disabled(
                                settingsStore.microphoneDevices.isEmpty &&
                                settingsStore.settings.microphoneSelectionMode != .specificDevice
                            )

                            Divider().frame(height: 16)

                            Button {
                                settingsStore.reloadMicrophoneDevices()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if settingsStore.microphoneStatus.isError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text(settingsStore.microphoneStatus.detail)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else if appState.isRecording, !appState.activeInputDeviceName.isEmpty {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                        Text("录音中：\(appState.activeInputDeviceName)")
                            .font(.caption)
                            .foregroundStyle(textSecondary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - HotKey Panel

    private var hotKeyPanel: some View {
        panel(icon: "command.square", title: "快捷键", subtitle: "触发听写的组合键") {
            VStack(alignment: .leading, spacing: 14) {
                hotKeyDisplay

                fieldBlock("触发模式") {
                    HStack(spacing: 8) {
                        hotKeyModeButton(
                            mode: .toggle,
                            icon: "hand.tap",
                            label: "按一下切换"
                        )
                        hotKeyModeButton(
                            mode: .pushToTalk,
                            icon: "hand.point.down",
                            label: "按住说话"
                        )
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        toggleHotKeyCapture()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isRecordingHotKey ? "keyboard.badge.ellipsis" : "keyboard")
                                .font(.caption)
                            Text(isRecordingHotKey ? "请按组合键..." : "录入快捷键")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(isRecordingHotKey ? Color.orange : Color(red: 0.16, green: 0.50, blue: 0.94))

                    Button("恢复默认") {
                        stopHotKeyCapture()
                        settingsStore.setHotKey(.default)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if isRecordingHotKey {
                    Label("按 Esc 取消录入", systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !appState.hotKeyWarning.isEmpty {
                    Label(appState.hotKeyWarning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.70, green: 0.40, blue: 0.10))
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var hotKeyDisplay: some View {
        let descriptor = settingsStore.settings.hotKey
        let keys = hotKeyParts(for: descriptor)

        let keyBadgeFill: LinearGradient = colorScheme == .dark
            ? LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color.white, Color(red: 0.94, green: 0.94, blue: 0.96)], startPoint: .top, endPoint: .bottom)
        let keyBadgeStroke = colorScheme == .dark
            ? Color.white.opacity(0.20)
            : Color(red: 0.78, green: 0.80, blue: 0.84)
        let keyBadgeShadow = colorScheme == .dark
            ? Color.black.opacity(0.25)
            : Color.black.opacity(0.08)
        let containerFill = colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color(red: 0.96, green: 0.97, blue: 0.98)
        let containerStroke = colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color(red: 0.88, green: 0.90, blue: 0.92)

        return HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 {
                    Text("+")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textSecondary.opacity(0.6))
                }
                Text(key)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(keyBadgeFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(keyBadgeStroke, lineWidth: 1)
                            )
                            .shadow(color: keyBadgeShadow, radius: 1, x: 0, y: 1)
                    )
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isRecordingHotKey
                    ? Color.orange.opacity(colorScheme == .dark ? 0.12 : 0.06)
                    : containerFill
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isRecordingHotKey
                                ? Color.orange.opacity(0.4)
                                : containerStroke,
                            lineWidth: isRecordingHotKey ? 1.5 : 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isRecordingHotKey)
    }

    private func hotKeyParts(for descriptor: HotKeyDescriptor) -> [String] {
        var parts: [String] = []
        if descriptor.modifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        if descriptor.modifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }
        if descriptor.modifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }
        if descriptor.modifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }
        parts.append(HotKeyCatalog.label(for: descriptor.keyCode))
        return parts
    }

    private func hotKeyModeButton(mode: HotKeyMode, icon: String, label: String) -> some View {
        let isSelected = settingsStore.settings.hotKeyMode == mode
        let accent = Color(red: 0.16, green: 0.50, blue: 0.94)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                settingsStore.settings.hotKeyMode = mode
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? accent : textSecondary)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? textPrimary : textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.08) : fieldFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? accent.opacity(0.35) : fieldStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Behavior Strip (switches in a horizontal bar)

    private var behaviorStrip: some View {
        HStack(spacing: 0) {
            behaviorItem(
                icon: "doc.on.clipboard",
                title: "自动粘贴",
                subtitle: "识别完自动填入光标位置",
                isOn: settingsStore.binding(for: \.autoPaste)
            )

            stripDivider

            behaviorItem(
                icon: "arrow.uturn.backward",
                title: "恢复剪贴板",
                subtitle: "粘贴后还原原有剪贴板",
                isOn: settingsStore.binding(for: \.preserveClipboard)
            )

            stripDivider

            behaviorItem(
                icon: "keyboard",
                title: "输入法切换",
                subtitle: "粘贴前临时切到英文键盘",
                isOn: settingsStore.binding(for: \.switchInputMethodBeforePaste)
            )

            stripDivider

            behaviorItem(
                icon: "waveform.path.ecg",
                title: "福建口音纠错",
                subtitle: "加入地名和常见误识别词",
                isOn: settingsStore.binding(for: \.enableBuiltInFujianPack)
            )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        )
    }

    private func behaviorItem(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        let accentColor = Color(red: 0.16, green: 0.50, blue: 0.94)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isOn.wrappedValue ? accentColor.opacity(0.12) : Color(red: 0.92, green: 0.93, blue: 0.95))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isOn.wrappedValue ? accentColor : textSecondary)
                }

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(textSecondary)
                        .lineLimit(1)
                }

                // Toggle indicator dot
                Circle()
                    .fill(isOn.wrappedValue ? accentColor : Color(red: 0.82, green: 0.84, blue: 0.87))
                    .frame(width: 8, height: 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(fieldStroke.opacity(0.6))
            .frame(width: 1, height: 50)
    }

    // MARK: - Online Panel

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
                        fieldBlock("提供方") {
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
                                HStack(spacing: 10) {
                                    fieldShell {
                                        SecureField("API Key", text: settingsStore.binding(for: \.apiKey))
                                            .textFieldStyle(.plain)
                                            .foregroundStyle(textPrimary)
                                    }

                                    Button {
                                        Task { await settingsStore.testOnlineOptimization() }
                                    } label: {
                                        HStack(spacing: 5) {
                                            if isTestingOnlineOptimization {
                                                ProgressView()
                                                    .controlSize(.small)
                                                    .scaleEffect(0.7)
                                            }
                                            Text(testButtonTitle)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(isTestingOnlineOptimization)
                                    .fixedSize()
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

                        Text("API Key 仅保存在本机，不会上传到第三方。")
                            .font(.caption2)
                            .foregroundStyle(textSecondary)

                        fieldBlock("补充要求") {
                            fieldShell {
                                TextField("可留空", text: settingsStore.binding(for: \.extraPrompt), axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(textPrimary)
                                    .lineLimit(1 ... 2)
                            }
                        }

                        if let message = settingsStore.onlineTestState.message {
                            HStack(spacing: 6) {
                                Image(systemName: settingsStore.onlineTestState.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(settingsStore.onlineTestState.isError ? Color.red : Color.green)
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(settingsStore.onlineTestState.isError ? Color.red : textSecondary)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                            }
                        }
                    } else {
                        Text("在线纠错会在首轮识别结果基础上做一次 LLM 优化。你可以先配置并测试连接，确认可用后再开启。")
                            .font(.caption)
                            .foregroundStyle(textSecondary)

                        fieldBlock("提供方") {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("提供方", selection: Binding(
                                    get: { settingsStore.settings.onlineProvider },
                                    set: { settingsStore.setOnlineProvider($0) }
                                )) {
                                    ForEach(OnlineProvider.allCases) { provider in
                                        Text(provider.title).tag(provider)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.small)

                                Text(settingsStore.settings.onlineProvider.description)
                                    .font(.caption)
                                    .foregroundStyle(textSecondary)
                            }
                        }

                        fieldBlock("API Key") {
                            HStack(spacing: 10) {
                                fieldShell {
                                    SecureField("API Key", text: settingsStore.binding(for: \.apiKey))
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(textPrimary)
                                }

                                Button {
                                    Task { await settingsStore.testOnlineOptimization() }
                                } label: {
                                    HStack(spacing: 5) {
                                        if isTestingOnlineOptimization {
                                            ProgressView()
                                                .controlSize(.small)
                                                .scaleEffect(0.7)
                                        }
                                        Text(testButtonTitle)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isTestingOnlineOptimization)
                                .fixedSize()
                            }
                        }

                        Text("API Key 仅保存在本机，不会上传到第三方。")
                            .font(.caption2)
                            .foregroundStyle(textSecondary)

                        if let message = settingsStore.onlineTestState.message {
                            HStack(spacing: 6) {
                                Image(systemName: settingsStore.onlineTestState.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(settingsStore.onlineTestState.isError ? Color.red : Color.green)
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(settingsStore.onlineTestState.isError ? Color.red : textSecondary)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                            }
                        }

                        HStack(alignment: .top, spacing: 12) {
                            fieldBlock("等待时间") {
                                fieldShell {
                                    TextField("8", value: settingsStore.binding(for: \.onlineSoftTimeoutSeconds), format: .number)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(textPrimary)
                                }
                            }
                            .frame(width: 96)

                            fieldBlock("总超时") {
                                fieldShell {
                                    TextField("8", value: settingsStore.binding(for: \.requestTimeoutSeconds), format: .number)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(textPrimary)
                                }
                            }
                            .frame(width: 96)

                            Spacer(minLength: 0)
                        }

                        Text("等待时间用于决定本地结果要等在线纠错多久；总超时是整个网络请求的上限。建议等待时间先设 8 秒。")
                            .font(.caption)
                            .foregroundStyle(textSecondary)

                        if settingsStore.settings.onlineProvider != .volcengineCodingPlan {
                            HStack(alignment: .top, spacing: 12) {
                                fieldBlock("接口地址") {
                                    fieldShell {
                                        TextField(
                                            settingsStore.settings.onlineProvider == .googleGemini
                                                ? "例如 https://generativelanguage.googleapis.com/v1beta"
                                                : "例如 https://api.openai.com/v1/chat/completions",
                                            text: settingsStore.binding(for: \.apiEndpoint)
                                        )
                                            .textFieldStyle(.plain)
                                            .foregroundStyle(textPrimary)
                                    }
                                }

                                fieldBlock("模型") {
                                    fieldShell {
                                        TextField(
                                            settingsStore.settings.onlineProvider == .googleGemini
                                                ? "例如 gemini-3-flash-preview"
                                                : "例如 gpt-4.1-mini",
                                            text: settingsStore.binding(for: \.modelName)
                                        )
                                            .textFieldStyle(.plain)
                                            .foregroundStyle(textPrimary)
                                    }
                                }
                                .frame(width: 200)
                            }

                            Text(
                                settingsStore.settings.onlineProvider == .googleGemini
                                    ? "使用 Google Gemini 时，普通设置页会显示最小必填项：接口地址、模型名和 API Key。"
                                    : "使用通用 OpenAI 兼容时，普通设置页会显示最小必填项：接口地址、模型名和 API Key。"
                            )
                                .font(.caption)
                                .foregroundStyle(textSecondary)
                        }
                    }

                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text(isDebugSettingsEnabled ? "展开在线优化配置" : "配置与测试")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Spacer()
                    Text(settingsStore.settings.onlineOptimizationEnabled ? "已开启" : "未启用，可先测试")
                        .font(.caption)
                        .foregroundStyle(settingsStore.settings.onlineOptimizationEnabled ? Color(red: 0.22, green: 0.57, blue: 0.31) : textSecondary)
                }
            }
            .tint(textPrimary)
        }
    }

    // MARK: - Correction Panel

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

    // MARK: - Prompt Panel

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
                        title: "角色资产：定义你要它扮演谁",
                        text: settingsStore.promptAssetBinding(for: \.optimizerRolePromptAsset),
                        minHeight: 120
                    )
                    editorColumn(
                        title: "规则资产：整理风格、口语感、禁区",
                        text: settingsStore.promptAssetBinding(for: \.optimizerStylePromptAsset),
                        minHeight: 140
                    )

                    HStack(alignment: .top, spacing: 12) {
                        editorColumn(
                            title: "词汇保护资产：专有名词、品牌、术语",
                            text: settingsStore.promptAssetBinding(for: \.optimizerVocabularyPromptAsset),
                            minHeight: 100
                        )
                        editorColumn(
                            title: "输出资产：只输出什么、不要输出什么",
                            text: settingsStore.promptAssetBinding(for: \.optimizerOutputPromptAsset),
                            minHeight: 100
                        )
                    }

                    editorColumn(
                        title: "用户模板，可用变量：{{EXTRA_PROMPT}} {{PRIORITY_PHRASES}} {{RULE_HINTS}} {{TEXT}}",
                        text: settingsStore.binding(for: \.optimizerUserPromptTemplate),
                        minHeight: 140
                    )

                    Text("系统 prompt 会由角色、规则、词汇保护、输出约束四块资产自动拼成。补充要求仍走在线优化面板里的\u{201C}补充要求\u{201D}。")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
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

    // MARK: - History Panel

    private var historyPanel: some View {
        panel(
            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            title: "历史记录",
            subtitle: "回看、复制、放回预览",
            accessory: {
                Button("清空全部") {
                    appState.clearRecentHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.recentHistory.isEmpty)
            }
        ) {
            DisclosureGroup(isExpanded: $showsHistoryPanel) {
                if appState.recentHistory.isEmpty {
                    Text("最近还没有完成的听写记录。完成一条听写后，这里会自动出现历史内容。")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                        .padding(.top, 8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(appState.recentHistory) { entry in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        pill(entry.optimizationStatus.title, tint: historyTint(for: entry.optimizationStatus))
                                        Text(historyTimestamp(for: entry.createdAt))
                                            .font(.caption)
                                            .foregroundStyle(textSecondary)
                                        if let inputDeviceName = entry.inputDeviceName {
                                            Text("· \(inputDeviceName)")
                                                .font(.caption)
                                                .foregroundStyle(textSecondary)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 8)
                                        Button("复制") {
                                            appState.copyRecentHistoryEntry(entry)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        Button("放到预览") {
                                            appState.restoreRecentHistoryEntry(entry)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    Text(entry.text)
                                        .font(.body)
                                        .foregroundStyle(textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(fieldFill)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(fieldStroke, lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxHeight: 260)
                }
            } label: {
                HStack {
                    Text("展开完整历史")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textPrimary)
                    Spacer()
                    Text("\(appState.recentHistory.count) 条")
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                }
            }
            .tint(textPrimary)
        }
    }

    // MARK: - Shared Components

    private func panel<Accessory: View, Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let accentBlue = Color(red: 0.16, green: 0.47, blue: 0.83)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accentBlue.opacity(0.10), accentBlue.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(accentBlue.opacity(0.12), lineWidth: 0.5)
                            )
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accentBlue)
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
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
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

    // MARK: - HotKey Capture

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

    // MARK: - History Helpers

    private func historyTimestamp(for date: Date) -> String {
        Self.historyDateFormatter.string(from: date)
    }

    private func historyTint(for status: RecentDictationHistoryEntry.OptimizationStatus) -> Color {
        switch status {
        case .localOnly:
            return Color(red: 0.16, green: 0.47, blue: 0.83)
        case .optimized:
            return Color(red: 0.22, green: 0.57, blue: 0.31)
        case .fallbackToLocal:
            return Color(red: 0.80, green: 0.44, blue: 0.18)
        }
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

// MARK: - Equal Height HStack

private struct EqualHeightHStack: Layout {
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxHeight = subviews.map { $0.sizeThatFits(proposal).height }.max() ?? 0
        let totalWidth = subviews.map { $0.sizeThatFits(proposal).width }.reduce(0, +)
            + spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: totalWidth, height: maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(proposal)
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: size.width, height: bounds.height)
            )
            x += size.width + spacing
        }
    }
}

// MARK: - Toggle Style

private struct BrandedSwitchToggleStyle: ToggleStyle {
    private let onTrack = Color(red: 0.16, green: 0.50, blue: 0.94)
    private let offTrack = Color(red: 0.82, green: 0.84, blue: 0.87)
    private let thumb = Color.white
    private let onLabel = Color(red: 0.12, green: 0.17, blue: 0.25)
    private let offLabel = Color(red: 0.45, green: 0.48, blue: 0.52)

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
