import AppKit
import SwiftUI
import Combine


final class PortalReceivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}


final class PortalReceiveOverlayController {
    private var panel: PortalReceivePanel?
    private let appState: AppState
    private var cancellable: AnyCancellable?
    private var hideWorkItem: DispatchWorkItem?
    @Published var animStartDate: Date = Date()


    init(appState: AppState) {
        self.appState = appState
        setupPanel()
        observeReceives()
    }


    private func setupPanel() {
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 680
        let height: CGFloat = 540
        let originX = screen.frame.maxX - width
        let originY = screen.frame.midY - (height / 2)


        let p = PortalReceivePanel(
            contentRect: NSRect(x: originX, y: originY, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true


        let hosting = NSHostingView(rootView: Portal3DReceiveView(state: appState, controller: self))
        hosting.frame = p.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        self.panel = p
    }


    private func observeReceives() {
        cancellable = appState.$portalSentFileName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                guard let self else { return }
                self.hideWorkItem?.cancel()
                if name != nil {
                    self.animStartDate = Date()
                    self.panel?.orderFrontRegardless()
                    let item = DispatchWorkItem { [weak self] in
                        self?.panel?.orderOut(nil)
                    }
                    self.hideWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
                } else {
                    self.panel?.orderOut(nil)
                }
            }
    }
}


struct Portal3DReceiveView: View {
    @ObservedObject var state: AppState
    let controller: PortalReceiveOverlayController


    var body: some View {
        ZStack(alignment: .trailing) {
            if let fileName = state.portalSentFileName {
                TimelineView(.animation(minimumInterval: 0.016)) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(controller.animStartDate))
                    let portalOpen = min(1.0, elapsed / 0.45)
                    let rocketProgress = max(0.0, min(1.0, (elapsed - 0.55) / 1.35))
                    let fadeOut = elapsed > 2.4 ? max(0.0, 1.0 - (elapsed - 2.4) / 0.55) : 1.0
                    let colors = state.portalEffect.colors + [state.portalEffect.colors.first ?? .purple]


                    ZStack(alignment: .trailing) {
                        // Soft Rainbow Edge Glow (00:02 style)
                        LinearGradient(
                            colors: [.clear, Color.orange.opacity(0.28), Color.purple.opacity(0.35), Color.blue.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 240, height: 480)
                        .blur(radius: 40)
                        .opacity(portalOpen * fadeOut)


                        // Concentric Right-Edge Portal Rings (00:13-00:15 style)
                        ZStack {
                            ForEach(0..<5, id: \.self) { idx in
                                let size = CGFloat(440 - idx * 62)
                                Circle()
                                    .strokeBorder(
                                        AngularGradient(colors: idx % 2 == 0 ? colors : colors.reversed(), center: .center),
                                        lineWidth: CGFloat(14 - idx * 2)
                                    )
                                    .frame(width: size, height: size)
                                    .blur(radius: idx == 0 ? 10 : 2)
                                    .rotationEffect(.degrees(elapsed * Double(idx % 2 == 0 ? 95 : -130)))
                            }


                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [.yellow.opacity(0.85), .orange.opacity(0.6), .purple.opacity(0.35), .clear],
                                        center: .center,
                                        startRadius: 4,
                                        endRadius: 95
                                    )
                                )
                                .frame(width: 190, height: 190)
                        }
                        .scaleEffect(0.25 + 0.75 * portalOpen)
                        .offset(x: 215)
                        .opacity(fadeOut)


                        // Rocket + File Card blasting out of the Portal (00:15-00:16 style)
                        HStack(spacing: 10) {
                            Image(systemName: "flame.fill")
                                .font(.title2)
                                .foregroundStyle(
                                    LinearGradient(colors: [.yellow, .orange, .red], startPoint: .leading, endPoint: .trailing)
                                )
                                .scaleEffect(x: 1.4 + 0.3 * sin(elapsed * 28), y: 0.95)
                                .rotationEffect(.degrees(-90))


                            HStack(spacing: 8) {
                                Image(systemName: "doc.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Received")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.75))
                                    Text(fileName)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.35), lineWidth: 1))


                            Image(systemName: "paperplane.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(-135))
                        }
                        .offset(
                            x: -40 - CGFloat(rocketProgress) * 460,
                            y: -CGFloat(sin(rocketProgress * .pi)) * 38
                        )
                        .scaleEffect(0.6 + 0.4 * min(1.0, rocketProgress * 2.5))
                        .opacity(elapsed > 0.5 ? fadeOut : 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}
