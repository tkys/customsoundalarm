import SwiftUI
import MediaPlayer
import AVFoundation

/// ミュージックアプリのライブラリから1曲選ぶ（#245）。
/// クラウド曲・保護された曲は出さない（選べても assetURL が nil になるため）。
struct MusicLibraryPickerView: UIViewControllerRepresentable {
    let onPick: (MPMediaItem) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
        picker.showsItemsWithProtectedAssets = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        private let onPick: (MPMediaItem) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (MPMediaItem) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func mediaPicker(
            _ mediaPicker: MPMediaPickerController,
            didPickMediaItems mediaItemCollection: MPMediaItemCollection
        ) {
            guard let item = mediaItemCollection.items.first else {
                onCancel()
                return
            }
            onPick(item)
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            onCancel()
        }
    }
}

/// ミュージックライブラリの曲を、既存の切り取り画面で扱えるファイルに書き出す（#245）。
enum MusicLibraryImporter {

    /// 曲名を初期値にする。空なら既定の名前。
    static func initialName(for item: MPMediaItem) -> String {
        initialName(title: item.title)
    }

    /// 曲名（`MPMediaItem.title`）を初期値にする。空・空白だけなら既定の名前。
    /// `MPMediaItem` はテストで作れないため、文字列だけを受け取る形も用意する。
    static func initialName(title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(localized: "imported_sound_default") : trimmed
    }

    /// `assetURL` を m4a に書き出す。書き出せなければ nil。
    static func export(assetURL: URL) async -> URL? {
        let asset = AVURLAsset(url: assetURL)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else { return nil }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("music-\(UUID().uuidString).m4a")
        do {
            try await session.export(to: outputURL, as: .m4a)
            return outputURL
        } catch {
            // 途中まで書かれたファイルを残さない
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
    }
}
