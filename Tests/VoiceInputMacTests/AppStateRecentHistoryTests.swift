import XCTest
@testable import VoiceInputMac

@MainActor
final class AppStateRecentHistoryTests: XCTestCase {
    func testStopRecordingStoresRecentHistoryEntry() async {
        let pipeline = FakeHistoryDictationPipeline()
        pipeline.nextStartDevice = ActiveInputDeviceInfo(id: "usb-1", name: "USB 麦克风", selectionMode: .specificDevice)
        pipeline.stopResult = .init(text: "第一条记录", onlineOptimizationStatus: .optimized)
        let historyStore = InMemoryRecentHistoryStore()
        let appState = makeAppState(pipeline: pipeline, historyStore: historyStore)

        await appState.startRecording()
        await appState.stopRecording()

        XCTAssertEqual(appState.recentHistory.count, 1)
        XCTAssertEqual(appState.recentHistory.first?.text, "第一条记录")
        XCTAssertEqual(appState.recentHistory.first?.inputDeviceName, "USB 麦克风")
        XCTAssertEqual(appState.recentHistory.first?.optimizationStatus, .optimized)
    }

    func testSecondCompletedRecordingAppearsFirstInHistory() async {
        let pipeline = FakeHistoryDictationPipeline()
        let historyStore = InMemoryRecentHistoryStore()
        let appState = makeAppState(pipeline: pipeline, historyStore: historyStore)

        pipeline.nextStartDevice = ActiveInputDeviceInfo(id: "built-in", name: "MacBook 麦克风", selectionMode: .systemDefault)
        pipeline.stopResult = .init(text: "第一条记录", onlineOptimizationStatus: .disabled)
        await appState.startRecording()
        await appState.stopRecording()

        pipeline.nextStartDevice = ActiveInputDeviceInfo(id: "usb-1", name: "USB 麦克风", selectionMode: .specificDevice)
        pipeline.stopResult = .init(text: "第二条记录", onlineOptimizationStatus: .fallback("超时"))
        await appState.startRecording()
        await appState.stopRecording()

        XCTAssertEqual(appState.recentHistory.map(\.text), ["第二条记录", "第一条记录"])
        XCTAssertEqual(appState.recentHistory.first?.inputDeviceName, "USB 麦克风")
        XCTAssertEqual(appState.recentHistory.first?.optimizationStatus, .fallbackToLocal)
    }

    func testRestoreRecentHistoryEntryLoadsTranscriptBackIntoPreview() {
        let pipeline = FakeHistoryDictationPipeline()
        let historyStore = InMemoryRecentHistoryStore()
        let appState = makeAppState(pipeline: pipeline, historyStore: historyStore)
        let entry = RecentDictationHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            text: "历史里的文本",
            inputDeviceName: "MacBook 麦克风",
            optimizationStatus: .localOnly
        )

        appState.restoreRecentHistoryEntry(entry)

        XCTAssertEqual(appState.transcriptPreview, "历史里的文本")
        XCTAssertEqual(appState.finalTranscript, "历史里的文本")
        XCTAssertEqual(appState.statusText, "已载入历史记录")
        XCTAssertEqual(appState.completionDetail, "已载入来自 MacBook 麦克风 的历史记录。")
    }

    func testCopyRecentHistoryEntryUpdatesStatusWithoutChangingPreview() {
        let pipeline = FakeHistoryDictationPipeline()
        let historyStore = InMemoryRecentHistoryStore()
        let appState = makeAppState(pipeline: pipeline, historyStore: historyStore)
        appState.transcriptPreview = "原来的预览"
        let entry = RecentDictationHistoryEntry(
            id: UUID(),
            createdAt: Date(),
            text: "用于复制的文本",
            inputDeviceName: nil,
            optimizationStatus: .optimized
        )

        appState.copyRecentHistoryEntry(entry)

        XCTAssertEqual(appState.transcriptPreview, "原来的预览")
        XCTAssertEqual(appState.statusText, "历史记录已复制")
        XCTAssertEqual(appState.completionDetail, "已复制一条历史记录。")
    }

    private func makeAppState(
        pipeline: FakeHistoryDictationPipeline,
        historyStore: InMemoryRecentHistoryStore
    ) -> AppState {
        let suite = "AppStateRecentHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settingsStore = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: FakeMicrophoneDeviceProviderForRecentHistory(),
            microphoneDeviceChangeMonitor: LocalFakeMicrophoneDeviceChangeMonitorForRecentHistory(),
            defaultInputDeviceChangeMonitor: LocalFakeDefaultInputDeviceChangeMonitorForRecentHistory()
        )
        settingsStore.settings.autoPaste = false
        return AppState(
            settingsStore: settingsStore,
            dictationPipeline: pipeline,
            recentHistoryStore: historyStore,
            requestPermissions: {
                PermissionsCoordinator.Snapshot(
                    speechRecognition: .authorized,
                    microphone: .authorized
                )
            },
            accessibilityTrustChecker: { _ in true }
        )
    }
}

