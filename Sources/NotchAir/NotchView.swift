import SwiftUI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

struct EqualizerBarsView: View {
    let isPlaying: Bool
    private let phases: [Double] = [0.0, 1.3, 2.5, 0.7, 1.9]
    private let speeds: [Double] = [5.2, 6.8, 4.5, 7.1, 5.9]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5, id: \.self) { idx in
                    let wave = (sin(t * speeds[idx] + phases[idx]) + 1.0) / 2.0
                    let barHeight = isPlaying ? (4.0 + wave * 11.0) : 3.0
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(isPlaying ? 0.9 : 0.45))
                        .frame(width: 2.2, height: barHeight)
                        .animation(.easeInOut(duration: 0.14), value: barHeight)
                }
            }
            .frame(height: 16)
        }
    }
}

struct MarqueeTextView: View {
    let text: String
    let font: Font
    let color: Color
    let maxWidth: CGFloat

    var body: some View {
        let charEstimate = CGFloat(text.count) * 6.8
        if charEstimate <= maxWidth {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
        } else {
            TimelineView(.animation(minimumInterval: 0.03)) { timeline in
                let cycle: Double = 7.5
                let elapsed = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                let pause: Double = 1.5
                let travel = max(0, charEstimate - maxWidth + 16)
                let progress = elapsed < pause ? 0.0 : min(1.0, (elapsed - pause) / (cycle - pause * 1.5))
                let offset = -CGFloat(progress) * travel

                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
            }
            .frame(width: maxWidth, alignment: .leading)
            .clipped()
        }
    }
}

struct AirDropBeamView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.03)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let w1 = t.truncatingRemainder(dividingBy: 1.4) / 1.4
            let w2 = (t + 0.7).truncatingRemainder(dividingBy: 1.4) / 1.4
            let glide = sin(t * 4.0) * 3.0
            ZStack {
                Circle().stroke(Color.white.opacity(0.6 * (1 - w1)), lineWidth: 1.2).frame(width: 22, height: 22).scaleEffect(1 + w1 * 1.1)
                Circle().stroke(Color.white.opacity(0.6 * (1 - w2)), lineWidth: 1.2).frame(width: 22, height: 22).scaleEffect(1 + w2 * 1.1)
                Image(systemName: "paperplane.fill").font(.caption).foregroundStyle(.white).offset(x: glide, y: -glide * 0.5)
            }
            .frame(width: 40, height: 40)
        }
    }
}

struct NotchView: View {
    @ObservedObject var state: AppState
    @ObservedObject var peerDiscovery: PeerDiscoveryManager
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onSeek: (Double) -> Void

    @Namespace private var notchSpace
    private let context = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()

