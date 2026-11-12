import Foundation
import AppKit

final class NowPlayingManager {
    private let appState: AppState
    private var observers: [NSObjectProtocol] = []
    private var positionTimer: Timer?
    private var lastTrackKey: String = ""

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        let dnc = DistributedNotificationCenter.default()

        let spotifyObs = dnc.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNotification(notification, sourceApp: "Spotify")
        }

        let musicObs = dnc.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNotification(notification, sourceApp: "Music")
        }

        observers = [spotifyObs, musicObs]
        fetchInitialPlayback()

        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollPlaybackPosition()
        }
    }

    private func fetchInitialPlayback() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let scriptSource = """
            if application "Spotify" is running then
                tell application "Spotify"
                    if player state is playing then
                        return "Spotify||" & (name of current track) & "||" & (artist of current track) & "||" & (album of current track) & "||" & ((duration of current track) / 1000)
                    end if
                end tell
            end if
            if application "Music" is running then
                tell application "Music"
                    if player state is playing then
                        return "Music||" & (name of current track) & "||" & (artist of current track) & "||" & (album of current track) & "||" & (duration of current track)
                    end if
                end tell
            end if
            return ""
            """
            guard let script = NSAppleScript(source: scriptSource) else { return }
            var err: NSDictionary?
            let res = script.executeAndReturnError(&err).stringValue ?? ""
            let parts = res.components(separatedBy: "||")
            guard parts.count == 5 else { return }
            let sourceApp = parts[0]
            let title = parts[1]
            let artist = parts[2]
            let album = parts[3]
            let duration = Double(parts[4]) ?? 0
            DispatchQueue.main.async {
                guard let self else { return }
                self.appState.nowPlaying = NowPlayingInfo(
                    title: title,
                    artist: artist,
                    album: album,
                    sourceApp: sourceApp,
                    isPlaying: true,
                    duration: duration,
                    artworkURL: nil
                )
                self.lastTrackKey = "\(sourceApp)|\(title)|\(artist)"
                self.fetchSyncedLyrics(title: title, artist: artist, album: album)
                if sourceApp == "Spotify" {
                    self.fetchSpotifyArtwork()
                }
            }
        }
    }

    private func handleNotification(_ notification: Notification, sourceApp: String) {
        guard let info = notification.userInfo else { return }
        let stateStr = (info["Player State"] as? String) ?? ""

        if stateStr == "Stopped" {
            if appState.nowPlaying?.sourceApp == sourceApp {
                appState.nowPlaying = nil
                appState.artworkImage = nil
                appState.syncedLyrics = []
            }
            return
        }

        let title = (info["Name"] as? String) ?? "Unknown Track"
        let artist = (info["Artist"] as? String) ?? "Unknown Artist"
        let album = (info["Album"] as? String) ?? ""
        let isPlaying = (stateStr == "Playing")
        let rawDuration = (info["Duration"] as? Double) ?? 0
        let duration = sourceApp == "Spotify" && rawDuration > 1000 ? rawDuration / 1000.0 : rawDuration

        appState.nowPlaying = NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            sourceApp: sourceApp,
            isPlaying: isPlaying,
            duration: duration > 0 ? duration : (appState.nowPlaying?.duration ?? 0),
            artworkURL: nil
        )

        let trackKey = "\(sourceApp)|\(title)|\(artist)"
        if trackKey != lastTrackKey {
            lastTrackKey = trackKey
            appState.syncedLyrics = []
            appState.currentPlaybackTime = 0
            fetchSyncedLyrics(title: title, artist: artist, album: album)
            if sourceApp == "Spotify" {
                fetchSpotifyArtwork()
                fetchSpotifyDuration()
            }
        }
    }

    private func fetchSpotifyDuration() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let script = NSAppleScript(source: "tell application \"Spotify\" to (duration of current track) / 1000") else { return }
            var err: NSDictionary?
            let dur = script.executeAndReturnError(&err).doubleValue
            if dur > 0 {
                DispatchQueue.main.async {
                    self?.appState.nowPlaying?.duration = dur
                }
            }
        }
    }

    private func pollPlaybackPosition() {
        guard let track = appState.nowPlaying, track.isPlaying else { return }
        let app = track.sourceApp
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let script = NSAppleScript(source: "tell application \"\(app)\" to player position") else { return }
            var err: NSDictionary?
            let result = script.executeAndReturnError(&err)
            let seconds = result.doubleValue
            if seconds >= 0 {
                DispatchQueue.main.async {
                    self?.appState.currentPlaybackTime = seconds
                }
            }
        }
    }

    private func fetchSpotifyArtwork() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let script = NSAppleScript(source: "tell application \"Spotify\" to artwork url of current track") else { return }
            var err: NSDictionary?
            let result = script.executeAndReturnError(&err)
            guard let urlStr = result.stringValue, let url = URL(string: urlStr),
                  let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.appState.artworkImage = image
            }
        }
    }

    private func fetchSyncedLyrics(title: String, artist: String, album: String) {
        var comps = URLComponents(string: "https://lrclib.net/api/get")
        comps?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album)
        ]
        guard let url = comps?.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lrc = json["syncedLyrics"] as? String else { return }
            let parsed = Self.parseLRC(lrc)
            DispatchQueue.main.async {
                self?.appState.syncedLyrics = parsed
            }
        }.resume()
    }

    private static func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for rawLine in lrc.components(separatedBy: .newlines) {
            let ns = rawLine as NSString
            guard let match = regex.firstMatch(in: rawLine, range: NSRange(location: 0, length: ns.length)) else { continue }
            let min = Double(ns.substring(with: match.range(at: 1))) ?? 0
            let sec = Double(ns.substring(with: match.range(at: 2))) ?? 0
            let fracStr = ns.substring(with: match.range(at: 3))
            let frac = (Double(fracStr) ?? 0) / (fracStr.count == 3 ? 1000.0 : 100.0)
            let text = ns.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                lines.append(LyricLine(time: min * 60 + sec + frac, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    func seek(to seconds: Double) {
        guard let app = appState.nowPlaying?.sourceApp else { return }
        appState.currentPlaybackTime = seconds
        runAppleScript("tell application \"\(app)\" to set player position to \(seconds)")
    }

    func togglePlayPause() {
        guard let app = appState.nowPlaying?.sourceApp else { return }
        runAppleScript("tell application \"\(app)\" to playpause")
    }

    func nextTrack() {
        guard let app = appState.nowPlaying?.sourceApp else { return }
        runAppleScript("tell application \"\(app)\" to next track")
    }

    func previousTrack() {
        guard let app = appState.nowPlaying?.sourceApp else { return }
        runAppleScript("tell application \"\(app)\" to previous track")
    }

    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let script = NSAppleScript(source: source) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
            }
        }
    }

    deinit {
        positionTimer?.invalidate()
        let dnc = DistributedNotificationCenter.default()
        observers.forEach { dnc.removeObserver($0) }
    }
}
