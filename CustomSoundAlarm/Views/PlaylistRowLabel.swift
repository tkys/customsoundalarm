import SwiftUI

/// プレイリストの行ラベル（ライブラリ・音の選択で共通・#160 PR-2）。
struct PlaylistRowLabel: View {
    let playlist: Playlist
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    private var summary: String {
        String(
            format: String(localized: "playlist_summary_fmt"),
            localizedPlayOrderTitle(playlist.playOrder),
            playlist.trackCount
        )
    }
}

/// プレイリスト見出し（「PRO・先行公開中」付き）。
struct PlaylistSectionHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("playlist_title")
            EarlyAccessBadge()
        }
    }
}

/// 再生順の表示名。
func localizedPlayOrderTitle(_ order: PlaylistPlayOrder) -> String {
    switch order {
    case .inOrder: String(localized: "play_order_in_order")
    case .shuffle: String(localized: "play_order_shuffle")
    case .oneRandom: String(localized: "play_order_one_random")
    }
}
