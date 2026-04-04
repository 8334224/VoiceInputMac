import Carbon
import Foundation

struct HotKeyDescriptor: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotKeyDescriptor(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | controlKey)
    )
}

struct HotKeyOption: Identifiable, Hashable {
    let id: UInt32
    let keyCode: UInt32
    let label: String
}

enum HotKeyCatalog {
    static let options: [HotKeyOption] = [
        HotKeyOption(id: UInt32(kVK_Space), keyCode: UInt32(kVK_Space), label: "Space"),
        HotKeyOption(id: UInt32(kVK_ANSI_Grave), keyCode: UInt32(kVK_ANSI_Grave), label: "`"),
        HotKeyOption(id: UInt32(kVK_F1), keyCode: UInt32(kVK_F1), label: "F1"),
        HotKeyOption(id: UInt32(kVK_F2), keyCode: UInt32(kVK_F2), label: "F2"),
        HotKeyOption(id: UInt32(kVK_F3), keyCode: UInt32(kVK_F3), label: "F3"),
        HotKeyOption(id: UInt32(kVK_F4), keyCode: UInt32(kVK_F4), label: "F4"),
        HotKeyOption(id: UInt32(kVK_F5), keyCode: UInt32(kVK_F5), label: "F5"),
        HotKeyOption(id: UInt32(kVK_F6), keyCode: UInt32(kVK_F6), label: "F6"),
        HotKeyOption(id: UInt32(kVK_F7), keyCode: UInt32(kVK_F7), label: "F7"),
        HotKeyOption(id: UInt32(kVK_F8), keyCode: UInt32(kVK_F8), label: "F8"),
        HotKeyOption(id: UInt32(kVK_F9), keyCode: UInt32(kVK_F9), label: "F9"),
        HotKeyOption(id: UInt32(kVK_F10), keyCode: UInt32(kVK_F10), label: "F10"),
        HotKeyOption(id: UInt32(kVK_F11), keyCode: UInt32(kVK_F11), label: "F11"),
        HotKeyOption(id: UInt32(kVK_F12), keyCode: UInt32(kVK_F12), label: "F12")
    ]

    private static let keyLabels: [UInt32: String] = [
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_Command): "Command",
        UInt32(kVK_Shift): "Shift",
        UInt32(kVK_CapsLock): "Caps Lock",
        UInt32(kVK_Option): "Option",
        UInt32(kVK_Control): "Control",
        UInt32(kVK_RightShift): "Right Shift",
        UInt32(kVK_RightOption): "Right Option",
        UInt32(kVK_RightControl): "Right Control",
        UInt32(kVK_Function): "Fn",
        UInt32(kVK_F17): "F17",
        UInt32(kVK_VolumeUp): "Volume Up",
        UInt32(kVK_VolumeDown): "Volume Down",
        UInt32(kVK_Mute): "Mute",
        UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19",
        UInt32(kVK_F20): "F20",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F13): "F13",
        UInt32(kVK_F16): "F16",
        UInt32(kVK_F14): "F14",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F12): "F12",
        UInt32(kVK_F15): "F15",
        UInt32(kVK_Help): "Help",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_ForwardDelete): "Forward Delete",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_End): "End",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_LeftArrow): "Left",
        UInt32(kVK_RightArrow): "Right",
        UInt32(kVK_DownArrow): "Down",
        UInt32(kVK_UpArrow): "Up",
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`"
    ]

    static func label(for descriptor: HotKeyDescriptor) -> String {
        let keyLabel = label(for: descriptor.keyCode)
        var parts: [String] = []
        if descriptor.modifiers & UInt32(controlKey) != 0 { parts.append("Control") }
        if descriptor.modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if descriptor.modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if descriptor.modifiers & UInt32(cmdKey) != 0 { parts.append("Command") }
        parts.append(keyLabel)
        return parts.joined(separator: " + ")
    }

    static func label(for keyCode: UInt32) -> String {
        keyLabels[keyCode]
            ?? options.first(where: { $0.keyCode == keyCode })?.label
            ?? "Key \(keyCode)"
    }

    static func isModifierKey(_ keyCode: UInt32) -> Bool {
        [
            UInt32(kVK_Command),
            UInt32(kVK_Shift),
            UInt32(kVK_CapsLock),
            UInt32(kVK_Option),
            UInt32(kVK_Control),
            UInt32(kVK_RightShift),
            UInt32(kVK_RightOption),
            UInt32(kVK_RightControl),
            UInt32(kVK_Function)
        ].contains(keyCode)
    }
}

final class HotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onPressed: () -> Void
    private let onReleased: () -> Void
    private let hotKeyID = EventHotKeyID(signature: OSType(0x56494D43), id: 1)
    private var currentDescriptor: HotKeyDescriptor?

    init(onPressed: @escaping () -> Void, onReleased: @escaping () -> Void = {}) {
        self.onPressed = onPressed
        self.onReleased = onReleased
        installEventHandlerIfNeeded()
    }

    deinit {
        // Remove event handler first so the callback cannot fire on a
        // partially-deallocated controller after the hotkey is unregistered.
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        unregister()
    }

    @discardableResult
    func update(descriptor: HotKeyDescriptor) -> String? {
        let previousDescriptor = currentDescriptor
        unregister()

        let status = register(descriptor: descriptor)

        guard status == noErr else {
            hotKeyRef = nil
            if let previousDescriptor {
                _ = register(descriptor: previousDescriptor)
            }
            if status == eventHotKeyExistsErr {
                return "快捷键已被系统或其他应用占用，已保留上一次可用快捷键。你仍可从菜单栏点击“开始听写”。"
            }
            return "快捷键注册失败，已保留上一次可用快捷键。你仍可从菜单栏点击“开始听写”。错误码：\(status)。"
        }

        currentDescriptor = descriptor
        return nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var receivedHotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedHotKeyID
                )

                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                guard receivedHotKeyID.id == controller.hotKeyID.id else { return noErr }

                let kind = GetEventKind(event)
                if kind == UInt32(kEventHotKeyPressed) {
                    controller.onPressed()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    controller.onReleased()
                }

                return noErr
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func register(descriptor: HotKeyDescriptor) -> OSStatus {
        RegisterEventHotKey(
            descriptor.keyCode,
            descriptor.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
