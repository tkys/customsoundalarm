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
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Brand.orange)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // AX では見出しとバッジを横に並べると重なるため、縦に分ける（#183）。
            VStack(alignment: .leading, spacing: 4) {
                title
                EarlyAccessBadge()
            }
        } else {
            HStack(spacing: 8) {
                title
                EarlyAccessBadge()
            }
        }
    }

    private var title: some View {
        Text("playlist_title")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.heading)
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


// MARK: - Empty state (#183)

/// プレイリストが空のときの共通表示。
/// ライブラリとアラームの「音」選択の両方で使い、使い道と作成導線を伝える。
struct PlaylistEmptyStateView: View {
    let source: PlaylistSource
    let hasOwnSounds: Bool
    let createButtonIdentifier: String
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("playlist_empty_explanation")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("playlist.empty.explanation")

            if !hasOwnSounds {
                Text("playlist_empty_import_hint")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("playlist.empty.importHint")
            }

            Button {
                onCreate()
            } label: {
                Label("playlist_new", systemImage: "plus")
                    .foregroundStyle(Color.actionText)
            }
            // List の行全体ではなく、ボタンの部分だけが反応するようにする
            // （説明文のタップで作成画面が開かないように）。
            .buttonStyle(.borderless)
            .accessibilityIdentifier(createButtonIdentifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .onAppear {
            PlaylistEmptyViewTracker.shared.recordViewed(
                source: source,
                hasOwnSounds: hasOwnSounds
            )
        }
    }
}
