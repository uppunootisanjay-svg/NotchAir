import AppKit
import SwiftUI

final class AmbientLockOverlayController {
    private var window: NSWindow?
    private let appState: AppState
    private let nowPlayingManager: NowPlayingManager

    init(appState: AppState, nowPlayingManager: NowPlayingManager) {
        self.appState = appState
        self.nowPlayingManager = nowPlayingManager
    }

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
            return
        }
        show()
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        if window == nil {
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.level = .screenSaver
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.backgroundColor = .black
            let view = AmbientLockView(
                state: appState,
                onPlayPause: { [weak nowPlayingManager] in nowPlayingManager?.togglePlayPause() },
                onNext: { [weak nowPlayingManager] in nowPlayingManager?.nextTrack() },
                onPrevious: { [weak nowPlayingManager] in nowPlayingManager?.previousTrack() },
                onClose: { [weak win] in win?.orderOut(nil) }
            )
            win.contentView = NSHostingView(rootView: view)
            self.window = win
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AmbientLockView: View {
    @ObservedObject var state: AppState
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void

    private var activeLineIndex: Int {
        guard !state.syncedLyrics.isEmpty else { return -1 }
        var active = 0
        for (idx, line) in state.syncedLyrics.enumerated() {
            if line.time <= state.currentPlaybackTime {
                active = idx
            } else {
                break
            }
        }
        return active
    }

    var body: some View {
        ZStack {
            if let art = state.artworkImage {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 75)
                    .overlay(Color.black.opacity(0.45))
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.1, blue: 0.16), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 28) {
                VStack(spacing: 2) {
                    Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(Date.now, format: .dateTime.hour().minute())
                        .font(.system(size: 84, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }

                if let track = state.nowPlaying {
                    HStack(alignment: .center, spacing: 48) {
                        VStack(spacing: 16) {
                            Group {
                                if let art = state.artworkImage {
                                    Image(nsImage: art)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 240, height: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                        .shadow(radius: 20)
                                } else {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 240, height: 240)
                                        .overlay(
                                            Image(systemName: "music.note")
                                                .font(.system(size: 64))
                                                .foregroundStyle(.white.opacity(0.85))
                                        )
                                }
                            }
                            .onTapGesture(count: 2) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    state.showLockLyrics.toggle()
                                }
                            }

                            VStack(spacing: 4) {
                                Text(track.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.white)
                                Text("\(track.artist) • \(track.sourceApp)")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.7))
                            }

                            HStack(spacing: 28) {
                                Button(action: onPrevious) {
                                    Image(systemName: "backward.fill").font(.title2)
                                }.buttonStyle(.plain).foregroundStyle(.white)

                                Button(action: onPlayPause) {
                                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.largeTitle)
                                }.buttonStyle(.plain).foregroundStyle(.white)

                                Button(action: onNext) {
                                    Image(systemName: "forward.fill").font(.title2)
                                }.buttonStyle(.plain).foregroundStyle(.white)

                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        state.showLockLyrics.toggle()
                                    }
                                } label: {
                                    Image(systemName: state.showLockLyrics ? "quote.bubble.fill" : "quote.bubble")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(state.showLockLyrics ? .white : .white.opacity(0.55))
                            }
                        }
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                        if state.showLockLyrics {
                            if state.syncedLyrics.isEmpty {
                                Text("No synced lyrics found for this track")
                                    .font(.title3)
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 380, height: 340)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                            } else {
                                ScrollViewReader { proxy in
                                    ScrollView(showsIndicators: false) {
                                        VStack(alignment: .leading, spacing: 14) {
                                            ForEach(Array(state.syncedLyrics.enumerated()), id: \.element.id) { idx, line in
                                                Text(line.text)
                                                    .font(.system(size: idx == activeLineIndex ? 26 : 20, weight: idx == activeLineIndex ? .bold : .medium))
                                                    .foregroundStyle(idx == activeLineIndex ? .white : .white.opacity(idx < activeLineIndex ? 0.35 : 0.55))
                                                    .id(line.id)
                                                    .animation(.easeInOut(duration: 0.25), value: activeLineIndex)
                                            }
                                        }
                                        .padding(.vertical, 60)
                                    }
                                    .frame(width: 420, height: 340)
                                    .onChange(of: activeLineIndex) { _, newIdx in
                                        if newIdx >= 0, newIdx < state.syncedLyrics.count {
                                            withAnimation(.easeInOut(duration: 0.35)) {
                                                proxy.scrollTo(state.syncedLyrics[newIdx].id, anchor: .center)
                                            }
                                        }
                                    }
                                }
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                            }
                        }
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: state.showLockLyrics)
                } else {
                    Text("Play a song in Spotify or Apple Music")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Button("Dismiss") { onClose() }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.4))
            }
        }
    }
}
