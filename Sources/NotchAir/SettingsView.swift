import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    private let tabs = ["Portal", "Media", "Appearance", "General"]

    var body: some View {
        NavigationSplitView {
            List(tabs, id: \.self, selection: Binding<String?>(
                get: { state.selectedSettingsTab },
                set: { if let val = $0 { state.selectedSettingsTab = val } }
            )) { tab in
                Label(tab, systemImage: iconFor(tab))
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if state.selectedSettingsTab == "Portal" {
                        portalSettings
                    } else if state.selectedSettingsTab == "Media" {
                        mediaSettings
                    } else if state.selectedSettingsTab == "Appearance" {
                        appearanceSettings
                    } else {
                        generalSettings
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 440, minHeight: 380)
        }
        .frame(width: 640, height: 440)
    }

    private var portalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Send Zone").font(.headline)
                    Text("Drag files to the right edge of your Mac screen to send to Android.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $state.portalEnabled).toggleStyle(.switch)
            }

            Text("Effect").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(PortalEffect.allCases) { effect in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: effect.colors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 68)
                        Text(effect.rawValue).font(.subheadline.weight(.semibold))
                        Text(effect.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(state.portalEffect == effect ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .onTapGesture { state.portalEffect = effect }
                }
            }
        }
    }

    private var mediaSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Now Playing").font(.headline)
            Text("NotchAir automatically listens to Spotify and Apple Music playback and displays album art and controls in the notch.")
                .font(.caption).foregroundStyle(.secondary)
            if let track = state.nowPlaying {
                GroupBox {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(track.title).font(.subheadline.weight(.semibold))
                            Text("\(track.artist) • \(track.sourceApp)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(track.isPlaying ? "Playing" : "Paused").font(.caption)
                    }
                }
            }
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notch Appearance").font(.headline)
            HStack {
                Text("Accent Color")
                Spacer()
                ForEach(NotchAccent.allCases) { item in
                    Circle()
                        .fill(item.color)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.primary, lineWidth: state.accent == item ? 2 : 0))
                        .onTapGesture { state.accent = item }
                }
            }
            Picker("Visual Style", selection: $state.visualStyle) {
                ForEach(NotchVisualStyle.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Corner Radius (\(Int(state.expandedCornerRadius))pt)")
                Slider(value: $state.expandedCornerRadius, in: 14...30)
            }
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Server & Clipboard").font(.headline)
            Text("Local Address: \(state.serverURL)").font(.caption.monospaced())
            Toggle("Clipboard Sync", isOn: $state.clipboardSyncEnabled)
        }
    }

    private func iconFor(_ tab: String) -> String {
        switch tab {
        case "Portal": return "sparkles"
        case "Media": return "music.note"
        case "Appearance": return "paintbrush"
        default: return "gear"
        }
    }
}
