import Foundation
import UniformTypeIdentifiers

/// 動画ファイルのインポート（temp コピー・型判定）を担うヘルパー。
///
/// **security-scoped resource の寿命**:
/// `.fileImporter` で選択した URL は security-scoped のため、
/// `startAccessingSecurityScopedResource()` から `stopAccessingSecurityScopedResource()`
/// の間のみアクセス可能。動画処理（`AVAssetExportSession`）は非同期で数秒かかるため、
/// **選択直後に temp へコピー → 即解放** する順序を厳守する。
///
/// **iCloud Drive の未ダウンロードファイル**:
/// ローカルに実体が無い URL が返る場合、`NSFileCoordinator` でコーディネート読み込みを
/// 行い、ダウンロード完了を待つ（UI 側で進捗を表示すること）。
enum VideoFileImporter {

    /// 動画ファイルとして許容する UTType
    static let supportedVideoTypes: [UTType] = [
        .movie, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg
    ]

    // MARK: - Pure Functions（単体テスト対象）

    /// temp ディレクトリ内の一意な URL を生成する。
    /// - Parameters:
    ///   - filename: UUID 等の一意なファイル名（拡張子なし）
    ///   - ext: 拡張子。空の場合は `mov` を補完
    /// - Returns: `temporaryDirectory/filename.ext`
    static func generateTempURL(filename: String, extension ext: String) -> URL {
        let safeExt = ext.isEmpty ? "mov" : ext
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension(safeExt)
    }

    /// URL がサポート対象の動画形式かを判定する。
    /// 拡張子から UTType を推定し、`supportedVideoTypes` のいずれかに適合するか確認。
    /// 拡張子が取れない場合は `false`（厳密な判定は `AVURLAsset` に委ねる）。
    static func isSupportedVideoURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return supportedVideoTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - File Copy（I/O）

    /// security-scoped URL から temp へコピーする。
    /// iCloud Drive の未ダウンロードファイルは `NSFileCoordinator` でダウンロードを待機する。
    ///
    /// - Parameter sourceURL: `.fileImporter` で取得した security-scoped URL
    /// - Returns: temp ディレクトリにコピーされた URL（呼び出し元で自由にアクセス可能）
    ///
    /// - Note: 呼び出し元で `startAccessingSecurityScopedResource()` /
    ///   `stopAccessingSecurityScopedResource()` を管理すること。
    ///   この関数はコピーが完了してから返すため、security scope 内で呼べば
    ///   コピー完了後に即座に scope を解放できる。
    static func copyToTemp(from sourceURL: URL) async throws -> URL {
        let tempURL = generateTempURL(
            filename: UUID().uuidString,
            extension: sourceURL.pathExtension
        )

        try await Task.detached(priority: .userInitiated) {
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var copyError: Error?

            coordinator.coordinate(
                readingItemAt: sourceURL,
                options: [],
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: coordinatedURL, to: tempURL)
                } catch {
                    copyError = error
                }
            }

            if let copyError { throw copyError }
            if let coordinationError { throw coordinationError }

            guard FileManager.default.fileExists(atPath: tempURL.path) else {
                throw VideoImportError.fileCopyFailed
            }
        }.value

        return tempURL
    }
}

// MARK: - VideoImportError

enum VideoImportError: LocalizedError {
    case fileAccessDenied
    case fileCopyFailed
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            String(localized: "error_file_access_denied")
        case .fileCopyFailed:
            String(localized: "error_file_copy_failed")
        case .unsupportedFormat:
            String(localized: "error_unsupported_video_format")
        }
    }
}
