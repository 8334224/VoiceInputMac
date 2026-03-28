@preconcurrency import AVFoundation
import Foundation

struct MicrophoneDeviceInfo: Identifiable, Hashable, Equatable, Sendable {
    let id: String
    let name: String
    let isSystemDefault: Bool
}

protocol MicrophoneDeviceProviding: Sendable {
    func availableInputDevices() throws -> [MicrophoneDeviceInfo]
    func systemDefaultInputDevice() -> MicrophoneDeviceInfo?
}

struct MicrophoneDeviceService: MicrophoneDeviceProviding {
    enum DeviceServiceError: LocalizedError {
        case enumerationFailed

        var errorDescription: String? {
            switch self {
            case .enumerationFailed:
                return "无法读取当前麦克风设备列表。"
            }
        }
    }

    func availableInputDevices() throws -> [MicrophoneDeviceInfo] {
        let defaultDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        let devices = microphoneCaptureDevices()
        let mapped = devices.map {
            MicrophoneDeviceInfo(
                id: $0.uniqueID,
                name: $0.localizedName,
                isSystemDefault: $0.uniqueID == defaultDeviceID
            )
        }
        let sorted = mapped.sorted { lhs, rhs in
            if lhs.isSystemDefault != rhs.isSystemDefault {
                return lhs.isSystemDefault && !rhs.isSystemDefault
            }
            if lhs.name == rhs.name {
                return lhs.id < rhs.id
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        logDevices(sorted)
        return sorted
    }

    func systemDefaultInputDevice() -> MicrophoneDeviceInfo? {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            print("[MicrophoneDeviceService] default input device unavailable")
            return nil
        }

        let info = MicrophoneDeviceInfo(
            id: device.uniqueID,
            name: device.localizedName,
            isSystemDefault: true
        )
        print("[MicrophoneDeviceService] default input device=\(device.localizedName) (\(device.uniqueID))")
        return info
    }

    private func logDevices(_ devices: [MicrophoneDeviceInfo]) {
        let names = devices.map { "\($0.name)(\($0.id))" }.joined(separator: ", ")
        print("[MicrophoneDeviceService] loaded \(devices.count) input device(s): \(names)")
    }
}

func microphoneCaptureDevices() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone, .external],
        mediaType: .audio,
        position: .unspecified
    ).devices
}
