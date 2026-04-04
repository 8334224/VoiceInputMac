import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState

    private struct SampleLabelOption: Identifiable {
        let id: String
        let title: String
        let value: ReRecognitionExperimentSampleLabel?
    }

    private let sampleLabelOptions: [SampleLabelOption] = [
        .init(id: "none", title: "未标记", value: nil),
        .init(id: ReRecognitionExperimentSampleLabel.hotword.rawValue, title: "hotword", value: .hotword),
        .init(id: ReRecognitionExperimentSampleLabel.englishAbbreviation.rawValue, title: "english_abbreviation", value: .englishAbbreviation),
        .init(id: ReRecognitionExperimentSampleLabel.numberUnit.rawValue, title: "number_unit", value: .numberUnit),
        .init(id: ReRecognitionExperimentSampleLabel.longSentence.rawValue, title: "long_sentence", value: .longSentence)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(appState.isRecording ? "正在听写" : "语音输入")
                    .font(.headline)
                Spacer()
                Text(appState.hotKeyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(appState.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if appState.isRecording, !appState.activeInputDeviceName.isEmpty {
                Text("当前输入：\(appState.activeInputDeviceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !appState.completionDetail.isEmpty {
                Text(appState.completionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(appState.transcriptPreview.isEmpty ? "按下热键后开始说话，再按一次结束。" : appState.transcriptPreview)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(width: 360, height: 140)
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

            if !appState.recentHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最近记录")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("清空记录") {
                            appState.clearRecentHistory()
                        }
                        .font(.caption)
                    }

                    ForEach(Array(appState.recentHistory.prefix(3))) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.optimizationStatus.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                if let inputDeviceName = entry.inputDeviceName {
                                    Text("· \(inputDeviceName)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(entry.text)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
            }

            if !appState.hotKeyWarning.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(appState.hotKeyWarning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !appState.accessibilityWarning.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(appState.accessibilityWarning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("打开辅助功能设置") {
                        appState.openAccessibilitySettings()
                    }
                    .font(.caption)
                }
            }

            if !appState.lastError.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(appState.lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !appState.recoveryActionTitle.isEmpty {
                        Button(appState.recoveryActionTitle) {
                            appState.performRecoveryAction()
                        }
                        .font(.caption)
                    }
                }
            }

            HStack {
                Button(appState.isRecording ? "结束听写" : "开始听写") {
                    Task { await appState.toggleRecording() }
                }

                Button("清空") {
                    appState.clearTranscript()
                }
            }

            if appState.isExperimentUIEnabled {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("固定样本实验")
                        .font(.subheadline.weight(.semibold))

                    Picker("重识别顺序", selection: $appState.experimentOrderMode) {
                        Text("fixed").tag(ReRecognitionOrderMode.fixed)
                        Text("session").tag(ReRecognitionOrderMode.session)
                        Text("blended").tag(ReRecognitionOrderMode.blended)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)

                    Picker("样本标签", selection: $appState.experimentSampleLabel) {
                        ForEach(sampleLabelOptions) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("sessionTag，例如 sample-01", text: $appState.experimentSessionTag)
                        .textFieldStyle(.roundedBorder)

                    Button("导出本次实验 JSON") {
                        Task { await appState.exportLatestExperimentJSON() }
                    }
                    .disabled(appState.transcriptPreview.isEmpty && appState.finalTranscript.isEmpty)

                    Text("导出目录：\(appState.experimentExportDirectoryPath())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if !appState.lastExperimentExportPath.isEmpty {
                        Text("最近导出：\(appState.lastExperimentExportPath)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Divider()
            }

            HStack {
                SettingsLink {
                    Text("设置")
                }
                Spacer()
                Button("退出") {
                    appState.terminateApplication()
                }
            }
        }
        .padding(14)
    }
}
