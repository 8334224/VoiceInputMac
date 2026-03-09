import AppKit
import Combine
import SwiftUI

@MainActor
final class SpeechHUDController {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var cancellables: Set<AnyCancellable> = []

    init(appState: AppState) {
        Publishers.CombineLatest(appState.$speechHUDPhase.removeDuplicates(), appState.$transcriptPreview.removeDuplicates())
            .sink { [weak self] phase, transcript in
                self?.update(for: phase, transcript: transcript, appState: appState)
            }
            .store(in: &cancellables)
    }

    private func update(for phase: AppState.SpeechHUDPhase, transcript: String, appState: AppState) {
        switch phase {
        case .hidden:
            hide()
        case .recording, .transcribing:
            show(appState: appState, transcript: transcript)
        }
    }

    private func show(appState: AppState, transcript: String) {
        let panel = ensurePanel(appState: appState, transcript: transcript)
        position(panel: panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel(appState: AppState, transcript: String) -> NSPanel {
        let panelSize = preferredPanelSize(phase: appState.speechHUDPhase, transcript: transcript)

        if let panel {
            if let hostingController {
                hostingController.rootView = hudRootView(appState: appState)
            }
            panel.setContentSize(panelSize)
            return panel
        }

        let rootView = hudRootView(appState: appState)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.frame = NSRect(origin: .zero, size: panelSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow

        self.panel = panel
        self.hostingController = hostingController
        return panel
    }

    private func preferredPanelSize(phase: AppState.SpeechHUDPhase, transcript: String) -> NSSize {
        switch phase {
        case .recording:
            let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let count = max(cleanTranscript.count, 6)
            let width = min(560, max(260, 156 + CGFloat(count) * 14))
            return NSSize(width: width, height: 62)
        case .transcribing:
            return NSSize(width: 170, height: 58)
        case .hidden:
            return NSSize(width: 170, height: 58)
        }
    }

    private func hudRootView(appState: AppState) -> AnyView {
        AnyView(
            SpeechHUDView()
                .environmentObject(appState)
        )
    }

    private func position(panel: NSPanel) {
        guard let screen = activeScreen() else { return }
        let size = panel.frame.size
        let frame = screen.visibleFrame
        let x = frame.midX - size.width / 2
        let y = frame.minY + 48
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: false)
    }

    private func activeScreen() -> NSScreen? {
        let pointerLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(pointerLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
