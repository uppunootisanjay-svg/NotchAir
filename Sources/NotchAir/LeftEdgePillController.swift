import AppKit
import SwiftUI

final class LeftEdgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class EdgeSliderModel: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var isVolumeMode: Bool = false
    @Published var level: Double = 0.65
    @Published var isHovering: Bool = false
}

final class LeftEdgePillController {
    private var panel: LeftEdgePanel?
    private let appState: AppState
    private let model = EdgeSliderModel()
    private let onDoubleTap: () -> Void
    private var hideTimer: Timer?
    private var eventMonitor: Any?

    init(appState: AppState, onTapPill: @escaping () -> Void) {
        self.appState = appState
        self.onDoubleTap = onTapPill
        setupPanel()
        startMediaKeyMonitor()
    }

    private func setupPanel() {
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 56
        let height: CGFloat = 180
        let originX = screen.frame.minX
        let originY = screen.frame.midY - (height / 2)

        let panel = LeftEdgePanel(
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

        let hosting = NSHostingView(rootView: LeftEdgePillView(model: model, onDoubleTap: onDoubleTap, onInteract: { [weak self] in
            self?.scheduleHide()
        }))
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func startMediaKeyMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let data1 = event.data1
            let keyCode = (data1 & 0xFFFF0000) >> 16
            let keyFlags = data1 & 0x0000FFFF
            let keyState = (keyFlags & 0xFF00) >> 8
            guard keyState == 0x0A else { return } // Key down

            DispatchQueue.main.async {
                guard let self else { return }
                switch keyCode {
                case 2: // Brightness Up
                    self.model.isVolumeMode = false
                    self.model.level = min(1.0, self.model.level + 0.0625)
                    self.revealTemporarily()
                case 3: // Brightness Down
                    self.model.isVolumeMode = false
                    self.model.level = max(0.0, self.model.level - 0.0625)
                    self.revealTemporarily()
                case 0: // Volume Up
                    self.model.isVolumeMode = true
                    self.model.level = min(1.0, self.model.level + 0.0625)
                    self.revealTemporarily()
                case 1: // Volume Down
                    self.model.isVolumeMode = true
                    self.model.level = max(0.0, self.model.level - 0.0625)
                    self.revealTemporarily()
                case 7: // Mute
                    self.model.isVolumeMode = true
                    self.revealTemporarily()
                default:
                    break
                }
            }
        }
    }

    func revealTemporarily() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            model.isVisible = true
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.model.isHovering else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                    self.model.isVisible = false
                }
            }
        }
    }

    deinit {
        hideTimer?.invalidate()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }
}

struct LeftEdgePillView: View {
    @ObservedObject var model: EdgeSliderModel
    let onDoubleTap: () -> Void
    let onInteract: () -> Void

    var body: some View {
        HStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.55))

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                        .frame(height: max(28, geo.size.height * model.level))
                        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: model.level)

                    Image(systemName: model.isVolumeMode ? "speaker.wave.2.fill" : "sun.max.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                        .padding(.bottom, 8)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let pct = 1.0 - (value.location.y / geo.size.height)
                            let clamped = min(1.0, max(0.0, pct))
                            let delta = clamped - model.level
                            model.level = clamped
                            onInteract()
                            applyAdjustment(level: clamped, delta: delta)
                        }
                )
            }
            .frame(width: model.isHovering ? 24 : 18, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.32), radius: 8, x: 2)
            .offset(x: model.isVisible ? 6 : -36)
            .opacity(model.isVisible ? 1 : 0)
            .onHover { hovering in
                model.isHovering = hovering
                if hovering {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.isVisible = true
                    }
                } else {
                    onInteract()
                }
            }
            .onTapGesture(count: 2) { onDoubleTap() }
            .onTapGesture(count: 1) {
                model.isVolumeMode.toggle()
                onInteract()
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: model.isVisible)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: model.isHovering)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func applyAdjustment(level: Double, delta: Double) {
        let isVol = model.isVolumeMode
        DispatchQueue.global(qos: .userInitiated).async {
            if isVol {
                let vol = Int(level * 100)
                runScript("set volume output volume \(vol)")
            } else if abs(delta) > 0.03 {
                let keyCode = delta > 0 ? 144 : 145
                runScript("tell application \"System Events\" to key code \(keyCode)")
            }
        }
    }

    private func runScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var err: NSDictionary?
            script.executeAndReturnError(&err)
        }
    }
}
