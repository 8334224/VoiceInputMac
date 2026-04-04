import XCTest
@testable import VoiceInputMac

@MainActor
final class AppStateActiveInputDeviceTests: XCTestCase {
    func testStartRecordingShowsActualInputDeviceName() async {
        let pipeline = FakeDictationPipelineForAppState()
        pipeline.nextStartDevice = ActiveInputDeviceInfo(id: "usb-1", name: "USB 麦克风", selectionMode: .specificDevice)
        let appState = makeAppState(pipeline: pipeline)

        await appState.startRecording()

        XCTAssertTrue(appState.isRecording)
        XCTAssertEqual(appState.activeInputDeviceName, "USB 麦克风")
        XCTAssertEqual(appState.statusText, "正在通过USB 麦克风听写...")
    }

    func testStopRecordingClearsActiveInputDeviceName() async {
        let pipeline = FakeDictationPipelineForAppState()
        pipeline.nextStartDevice = ActiveInputDeviceInfo(id: "built-in", name: "MacBook 麦克风", selectionMode: .systemDefault)
        let appState = makeAppState(pipeline: pipeline)

        await appState.startRecording()
        await appState.stopRecording()

        XCTAssertFalse(appState.isRecording)
        XCTAssertEqual(appState.activeInputDeviceName, "")
    }

    func testRuntimeFailureClearsActiveInputDeviceName() async {
        let pipeline = FakeDictationPipelineForAppState()
        pipeline.nextStartDevice = ActiveInputDeviceInfo(id: "usb-1", name: "USB 麦克风", selectionMode: .specificDevice)
        let appState = makeAppState(pipeline: pipeline)

        await appState.startRecording()
        pipeline.emitRuntimeFailure(AudioCaptureService.AudioCaptureError.selectedInputDeviceUnavailable("USB 麦克风"))
        await Task.yield()

        XCTAssertFalse(appState.isRecording)
        XCTAssertEqual(appState.activeInputDeviceName, "")
        XCTAssertEqual(appState.statusText, "所选麦克风不可用")
    }

    func testSecondRecordingRefreshesDisplayedDeviceName() async {
        let pipeline = FakeDictationPipelineForAppState()
        let appState = makeAppState(pipeline: pipeline)

        pipeline.nextStartDevice = ActiveInputDeviceInfo(id: "built-in", name: "MacBook 麦克风", selectionMode: .systemDefault)
        await appState.startRecording()
        await appState.stopRecording()

        pipeline.nextStartDevice = ActiveInputDeviceInfo(id: "usb-2", name: "USB 麦克风 2", selectionMode: .specificDevice)
        await appState.startRecording()

        XCTAssertEqual(appState.activeInputDeviceName, "USB 麦克风 2")
        XCTAssertEqual(appState.statusText, "正在通过USB 麦克风 2听写...")
    }

    private func makeAppState(pipeline: FakeDictationPipelineForAppState) -> AppState {
        let suite = "AppStateActiveInputDeviceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settingsStore = SettingsStore(
            userDefaults: defaults,
            microphoneDeviceProvider: FakeMicrophoneDeviceProviderForAppState(),
            microphoneDeviceChangeMonitor: LocalFakeMicrophoneDeviceChangeMonitorForAppState(),
            defaultInputDeviceChangeMonitor: LocalFakeDefaultInputDeviceChangeMonitorForAppState()
        )
        settingsStore.settings.autoPaste = false
        return AppState(
            settingsStore: settingsStore,
            dictationPipeline: pipeline,
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

private final class FakeDictationPipelineForAppState: DictationPipelineControlling, @unchecked Sendable {
    var nextStartDevice = ActiveInputDeviceInfo(id: nil, name: "当前输入设备", selectionMode: .systemDefault)
    private var failureHandler: ((Error) -> Void)?

    func start(
        settings: AppSettings,
        onStatus: @escaping @Sendable (String) -> Void,
        onPreview: @escaping @Sendable (String) -> Void,
        onSegments: @escaping @Sendable ([TranscriptSegment]) -> Void,
        onActiveInputDevice: @escaping @Sendable (ActiveInputDeviceInfo) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) async throws {
        failureHandler = onFailure
        onActiveInputDevice(nextStartDevice)
    }

    func stop(
        settings: AppSettings,
        onStatus: @escaping @Sendable (String) -> Void,
        onSegments: @escaping @Sendable ([TranscriptSegment]) -> Void
    ) async throws -> DictationPipeline.StopResult {
        .init(text: "", onlineOptimizationStatus: .disabled)
    }

    func cancelCurrentSession() {}
    func setReRecognitionOrderMode(_ mode: ReRecognitionOrderMode) {}
    func setExperimentPathEnabled(_ enabled: Bool) {}
    func setReRecognitionExperimentTag(sampleLabel: ReRecognitionExperimentSampleLabel?, sessionTag: String?) {}
    func saveLatestReRecognitionExperimentJSON(prettyPrinted: Bool) async throws -> URL { URL(fileURLWithPath: "/tmp/fake.json") }
    func reRecognitionExperimentExportDirectoryURL() throws -> URL { URL(fileURLWithPath: "/tmp") }

    func emitRuntimeFailure(_ error: Error) {
        failureHandler?(error)
    }
}

private struct FakeMicrophoneDeviceProviderForAppState: MicrophoneDeviceProviding {
    func availableInputDevices() throws -> [MicrophoneDeviceInfo] { [] }
    func systemDefaultInputDevice() -> MicrophoneDeviceInfo? { nil }
}

private final class LocalFakeMicrophoneDeviceChangeMonitorForAppState: MicrophoneDeviceChangeObserving, @unchecked Sendable {
    func startObserving(_ onChange: @escaping @MainActor (MicrophoneDeviceChangeEvent) -> Void) {}
    func stopObserving() {}
}

private final class LocalFakeDefaultInputDeviceChangeMonitorForAppState: DefaultInputDeviceChangeObserving, @unchecked Sendable {
    func startObserving(_ onChange: @escaping @MainActor (DefaultInputDeviceChangeEvent) -> Void) {}
    func stopObserving() {}
}
