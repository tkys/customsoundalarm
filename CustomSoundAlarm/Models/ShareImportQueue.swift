import Foundation

/// 共有シートから staging に置かれた1件（#222）。
struct ShareImportItem: Identifiable, Equatable {
    /// メタデータ JSON のファイル名。staging 内で一意。
    let id: String
    let displayName: String
    let mediaURL: URL
    let mediaKind: ShareImportMedia
    let metadataURL: URL
}

/// 共有シートの受け取りを、起動時の切り取り画面に渡す（#222）。
enum ShareImportQueue {

    /// staging の保留を、共有された順（古い順）に返す。
    /// メタデータが壊れている・音声ファイルが無いものは飛ばす。
    static func pendingItems(
        stagingDirectory: URL = AppGroup.stagingDirectory,
        fileManager: FileManager = .default
    ) -> [ShareImportItem] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let orderedJSON = files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                if left == right { return lhs.lastPathComponent < rhs.lastPathComponent }
                return left < right
            }

        return orderedJSON.compactMap { metadataURL in
            guard let data = try? Data(contentsOf: metadataURL),
                  let pending = try? JSONDecoder().decode(PendingSoundImport.self, from: data)
            else { return nil }

            let mediaURL = stagingDirectory.appendingPathComponent(pending.stagedFileName)
            guard fileManager.fileExists(atPath: mediaURL.path) else { return nil }

            return ShareImportItem(
                id: metadataURL.lastPathComponent,
                displayName: pending.displayName,
                mediaURL: mediaURL,
                mediaKind: mediaKind(
                    fileExtension: mediaURL.pathExtension,
                    stored: pending.mediaKind
                ),
                metadataURL: metadataURL
            )
        }
    }

    /// 保存できた1件を staging から消す。
    static func complete(
        _ item: ShareImportItem,
        fileManager: FileManager = .default
    ) {
        try? fileManager.removeItem(at: item.metadataURL)
        try? fileManager.removeItem(at: item.mediaURL)
    }

    /// 種類は保存時の値を使い、無ければ拡張子から判定する（1.8.2 以前のデータ）。
    static func mediaKind(
        fileExtension: String,
        stored: String?
    ) -> ShareImportMedia {
        if let stored = stored.flatMap(ShareImportMedia.init(rawValue:)) {
            return stored
        }
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi"]
        return videoExtensions.contains(fileExtension.lowercased()) ? .video : .audio
    }
}
