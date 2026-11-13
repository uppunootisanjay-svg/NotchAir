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


struct StencilClockText: View {
    let style: LockClockStyle
    let weight: Double
    let isLiquid: Bool


    var body: some View {
        let base = Text(Date.now, format: .dateTime.hour().minute())
            .font(style.font(size: 92, weightValue: weight))


        let styled = Group {
            if isLiquid || style == .glassOutline {
                ZStack {
                    base.foregroundStyle(.white.opacity(style == .glassOutline ? 0.14 : 0.24))
                    base.foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.95), .white.opacity(0.32), .white.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: style == .glassOutline ? 0.6 : 0.25)
                }
                .shadow(color: .white.opacity(0.4), radius: 2, y: -1)
                .shadow(color: .black.opacity(0.38), radius: 14, y: 6)
            } else {
                base.foregroundStyle(.white.opacity(0.92))
            }
        }


        if style == .stencil {
            styled
                .overlay(
                    GeometryReader { geo in
                        ZStack {
                            Rectangle().frame(height: 3.5).offset(y: -geo.size.height * 0.16)
                            Rectangle().frame(height: 3.5).offset(y: geo.size.height * 0.16)
                            HStack(spacing: geo.size.width * 0.19) {
                                ForEach(0..<4, id: \.self) { _ in Rectangle().frame(width: 3.2) }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blendMode(.destinationOut)
                    }
                )
                .compositingGroup()
        } else {
            styled
        }
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
                    StencilClockText(style: state.lockClockStyle, weight: state.clockWeight, isLiquid: state.liquidGlassClockEnabled)
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
                        .liquidGlass(cornerRadius: 28)


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
                                        VStack(alignment: state.lyricsCentered ? .center : .leading, spacing: 14) {
                                            ForEach(Array(state.syncedLyrics.enumerated()), id: \.element.id) { idx, line in
                                                let isActive = idx == activeLineIndex
                                                Text(line.text)
                                                    .font(.system(
                                                        size: isActive ? 26 : 20,
                                                        weight: isActive ? .bold : .medium,
                                                        design: state.lyricsDisplayStyle == .minimal ? .monospaced : .default
                                                    ))
                                                    .multilineTextAlignment(state.lyricsCentered ? .center : .leading)
                                                    .foregroundStyle(isActive ? .white : .white.opacity(idx < activeLineIndex ? 0.35 : 0.55))
                                                    .blur(radius: (state.lyricsDisplayStyle == .blur && !isActive) ? 1.8 : 0)
                                                    .shadow(color: (state.lyricsDisplayStyle == .glow && isActive) ? .white.opacity(0.65) : .clear, radius: 10)
                                                    .id(line.id)
                                                    .animation(.easeInOut(duration: 0.25), value: activeLineIndex)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: state.lyricsCentered ? .center : .leading)
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
                    .padding(.horizontal, 14).padding(.vertical, 6).liquidGlass(cornerRadius: 16).buttonStyle(.plain).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}
