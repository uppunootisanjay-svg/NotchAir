import SwiftUI


struct SettingsView: View {
    @ObservedObject var state: AppState
    private let tabs = ["Portal", "Lock Screen", "Media", "Appearance", "General"]


    var body: some View {
        NavigationSplitView {
            List(tabs, id: \.self, selection: Binding<String?>(
                get: { state.selectedSettingsTab },
                set: { if let val = $0 { state.selectedSettingsTab = val } }
            )) { tab in
                HStack(spacing: 10) {
                    Image(systemName: iconFor(tab))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(badgeColor(tab), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(tab)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            Form {
                if state.selectedSettingsTab == "Portal" {
                    Section("Send Zone") {
                        Toggle("Enable Right-Edge Portal", isOn: $state.portalEnabled)
                    }
                    Section("Portal Effect") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(PortalEffect.allCases) { effect in
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(LinearGradient(colors: effect.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(height: 62)
                                    Text(effect.rawValue).font(.subheadline.weight(.semibold))
                                    Text(effect.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(state.portalEffect == effect ? Color.accentColor : Color.clear, lineWidth: 2))
                                .onTapGesture { state.portalEffect = effect }
                            }
                        }
                    }
                } else if state.selectedSettingsTab == "Lock Screen" {
                    Section("Clock Appearance") {
                        HStack(spacing: 10) {
                            ForEach(LockClockStyle.allCases) { style in
                                Text("12")
                                    .font(style.font(size: 26, weightValue: state.clockWeight))
                                    .foregroundStyle(style == .glassOutline ? AnyShapeStyle(.white.opacity(0.6)) : AnyShapeStyle(.primary))
                                    .frame(width: 48, height: 48)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(state.lockClockStyle == style ? Color.white : Color.white.opacity(0.15), lineWidth: state.lockClockStyle == style ? 2 : 1)
                                    )
                                    .onTapGesture { state.lockClockStyle = style }
                            }
                        }
                        .padding(.vertical, 4)


                        Slider(value: $state.clockWeight, in: 0...1) {
                            Text("Weight")
                        }
                        Toggle("Liquid Glass Finish on All Clocks", isOn: $state.liquidGlassClockEnabled)
                    }
                    Section("Lyrics") {
                        Picker("Lyrics Style", selection: $state.lyricsDisplayStyle) {
                            ForEach(LyricsDisplayStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        Toggle("Center-align Lyrics", isOn: $state.lyricsCentered)
                    }
                } else if state.selectedSettingsTab == "Media" {
                    Section("Now Playing") {
                        Text("Automatically syncs with Spotify and Apple Music.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let track = state.nowPlaying {
                            LabeledContent("Track", value: track.title)
                            LabeledContent("Artist", value: track.artist)
                            LabeledContent("App", value: track.sourceApp)
                        }
                    }
                } else if state.selectedSettingsTab == "Appearance" {
                    Section("Notch Style") {
                        Picker("Visual Style", selection: $state.visualStyle) {
                            ForEach(NotchVisualStyle.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        Slider(value: $state.expandedCornerRadius, in: 14...30) {
                            Text("Corner Radius (\(Int(state.expandedCornerRadius))pt)")
                        }
                    }
                } else {
                    Section("Local Transfer") {
                        LabeledContent("Server Address", value: state.serverURL)
                        Toggle("Clipboard Sync", isOn: $state.clipboardSyncEnabled)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .frame(minWidth: 450, minHeight: 390)
        }
        .frame(width: 660, height: 460)
    }


    private func iconFor(_ tab: String) -> String {
        switch tab {
        case "Portal": return "sparkles"
        case "Lock Screen": return "lock.display"
        case "Media": return "music.note"
        case "Appearance": return "paintbrush.fill"
        default: return "gearshape.fill"
        }
    }


    private func badgeColor(_ tab: String) -> Color {
        switch tab {
        case "Portal": return .blue
        case "Lock Screen": return .indigo
        case "Media": return .pink
        case "Appearance": return .cyan
        default: return .gray
        }
    }
}
