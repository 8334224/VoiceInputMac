@preconcurrency import AVFoundation
import Foundation

struct MicrophoneDeviceChangeEvent: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case connected
        case disconnected
    }

    let kind: Kind
    let deviceID: String?
    let deviceName: String?

    var logDescription: String {
        let name = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = deviceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(kind.rawValue) name=\(name?.nilIfBlank ?? "-") id=\(id?.nilIfBlank ?? "-")"
    }
}

protocol MicrophoneDeviceChangeObserving: AnyObject, Sendable {
    func startObserving(_ onChange: @escaping @MainActor (MicrophoneDeviceChangeEvent) -> Void)
    func stopObserving()
}

final class AVFoundationMicrophoneDeviceChangeMonitor: MicrophoneDeviceChangeObserving, @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let connectedNotification: Notification.Name
    private let disconnectedNotification: Notification.Name
    private var observers: [NSObjectProtocol] = []
    private var onChange: (@MainActor (MicrophoneDeviceChangeEvent) -> Void)?

    init(
        notificationCenter: NotificationCenter = .default,
        connectedNotification: Notification.Name = AVCaptureDevice.wasConnectedNotification,
        disconnectedNotification: Notification.Name = AVCaptureDevice.wasDisconnectedNotification
    ) {
        self.notificationCenter = notificationCenter
        self.connectedNotification = connectedNotification
        self.disconnectedNotification = disconnectedNotification
    }

    func startObserving(_ onChange: @escaping @MainActor (MicrophoneDeviceChangeEvent) -> Void) {
        stopObserving()
        self.onChange = onChange

        observers = [
            notificationCenter.addObserver(
                forName: connectedNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.handleNotification(notification, kind: .connected)
            },
            notificationCenter.addObserver(
                forName: disconnectedNotification,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.handleNotification(notification, kind: .disconnected)
            }
        ]
    }

    func stopObserving() {
        observers.forEach(notificationCenter.removeObserver)
        observers.removeAll()
        onChange = nil
    }

    private func handleNotification(_ notification: Notification, kind: MicrophoneDeviceChangeEvent.Kind) {
        let device = notification.object as? AVCaptureDevice
        let event = MicrophoneDeviceChangeEvent(
            kind: kind,
            deviceID: device?.uniqueID,
            deviceName: device?.localizedName
        )
        print("[MicrophoneDeviceChangeMonitor] event \(event.logDescription)")
        Task { @MainActor [onChange] in
            onChange?(event)
        }
    }
}
