import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
final class TextInjector {
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Delay before sending Cmd+V after setting the clipboard.
    private static let prePasteDelay: TimeInterval = 0.10
    /// Delay after Cmd+V before restoring clipboard / input source.
    /// Needs to be long enough for the target app to read the clipboard.
    private static let postPasteDelay: TimeInterval = 0.50

    func paste(_ text: String, preserveClipboard: Bool, switchInputMethod: Bool = true) {
        let pasteboard = NSPasteboard.general
        let originalString = preserveClipboard ? pasteboard.string(forType: .string) : nil

        let savedInputSource: TISInputSource? = switchInputMethod ? switchToASCIIIfCJK() : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.prePasteDelay) {
            self.sendPasteShortcut()

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.postPasteDelay) {
                if let savedInputSource {
                    TISSelectInputSource(savedInputSource)
                }

                guard preserveClipboard else { return }
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

    /// If the current input source is a CJK input method, switch to ASCII-capable source
    /// and return the original source so it can be restored later.
    private func switchToASCIIIfCJK() -> TISInputSource? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        guard isCJKInputSource(currentSource) else {
            return nil
        }

        guard let asciiSource = findASCIICapableSource() else {
            return nil
        }

        TISSelectInputSource(asciiSource)
        return currentSource
    }

    private func isCJKInputSource(_ source: TISInputSource) -> Bool {
        guard let langArrayRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return false
        }
        let languages = Unmanaged<CFArray>.fromOpaque(langArrayRef).takeUnretainedValue() as [AnyObject]

        let cjkPrefixes = ["zh", "ja", "ko"]
        for lang in languages {
            guard let langStr = lang as? String else { continue }
            for prefix in cjkPrefixes {
                if langStr.hasPrefix(prefix) {
                    return true
                }
            }
        }
        return false
    }

    private func findASCIICapableSource() -> TISInputSource? {
        let properties: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as String,
            kTISPropertyInputSourceIsASCIICapable: true,
            kTISPropertyInputSourceIsSelectCapable: true
        ]
        guard let sourceList = TISCreateInputSourceList(properties as CFDictionary, false)?.takeRetainedValue() else {
            return nil
        }

        let sources: [TISInputSource] = (sourceList as [AnyObject]).map { $0 as! TISInputSource }
        // Prefer "com.apple.keylayout.ABC" or "com.apple.keylayout.US"
        for inputSource in sources {
            if let idRef = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) {
                let sourceID = Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String
                if sourceID == "com.apple.keylayout.ABC" || sourceID == "com.apple.keylayout.US" {
                    return inputSource
                }
            }
        }

        // Fallback to any ASCII-capable keyboard layout
        return sources.first
    }
}
