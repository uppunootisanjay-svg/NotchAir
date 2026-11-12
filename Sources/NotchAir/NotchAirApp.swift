import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    var notchController: NotchPanelController?
    var portalController: PortalEdgeController?
    var ambientController: AmbientLockOverlayController?
    var transferServer: LocalTransferServer?
    var nowPlayingManager: NowPlayingManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let player = NowPlayingManager(appState: appState)
        player.start()
        nowPlayingManager = player

        notchController = NotchPanelController(appState: appState, nowPlayingManager: player)
        portalController = PortalEdgeController(appState: appState)
        ambientController = AmbientLockOverlayController(appState: appState, nowPlayingManager: player)
        transferServer = LocalTransferServer(appState: appState)
        transferServer?.start()
    }
}

@main
struct NotchAirApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("NotchAir", systemImage: "dot.radiowaves.left.and.right") {
            Text("Server: \(delegate.appState.serverURL)")
            Divider()
            Button("Toggle Notch Shelf") {
                delegate.appState.notchMode = delegate.appState.notchMode == .idle ? .expandedShelf : .idle
            }
            Button("Show Ambient Lock Player") {
                delegate.ambientController?.toggle()
            }
            Button("Customize & Portal Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            Divider()
            Button("Simulate Incoming File") {
                delegate.appState.notchMode = .incomingRequest(
                    deviceName: "Pixel 9",
                    fileName: "Invoice_2026.pdf",
                    fileSize: "2.4 MB"
                )
            }
            Divider()
            Button("Quit NotchAir") {
                NSApplication.shared.terminate(nil)
            }
        }

        Window("NotchAir Settings", id: "settings") {
            SettingsView(state: delegate.appState)
        }
    }
}
