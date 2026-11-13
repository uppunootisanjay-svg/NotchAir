import Foundation
import SwiftUI
import Combine

enum NotchMode: Equatable {
    case idle
    case expandedShelf
    case incomingRequest(deviceName: String, fileName: String, fileSize: String)
    case transferring(fileName: String, progress: Double, speedMBps: Double)
}

enum NotchAccent: String, CaseIterable, Identifiable {
    case blue, purple, green, orange, pink
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        }
    }
}

enum NotchVisualStyle: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case glow = "Glow"
    case minimal = "Minimal"
    var id: String { rawValue }
}

enum PortalEffect: String, CaseIterable, Identifiable {
    case rainbow = "Rainbow"
    case portal = "Portal"
    case flashDrive = "Flash Drive"
    case volcano = "Volcano"
    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .rainbow: return "A blaze of light"
        case .portal: return "Through the cosmos"
        case .flashDrive: return "It's giving 2005"
        case .volcano: return "Into the fire"
        }
    }

    var colors: [Color] {
        switch self {
        case .rainbow: return [.red, .orange, .yellow, .green, .blue, .purple]
        case .portal: return [.purple, .blue, .cyan, .indigo]
        case .flashDrive: return [.green, .mint, .teal]
        case .volcano: return [.red, .orange, .yellow]
        }
    }
}

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var sourceApp: String
    var isPlaying: Bool
    var duration: Double = 0
    var artworkURL: URL?
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let text: String
}

struct TransferItem: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let deviceName: String
    let direction: String
    let date: Date
    let localURL: URL?
}

struct ShelfFile: Identifiable {
    let id = UUID()
    let url: URL
    var fileName: String { url.lastPathComponent }
}

struct PortalPushPayload: Codable, Equatable {
    let id: String
    let fileName: String
}

final class AppState: ObservableObject {
    @Published var notchMode: NotchMode = .idle
    @Published var shelfFiles: [ShelfFile] = []
    @Published var recentTransfers: [TransferItem] = []
    @Published var clipboardSyncEnabled: Bool = true
    @Published var serverURL: String = "http://localhost:8765"
    @Published var isHovering: Bool = false
    @Published var isDropTargeted: Bool = false
    @Published var showQR: Bool = false
    @Published var showCustomize: Bool = false

    // Notch Appearance (clean monochrome by default)
    @Published var accent: NotchAccent = .blue
    @Published var visualStyle: NotchVisualStyle = .classic
    @Published var expandedCornerRadius: Double = 22

    // Portal Send Zone (Right Edge) + Auto-Push
    @Published var portalEnabled: Bool = true
    @Published var portalEffect: PortalEffect = .rainbow
    @Published var portalActive: Bool = false
    @Published var portalSpin: Bool = false
    @Published var selectedSettingsTab: String = "Portal"
    @Published var latestPortalPush: PortalPushPayload?
    @Published var portalSentFileName: String?

    // Now Playing + Live Synced Lyrics (Spotify & Apple Music)
    @Published var nowPlaying: NowPlayingInfo?
    @Published var artworkImage: NSImage?
    @Published var syncedLyrics: [LyricLine] = []
    @Published var currentPlaybackTime: Double = 0
    @Published var showLockLyrics: Bool = false

    var pendingDecision: ((Bool) -> Void)?

    func respondToIncoming(accepted: Bool) {
        pendingDecision?(accepted)
        pendingDecision = nil
        if !accepted {
            notchMode = .idle
        }
    }

    func pushFileFromPortal(url: URL) {
        if !shelfFiles.contains(where: { $0.url == url }) {
            shelfFiles.append(ShelfFile(url: url))
        }
        latestPortalPush = PortalPushPayload(id: UUID().uuidString, fileName: url.lastPathComponent)
        notchMode = .expandedShelf
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.portalSentFileName == url.lastPathComponent {
                self?.portalSentFileName = nil
            }
        }
    }
}
