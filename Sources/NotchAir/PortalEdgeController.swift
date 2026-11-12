import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class PortalEdgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PortalEdgeController {
    private var panel: PortalEdgePanel?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        setupPanel()
    }

    private func setupPanel() {
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 150
        let height: CGFloat = 340
        let originX = screen.frame.maxX - width
        let originY = screen.frame.midY - (height / 2)

        let panel = PortalEdgePanel(
            contentRect: NSRect(x: originX, y: originY, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        let hosting = NSHostingView(rootView: PortalEdgeView(state: appState))
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

struct PortalEdgeView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .trailing) {
            if state.portalEnabled {
                if state.portalActive {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                AngularGradient(
                                    colors: state.portalEffect.colors + [state.portalEffect.colors.first ?? .blue],
                                    center: .center
                                ),
                                lineWidth: 12
                            )
                            .frame(width: 190, height: 190)
                            .blur(radius: 4)
                            .rotationEffect(.degrees(state.portalSpin ? 360 : 0))
                            .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: state.portalSpin)
                            .offset(x: 95)

                        VStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                            Text("Drop to Send")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 10)
                    }
                    .onAppear { state.portalSpin = true }
                    .onDisappear { state.portalSpin = false }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 5, height: 84)
                        .padding(.trailing, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $state.portalActive) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        state.pushFileFromPortal(url: url)
                    }
                }
            }
            return true
        }
    }
}
