import AppKit
import Combine
import SwiftUI

@MainActor
final class SpeechHUDController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var cancellables: Set<AnyCancellable> = []
    private var currentPhase: AppState.SpeechHUDPhase = .hidden

    init(appState: AppState) {
        appState.$speechHUDPhase
            .removeDuplicates()
            .sink { [weak self] phase in
                self?.handlePhaseChange(phase, appState: appState)
            }
            .store(in: &cancellables)

        appState.$transcriptPreview
            .removeDuplicates()
            .sink { [weak self] transcript in
                guard let self, self.currentPhase == .recording else { return }
                self.updatePanelSize(transcript: transcript, animated: true)
                self.repositionPanel(animated: true)
            }
            .store(in: &cancellables)

        appState.$audioLevel
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.currentPhase == .recording else { return }
                if let hostingController = self.hostingController {
                    hostingController.rootView = self.hudRootView(appState: appState)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Phase transitions

    private func handlePhaseChange(_ phase: AppState.SpeechHUDPhase, appState: AppState) {
        let previousPhase = currentPhase
        currentPhase = phase

        switch phase {
        case .hidden:
            dismissWithAnimation()
        case .recording, .transcribing:
            if previousPhase == .hidden {
                showWithEntrance(appState: appState)
            } else {
                updateContent(appState: appState)
            }
        }
    }

    private func showWithEntrance(appState: AppState) {
        let panel = ensurePanel(appState: appState)
        let transcript = appState.transcriptPreview
        let size = preferredPanelSize(phase: currentPhase, transcript: transcript)

        panel.setContentSize(size)
        repositionPanel(animated: false)

        panel.alphaValue = 0
        panel.setIsVisible(true)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
            panel.animator().alphaValue = 1
        }
    }

    private func dismissWithAnimation() {
        guard let panel else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.tearDown()
            }
        })
    }

    private func updateContent(appState: AppState) {
        guard let panel else {
            showWithEntrance(appState: appState)
            return
        }
        if let hostingController {
            hostingController.rootView = hudRootView(appState: appState)
        }
        let transcript = appState.transcriptPreview
        updatePanelSize(transcript: transcript, animated: true)
        repositionPanel(animated: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func tearDown() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel?.close()
        panel = nil
        hostingController = nil
    }

    // MARK: - Panel

    private func ensurePanel(appState: AppState) -> NSPanel {
        if let panel {
            if let hostingController {
                hostingController.rootView = hudRootView(appState: appState)
            }
            return panel
        }

        let rootView = hudRootView(appState: appState)
        let hosting = NSHostingController(rootView: rootView)
        hosting.view.frame = NSRect(origin: .zero, size: NSSize(width: 240, height: 72))

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 240, height: 72)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.animationBehavior = .none

        self.panel = panel
        self.hostingController = hosting
        return panel
    }

    // MARK: - Sizing

    /// Font matching the HUD transcript text in SpeechHUDView.
    private static let transcriptFont = NSFont.systemFont(ofSize: 15, weight: .medium)

    private func preferredPanelSize(phase: AppState.SpeechHUDPhase, transcript: String) -> NSSize {
        let padding: CGFloat = 16
        switch phase {
        case .recording:
            let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let measureText = cleanTranscript.isEmpty ? "语音输入" : cleanTranscript
            let measuredWidth = (measureText as NSString).size(
                withAttributes: [.font: Self.transcriptFont]
            ).width
            let textWidth = min(CGFloat(560), max(CGFloat(160), ceil(measuredWidth) + 8))
            let totalWidth = 44 + 14 + 1 + 14 + textWidth + 16 + 20
            return NSSize(width: totalWidth + padding * 2, height: 56 + padding * 2)
        case .transcribing:
            return NSSize(width: 180 + padding * 2, height: 44 + padding * 2)
        case .hidden:
            return NSSize(width: 180 + padding * 2, height: 44 + padding * 2)
        }
    }

    private func updatePanelSize(transcript: String, animated: Bool) {
        guard let panel else { return }
        let newSize = preferredPanelSize(phase: currentPhase, transcript: transcript)
        let currentSize = panel.frame.size
        guard abs(newSize.width - currentSize.width) > 2 || abs(newSize.height - currentSize.height) > 2 else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.5, 1.0)
                panel.animator().setContentSize(newSize)
            }
        } else {
            panel.setContentSize(newSize)
        }
    }

    // MARK: - Positioning (bottom-center)

    /// Offset from the bottom of the visible screen area (above the Dock).
    private static let bottomOffset: CGFloat = 64

    private func repositionPanel(animated: Bool) {
        guard let panel, let screen = activeScreen() else { return }
        let size = preferredPanelSize(phase: currentPhase, transcript: "")
        let actualWidth = panel.frame.width > 10 ? panel.frame.width : size.width
        let actualHeight = panel.frame.height > 10 ? panel.frame.height : size.height
        // visibleFrame already excludes the menu bar (and notch area) and Dock.
        let frame = screen.visibleFrame
        let x = frame.midX - actualWidth / 2
        let y = frame.minY + Self.bottomOffset
        let origin = NSPoint(x: x, y: y)
        let targetFrame = NSRect(origin: origin, size: NSSize(width: actualWidth, height: actualHeight))

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.5, 1.0)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func activeScreen() -> NSScreen? {
        let pointerLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(pointerLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func hudRootView(appState: AppState) -> AnyView {
        AnyView(
            SpeechHUDView()
                .environmentObject(appState)
        )
    }
}
