import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class NotchPanelController {
    private var panel: NotchPanel?
    private let appState: AppState
    private let nowPlayingManager: NowPlayingManager

    init(appState: AppState, nowPlayingManager: NowPlayingManager) {
        self.appState = appState
        self.nowPlayingManager = nowPlayingManager
        setupPanel()
    }

    private func setupPanel() {
        guard let screen = NSScreen.main else { return }

        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 250
        let originX = screen.frame.midX - (panelWidth / 2)
        let originY = screen.frame.maxY - panelHeight

        let panel = NotchPanel(
            contentRect: NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false

        let root = NotchView(
            state: appState,
            onPlayPause: { [weak nowPlayingManager] in nowPlayingManager?.togglePlayPause() },
            onNext: { [weak nowPlayingManager] in nowPlayingManager?.nextTrack() },
            onPrevious: { [weak nowPlayingManager] in nowPlayingManager?.previousTrack() },
            onSeek: { [weak nowPlayingManager] seconds in nowPlayingManager?.seek(to: seconds) }
        )

        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
    }
}
