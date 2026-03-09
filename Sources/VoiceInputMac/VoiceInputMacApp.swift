import SwiftUI

@main
struct VoiceInputMacApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var appState: AppState
    private let speechHUDController: SpeechHUDController

    init() {
        let store = SettingsStore()
        let state = AppState(settingsStore: store)
        _settingsStore = StateObject(wrappedValue: store)
        _appState = StateObject(wrappedValue: state)
        speechHUDController = SpeechHUDController(appState: state)
    }

    var body: some Scene {
        MenuBarExtra("MOMO语音输入法", systemImage: appState.isRecording ? "waveform.circle.fill" : "mic.circle") {
            MenuBarContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
        }
    }
}