    var body: some View {
        VStack(spacing: 0) {
            notchContainer
                .onHover { hovering in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        state.isHovering = hovering
                        if hovering && state.notchMode == .idle {
                            state.notchMode = .expandedShelf
                        } else if !hovering && state.notchMode == .expandedShelf && !state.showQR && !state.showCustomize && state.portalSentFileName == nil {
                            state.notchMode = .idle
                        }
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $state.isDropTargeted) { providers in
                    handleDrop(providers: providers)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var notchContainer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(state.isDropTargeted ? 0.45 : 0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)

            contentView
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .animation(.spring(response: 0.35, dampingFraction: 0.76), value: state.notchMode)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.showQR)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.showCustomize)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.nowPlaying)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.portalSentFileName)
    }

    @ViewBuilder
    private var contentView: some View {
        if let sentName = state.portalSentFileName {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ready for Android")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(sentName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.top, 14)
        } else {
            switch state.notchMode {
            case .idle:
                if let track = state.nowPlaying {
                    HStack(spacing: 8) {
                        if let art = state.artworkImage {
                            Image(nsImage: art)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .matchedGeometryEffect(id: "albumArt", in: notchSpace)
                        } else {
                            Image(systemName: "music.note")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .matchedGeometryEffect(id: "albumArt", in: notchSpace)
                        }
                        MarqueeTextView(
                            text: "\(track.title) — \(track.artist)",
                            font: .caption2.weight(.semibold),
                            color: .white,
                            maxWidth: 220
                        )
                        .matchedGeometryEffect(id: "trackTitle", in: notchSpace)
                        Spacer(minLength: 4)
                        EqualizerBarsView(isPlaying: track.isPlaying)
                            .matchedGeometryEffect(id: "eqBars", in: notchSpace)
                    }
                    .padding(.horizontal, 2)
                } else {
                    EmptyView()
                }

            case .incomingRequest(let device, let file, let size):
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Incoming from \(device)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(file) (\(size))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Decline") { state.respondToIncoming(accepted: false) }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    Button("Accept") { state.respondToIncoming(accepted: true) }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.25))
                }

            case .transferring(let file, let progress, let speed):
                HStack(spacing: 14) {
                    AirDropBeamView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(speed > 0 ? String(format: "%.1f MB/s • %d%%", speed, Int(progress * 100)) : "\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

            case .expandedShelf:
                if let track = state.nowPlaying, !state.isDropTargeted, !state.showQR, !state.showCustomize {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            ZStack {
                                if let art = state.artworkImage {
                                    Image(nsImage: art)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 54, height: 54)
                                        .blur(radius: 14)
                                        .opacity(0.45)
                                    Image(nsImage: art)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .matchedGeometryEffect(id: "albumArt", in: notchSpace)
                                } else {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 48, height: 48)
                                        .overlay(
                                            Image(systemName: "music.note")
                                                .foregroundStyle(.white.opacity(0.8))
                                        )
                                        .matchedGeometryEffect(id: "albumArt", in: notchSpace)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                MarqueeTextView(
                                    text: track.title,
                                    font: .subheadline.weight(.semibold),
                                    color: .white,
                                    maxWidth: 195
                                )
                                .matchedGeometryEffect(id: "trackTitle", in: notchSpace)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.65))
                                    .lineLimit(1)
                            }
                            Spacer()
                            EqualizerBarsView(isPlaying: track.isPlaying)
                                .matchedGeometryEffect(id: "eqBars", in: notchSpace)
                        }

                        if track.duration > 0 {
                            HStack(spacing: 8) {
                                Text(formatTime(state.currentPlaybackTime))
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.55))
                                Slider(
                                    value: Binding(
                                        get: { min(state.currentPlaybackTime, track.duration) },
                                        set: { onSeek($0) }
                                    ),
                                    in: 0...track.duration
                                )
                                .controlSize(.mini)
                                .tint(.white)
                                Text(formatTime(track.duration))
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }

                        HStack(spacing: 28) {
                            Button(action: onPrevious) {
                                Image(systemName: "backward.fill").font(.subheadline)
                            }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.85))

                            Button(action: onPlayPause) {
                                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                            }.buttonStyle(.plain).foregroundStyle(.white)

                            Button(action: onNext) {
                                Image(systemName: "forward.fill").font(.subheadline)
                            }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.top, 20)
                } else {
                    VStack(spacing: 10) {
                        HStack {
                            Label("NotchAir", systemImage: "dot.radiowaves.left.and.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Button {
                                state.showCustomize.toggle()
                                if state.showCustomize { state.showQR = false }
                            } label: {
                                Image(systemName: state.showCustomize ? "slider.horizontal.3" : "paintbrush.fill")
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .buttonStyle(.plain)

                            Button {
                                state.showQR.toggle()
                                if state.showQR { state.showCustomize = false }
                            } label: {
                                Image(systemName: state.showQR ? "xmark.circle.fill" : "qrcode")
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }

                        if state.showCustomize {
                            customizePanel
                        } else if state.showQR, let qrImage = generateQRCode(from: state.serverURL) {
                            HStack(spacing: 12) {
                                Image(nsImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Scan on Android")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(state.serverURL)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        } else {
                            HStack(spacing: 10) {
                                if state.shelfFiles.isEmpty {
                                    Text("Drop files here to share with Android or Mac")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                } else {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(state.shelfFiles) { item in
                                                VStack(spacing: 4) {
                                                    Image(systemName: "doc.fill")
                                                        .font(.title3)
                                                        .foregroundStyle(.white)
                                                    Text(item.fileName)
                                                        .font(.caption2)
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                        .frame(width: 64)
                                                }
                                                .padding(6)
                                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                    .frame(height: 54)
                                }
                            }

                            if !peerDiscovery.peers.isEmpty, let firstFile = state.shelfFiles.first {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(peerDiscovery.peers) { peer in
                                            Button {
                                                peerDiscovery.sendFile(fileURL: firstFile.url, to: peer, appState: state)
                                            } label: {
                                                Label(peer.name, systemImage: "laptopcomputer")
                                                    .font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(Color.white.opacity(0.14), in: Capsule())
                                                    .foregroundStyle(.white)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            HStack {
                                Toggle("Clipboard Sync", isOn: $state.clipboardSyncEnabled)
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(state.recentTransfers.count) recent")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 20)
                }
            }
        }
    }

    private var customizePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Style")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $state.visualStyle) {
                    ForEach(NotchVisualStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            HStack {
                Text("Radius")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $state.expandedCornerRadius, in: 14...30)
                    .tint(.white)
            }
        }
        .padding(.vertical, 4)
    }

    private var currentSize: CGSize {
        if state.portalSentFileName != nil {
            return CGSize(width: 280, height: 68)
        }
        switch state.notchMode {
        case .idle:
            if state.nowPlaying != nil {
                return CGSize(width: 330, height: 36)
            }
            return CGSize(width: 190, height: 32)
        case .incomingRequest:
            return CGSize(width: 390, height: 82)
        case .transferring:
            return CGSize(width: 300, height: 76)
        case .expandedShelf:
            if state.nowPlaying != nil && !state.isDropTargeted && !state.showQR && !state.showCustomize {
                return CGSize(width: 340, height: 158)
            }
            if state.showCustomize { return CGSize(width: 360, height: 155) }
            if state.showQR { return CGSize(width: 360, height: 175) }
            return CGSize(width: 360, height: peerDiscovery.peers.isEmpty ? 165 : 200)
        }
    }

    private var cornerRadius: CGFloat {
        state.notchMode == .idle ? 14 : CGFloat(state.expandedCornerRadius)
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    state.shelfFiles.append(ShelfFile(url: url))
                    state.notchMode = .expandedShelf
                }
            }
        }
        return true
    }

    private func generateQRCode(from string: String) -> NSImage? {
        qrFilter.message = Data(string.utf8)
        guard let output = qrFilter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 120))
    }
}
