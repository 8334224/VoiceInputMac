import AVFoundation
import Foundation
import Speech

enum PermissionsCoordinator {
    static func requestAll() async -> Bool {
        let speechAuthorized = await requestSpeechRecognition()
        let microphoneAuthorized = await requestMicrophone()
        return speechAuthorized && microphoneAuthorized
    }

    static func requestSpeechRecognition() async -> Bool {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        if currentStatus == .authorized {
            return true
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func requestMicrophone() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if currentStatus == .authorized {
            return true
        }

        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
