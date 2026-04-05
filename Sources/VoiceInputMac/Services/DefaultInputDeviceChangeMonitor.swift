import CoreAudio
import Foundation

struct DefaultInputDeviceChangeEvent: Equatable, Sendable {
    let deviceID: String?
    let deviceName: String?

    var logDescription: String {
        let name = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = deviceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return "default name=\(name?.nilIfBlank ?? "-") id=\(id?.nilIfBlank ?? "-")"
    }
}

protocol DefaultInputDeviceChangeObserving: AnyObject, Sendable {
    func startObserving(_ onChange: @escaping @MainActor (DefaultInputDeviceChangeEvent) -> Void)
    func stopObserving()
}

protocol DefaultInputDeviceMonitoringBackend: AnyObject, Sendable {
    func currentDefaultInputDeviceUID() -> String?
    func startObserving(_ onChange: @escaping @Sendable () -> Void) throws
    func stopObserving()
}

final class CoreAudioDefaultInputDeviceChangeMonitor: DefaultInputDeviceChangeObserving, @unchecked Sendable {
    private let deviceProvider: MicrophoneDeviceProviding
    private let backend: DefaultInputDeviceMonitoringBackend
    private var onChange: (@MainActor (DefaultInputDeviceChangeEvent) -> Void)?
    private var lastSeenDeviceID: String?

    init(
        deviceProvider: MicrophoneDeviceProviding = MicrophoneDeviceService(),
        backend: DefaultInputDeviceMonitoringBackend = CoreAudioDefaultInputDeviceMonitoringBackend()
    ) {
        self.deviceProvider = deviceProvider
        self.backend = backend
    }

    func startObserving(_ onChange: @escaping @MainActor (DefaultInputDeviceChangeEvent) -> Void) {
        stopObserving()
        self.onChange = onChange
        lastSeenDeviceID = backend.currentDefaultInputDeviceUID()

        do {
            try backend.startObserving { [weak self] in
                self?.handleDefaultInputDeviceChange()
            }
        } catch {
            print("[DefaultInputDeviceChangeMonitor] failed to start observing: \(error.localizedDescription)")
        }
    }

    func stopObserving() {
        backend.stopObserving()
        onChange = nil
        lastSeenDeviceID = nil
    }

    private func handleDefaultInputDeviceChange() {
        let currentDeviceID = backend.currentDefaultInputDeviceUID()
        guard currentDeviceID != lastSeenDeviceID else { return }
        lastSeenDeviceID = currentDeviceID

        let currentDefaultDevice = deviceProvider.systemDefaultInputDevice()
        let event = DefaultInputDeviceChangeEvent(
            deviceID: currentDefaultDevice?.id ?? currentDeviceID,
            deviceName: currentDefaultDevice?.name
        )
        print("[DefaultInputDeviceChangeMonitor] event \(event.logDescription)")
        Task { @MainActor [onChange] in
            onChange?(event)
        }
    }
}

final class CoreAudioDefaultInputDeviceMonitoringBackend: DefaultInputDeviceMonitoringBackend, @unchecked Sendable {
    private let notificationQueue = DispatchQueue(label: "VoiceInputMac.DefaultInputDeviceChangeMonitor")
    private var isObserving = false
    private var onChange: (@Sendable () -> Void)?
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    func currentDefaultInputDeviceUID() -> String? {
        var deviceID = AudioDeviceID(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else {
            return nil
        }
        return audioDeviceUID(for: deviceID)
    }

    func startObserving(_ onChange: @escaping @Sendable () -> Void) throws {
        stopObserving()
        self.onChange = onChange
        listenerBlock = { [weak self] _, _ in
            self?.onChange?()
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard let listenerBlock else {
            self.onChange = nil
            throw CoreAudioDefaultInputDeviceMonitoringError.listenerRegistrationFailed(kAudioHardwareUnspecifiedError)
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            notificationQueue
        , listenerBlock)

        guard status == noErr else {
            self.onChange = nil
            self.listenerBlock = nil
            throw CoreAudioDefaultInputDeviceMonitoringError.listenerRegistrationFailed(status)
        }

        isObserving = true
    }

    func stopObserving() {
        guard isObserving else {
            onChange = nil
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        if let listenerBlock {
            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                notificationQueue,
                listenerBlock
            )

            if status != noErr {
                print("[DefaultInputDeviceChangeMonitor] failed to stop observing default input device: \(status)")
            }
        }

        isObserving = false
        onChange = nil
        listenerBlock = nil
    }
}

private enum CoreAudioDefaultInputDeviceMonitoringError: LocalizedError {
    case listenerRegistrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .listenerRegistrationFailed(status):
            return "默认输入设备监听注册失败（OSStatus: \(status)）。"
        }
    }
}

private func audioDeviceUID(for deviceID: AudioDeviceID) -> String? {
    var uid: CFString = "" as CFString
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(deviceID),
        &address,
        0,
        nil,
        &size,
        &uid
    )
    guard status == noErr else { return nil }
    return uid as String
}

