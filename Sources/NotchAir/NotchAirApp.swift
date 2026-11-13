import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let peerDiscovery = PeerDiscoveryManager()
    var notchController: NotchPanelController?
    var portalController: PortalEdgeController?
    var portalReceiveController: PortalReceiveOverlayController?
    var downloadsWatcher: DownloadsWatcher?
    var ambientController: AmbientLockOverlayController?
    var transferServer: LocalTransferServer?
    var nowPlayingManager: NowPlayingManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let player = NowPlayingManager(appState: appState)
        player.start()
        nowPlayingManager = player
        peerDiscovery.start()

        notchController = NotchPanelController(appState: appState, nowPlayingManager: player, peerDiscovery: peerDiscovery)
        portalController = PortalEdgeController(appState: appState)
        portalReceiveController = PortalReceiveOverlayController(appState: appState)
        let watcher = DownloadsWatcher()
        watcher.start(appState: appState)
        downloadsWatcher = watcher
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
            Button("Quit NotchAir") {
                NSApplication.shared.terminate(nil)
            }
        }
        Window("NotchAir Settings", id: "settings") {
            SettingsView(state: delegate.appState)
        }
    }
}
