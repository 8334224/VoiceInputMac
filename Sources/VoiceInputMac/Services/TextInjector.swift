import AppKit
import ApplicationServices
import Foundation

@MainActor
final class TextInjector {
    func paste(_ text: String, preserveClipboard: Bool) {
        let pasteboard = NSPasteboard.general
        let originalString = preserveClipboard ? pasteboard.string(forType: .string) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.sendPasteShortcut()

            guard preserveClipboard else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                pasteboard.clearContents()
                if let originalString {
                    pasteboard.setString(originalString, forType: .string)
                }
            }
        }
    }

    private func sendPasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode: CGKeyCode = 9
        let flags: CGEventFlags = .maskCommand

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
