import SwiftUI

/// 「PRO・先行公開中」の小さなバッジ（#151）。
struct EarlyAccessBadge: View {
    var body: some View {
        Text("pro_early_access")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.orange.opacity(0.16))
            )
            .foregroundStyle(Color.orange)
            .accessibilityIdentifier("playlist.earlyAccessBadge")
    }
}

/// フェード設定の画面（#151）。
struct FadeSettingsView: View {
    @Binding var fadeSettings: PlaylistFadeSettings
    let isPlaylist: Bool

    var body: some View {
        List {
            Section {
                Picker("fade_in", selection: $fadeSettings.fadeIn) {
                    Text("fade_off").tag(PlaylistFadeIn.off)
                    Text("fade_in_10").tag(PlaylistFadeIn.ten)
                    Text("fade_in_30").tag(PlaylistFadeIn.thirty)
                    Text("fade_in_60").tag(PlaylistFadeIn.sixty)
                }
                .accessibilityIdentifier("fade.fadeIn")
            } footer: {
                Text("fade_in_footer")
            }

            if isPlaylist {
                Section {
                    Picker("gap_fade", selection: $fadeSettings.gapFade) {
                        Text("fade_off").tag(PlaylistGapFade.off)
                        Text("gap_fade_short").tag(PlaylistGapFade.short)
                        Text("gap_fade_long").tag(PlaylistGapFade.long)
                        Text("gap_fade_crossfade").tag(PlaylistGapFade.crossfade)
                    }
                    .accessibilityIdentifier("fade.gapFade")
                } footer: {
                    Text("gap_fade_footer")
                }
            }

            Section {
                Toggle("end_fade", isOn: $fadeSettings.endFade)
                    .accessibilityIdentifier("fade.endFade")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("end_fade_footer")
                    Text("fade_backup_note")
                        .foregroundStyle(.secondary)
                    Text("playlist_backup_note")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                EarlyAccessBadge()
                Text("playlist_early_access_note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(String(localized: "fade_settings"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension PlaylistFadeSettings {
    /// 追加画面の行に出す短い要約（#151）。
    var summary: String {
        if isDisabled { return String(localized: "fade_summary_off") }
        var parts: [String] = []
        if fadeIn != .off {
            parts.append(String(
                format: String(localized: "fade_in_seconds_fmt"),
                fadeIn.rawValue
            ))
        }
        switch gapFade {
        case .off: break
        case .short: parts.append(String(localized: "gap_fade_short"))
        case .long: parts.append(String(localized: "gap_fade_long"))
        case .crossfade: parts.append(String(localized: "gap_fade_crossfade"))
        }
        if endFade {
            parts.append(String(localized: "end_fade"))
        }
        return parts.joined(separator: " · ")
    }
}
