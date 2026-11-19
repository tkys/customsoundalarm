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

/// ミュージック取り込みの進行状態（#245）。
///
/// ピッカーのシートは `List` の中ではなく、`SoundLibrarySections` を載せている
/// 親画面の `List` に付ける（1.8.1 の「シートを List の中に付けると親ごと閉じる」
/// 不具合を避ける）。親は `.musicLibraryImport(controller)` を `List` に付ける。
///
/// 切り取り画面はピッカーが閉じきってから開く。短い曲だと書き出しが先に終わり、
/// 閉じるアニメーション中のシートに重なって開けないことがあるため。
@Observable
@MainActor
final class MusicLibraryImportController {

    struct Notice: Equatable {
        let text: String
        /// 許可がないときは、この1行を押すと設定アプリを開く（#245 レビュー）。
        let opensSettings: Bool
    }

    /// ピッカーのシート表示。親画面のシート Binding から読み書きする。
    var isPickerPresented = false
    /// 曲を選んだあと、m4a を書き出している間だけ true。
    private(set) var isExporting = false
    /// 画面に出す短い1行（取り込めない曲・許可がないとき）。
    private(set) var notice: Notice?
    /// ピッカーが閉じきるのを待っている、書き出し済みの取り込み。
    private var waitingForPickerDismissal: PendingAudioImport?
    /// ピッカーが閉じきってから渡す、書き出し済みの取り込み。
    private(set) var pendingImport: PendingAudioImport?
    private var isPickerDismissed = true

    /// 「ミュージックから」を押したときだけ許可を求める。
    func requestAndOpen() {
        notice = nil
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            presentPicker()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { status in
                Task { @MainActor in
                    if status == .authorized {
                        self.presentPicker()
                    } else {
                        self.showPermissionDenied()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionDenied()
        @unknown default:
            showPermissionDenied()
        }
    }

    /// ピッカーで曲を選んだ（`MusicLibraryPickerView` の delegate から）。
    func pick(_ item: MPMediaItem) {
        isPickerPresented = false
        notice = nil
        let name = MusicLibraryImporter.initialName(for: item)
        guard let assetURL = item.assetURL else {
            showUnavailable()
            return
        }

        isExporting = true
        Task {
            let exportedURL = await MusicLibraryImporter.export(assetURL: assetURL)
            isExporting = false
            guard let exportedURL else {
                showUnavailable()
                return
            }
            let pending = PendingAudioImport(
                url: exportedURL,
                name: name,
                source: .musicLibrary
            )
            if isPickerDismissed {
                pendingImport = pending
            } else {
                waitingForPickerDismissal = pending
            }
        }
    }

    /// ピッカーのシートが閉じきった（シートの `onDismiss`）。
    func pickerDidDismiss() {
        isPickerDismissed = true
        if let pending = waitingForPickerDismissal {
            waitingForPickerDismissal = nil
            pendingImport = pending
        }
    }

    /// 切り取り画面に渡したら nil に戻す。
    func consumePendingImport() -> PendingAudioImport? {
        defer { pendingImport = nil }
        return pendingImport
    }

    private func presentPicker() {
        notice = nil
        isPickerDismissed = false
        isPickerPresented = true
    }

    private func showPermissionDenied() {
        notice = Notice(
            text: String(localized: "music_library_permission_denied"),
            opensSettings: true
        )
    }

    private func showUnavailable() {
        notice = Notice(
            text: String(localized: "music_library_unavailable"),
            opensSettings: false
        )
        AnalyticsService.shared.capture(.musicLibraryUnavailable)
    }

    #if DEBUG
    /// UIテスト・スクショ用: 許可が拒否されている状態の1行を出す（#245）。
    func showPermissionDeniedForUITest() {
        notice = Notice(
            text: String(localized: "music_library_permission_denied"),
            opensSettings: true
        )
    }

    /// UIテスト・スクショ用: 「取り込めません」の1行を出す（#245）。
    func showUnavailableForUITest() {
        notice = Notice(
            text: String(localized: "music_library_unavailable"),
            opensSettings: false
        )
    }
    #endif
}

extension View {
    /// ミュージックのピッカーを、`List` の外側（親画面）で1回だけ提示する（#245）。
    func musicLibraryImport(_ controller: MusicLibraryImportController) -> some View {
        sheet(
            isPresented: Binding(
                get: { controller.isPickerPresented },
                set: { controller.isPickerPresented = $0 }
            ),
            onDismiss: { controller.pickerDidDismiss() }
        ) {
            MusicLibraryPickerView(
                onPick: { controller.pick($0) },
                onCancel: { controller.isPickerPresented = false }
            )
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
    /// 書き出したファイルは既存の「ファイルから」と同じ一時ファイルで、
    /// 切り取り画面の保存・破棄で `AudioCropView` が削除する。
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