private final class FakeHistoryDictationPipeline: DictationPipelineControlling, @unchecked Sendable {
    var nextStartDevice = ActiveInputDeviceInfo(id: nil, name: "当前输入设备", selectionMode: .systemDefault)
    var stopResult = DictationPipeline.StopResult(text: "", onlineOptimizationStatus: .disabled)

    func start(
        settings: AppSettings,
        onStatus: @escaping @Sendable (String) -> Void,
        onPreview: @escaping @Sendable (String) -> Void,
        onSegments: @escaping @Sendable ([TranscriptSegment]) -> Void,
        onActiveInputDevice: @escaping @Sendable (ActiveInputDeviceInfo) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) async throws {
        onActiveInputDevice(nextStartDevice)
    }

    func stop(
        settings: AppSettings,
        onStatus: @escaping @Sendable (String) -> Void,
        onSegments: @escaping @Sendable ([TranscriptSegment]) -> Void
    ) async throws -> DictationPipeline.StopResult {
        stopResult
    }

    func cancelCurrentSession() {}
    func setReRecognitionOrderMode(_ mode: ReRecognitionOrderMode) {}
    func setExperimentPathEnabled(_ enabled: Bool) {}
    func setReRecognitionExperimentTag(sampleLabel: ReRecognitionExperimentSampleLabel?, sessionTag: String?) {}
    func saveLatestReRecognitionExperimentJSON(prettyPrinted: Bool) async throws -> URL { URL(fileURLWithPath: "/tmp/fake.json") }
    func reRecognitionExperimentExportDirectoryURL() throws -> URL { URL(fileURLWithPath: "/tmp") }
}

private final class InMemoryRecentHistoryStore: RecentDictationHistoryStoring, @unchecked Sendable {
    private var records: [RecentDictationHistoryEntry] = []

    func load() -> [RecentDictationHistoryEntry] {
        records
    }

    func record(_ entry: RecentDictationHistoryEntry) -> [RecentDictationHistoryEntry] {
        records.insert(entry, at: 0)
        return records
    }

    func clear() -> [RecentDictationHistoryEntry] {
        records.removeAll()
        return records
    }
}

private struct FakeMicrophoneDeviceProviderForRecentHistory: MicrophoneDeviceProviding {
    func availableInputDevices() throws -> [MicrophoneDeviceInfo] { [] }
    func systemDefaultInputDevice() -> MicrophoneDeviceInfo? { nil }
}

private final class LocalFakeMicrophoneDeviceChangeMonitorForRecentHistory: MicrophoneDeviceChangeObserving, @unchecked Sendable {
    func startObserving(_ onChange: @escaping @MainActor (MicrophoneDeviceChangeEvent) -> Void) {}
    func stopObserving() {}
}

private final class LocalFakeDefaultInputDeviceChangeMonitorForRecentHistory: DefaultInputDeviceChangeObserving, @unchecked Sendable {
    func startObserving(_ onChange: @escaping @MainActor (DefaultInputDeviceChangeEvent) -> Void) {}
    func stopObserving() {}
}
