import SwiftUI

/// 音源サムネイル（#86）。
///
/// 表示の優先順位は `SoundThumbnailLogic.preferredSource` に従う:
/// 1. 保存済みサムネイル（動画フレーム / アートワーク）
/// 2. プリセット → 音源ごとの固定アイコン
/// 3. 素の音声 → 波形（最後の手段）
///
/// 波形は識別に使えないため「最後の手段」であり、常時表示には使わない
/// （Issue #86 の訂正コメント参照）。
struct SoundThumbnail: View {
    let sound: AlarmSound?
    var size: CGFloat = 36

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if sound == nil || sound!.isPreset {
                // プリセット（未指定のデフォルト音を含む）: 音源ごとの固定アイコン
                Image(systemName: SoundThumbnailLogic.presetIconName(fileName: sound?.fileName ?? ""))
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(Brand.purpleLight)
                    .frame(width: size, height: size)
                    .background(Brand.purpleLight.opacity(0.12))
            } else {
                // 素の音声: 波形（最後の手段）
                MiniWaveformBars(color: .accentColor, barWidth: max(size / 12, 2), height: size * 0.45)
                    .frame(width: size, height: size)
                    .background(Color.accentColor.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .task(id: sound?.thumbnailFileName) {
            guard let name = sound?.thumbnailFileName, !name.isEmpty else {
                image = nil
                return
            }
            image = SoundThumbnailStore.shared.image(fileName: name)
        }
    }
}