import AVFoundation
import AppKit
import Foundation
import Speech

enum PermissionsCoordinator {
    enum AuthorizationState: Equatable {
        case authorized
        case denied
        case restricted
        case notDetermined
    }

    enum SettingsTarget {
        case privacy
        case microphone
        case speechRecognition
    }

    struct Snapshot {
        let speechRecognition: AuthorizationState
        let microphone: AuthorizationState

        var allAuthorized: Bool {
            speechRecognition == .authorized && microphone == .authorized
        }

        var recoveryMessage: String {
            switch (speechRecognition, microphone) {
            case (.authorized, .authorized):
                return ""
            case (.denied, .denied), (.restricted, .restricted), (.denied, .restricted), (.restricted, .denied):
                return "请在 系统设置 > 隐私与安全性 中打开“麦克风”和“语音识别”权限后，再回到菜单栏重新开始听写。"
            case (.denied, _), (.restricted, _):
                return "语音识别权限未开启。请在 系统设置 > 隐私与安全性 > 语音识别 中允许本应用，然后重新开始听写。"
            case (_, .denied), (_, .restricted):
                return "麦克风权限未开启。请在 系统设置 > 隐私与安全性 > 麦克风 中允许本应用，然后重新开始听写。"
            case (.notDetermined, _), (_, .notDetermined):
                return "请允许麦克风和语音识别权限后，再重新开始听写。"
            }
        }

        var recoveryTarget: SettingsTarget? {
            switch (speechRecognition, microphone) {
            case (.authorized, .authorized):
                return nil
            case (.denied, .denied), (.restricted, .restricted), (.denied, .restricted), (.restricted, .denied):
                return .privacy
            case (.denied, _), (.restricted, _):
                return .speechRecognition
            case (_, .denied), (_, .restricted):
                return .microphone
            case (.notDetermined, _), (_, .notDetermined):
                return .privacy
            }
        }
    }

    static func requestAll() async -> Snapshot {
        let speechAuthorized = await requestSpeechRecognition()
        let microphoneAuthorized = await requestMicrophone()
        return Snapshot(
            speechRecognition: speechAuthorized,
            microphone: microphoneAuthorized
        )
    }

    static func requestSpeechRecognition() async -> AuthorizationState {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        if currentStatus != .notDetermined {
            return mapSpeechStatus(currentStatus)
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: mapSpeechStatus(status))
            }
        }
    }

    static func requestMicrophone() async -> AuthorizationState {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if currentStatus != .notDetermined {
            return mapMicrophoneStatus(currentStatus)
        }

        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .authorized : mapMicrophoneStatus(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    static func openSettings(for target: SettingsTarget) {
        let urlString: String
        switch target {
        case .privacy:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        }

        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func mapSpeechStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }

    private static func mapMicrophoneStatus(_ status: AVAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }
}
