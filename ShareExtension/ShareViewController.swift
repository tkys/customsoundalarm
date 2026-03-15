import UIKit
import UniformTypeIdentifiers
import os

/// Share Extension: 他アプリから音声ファイルを受け取りステージングに保存
/// メインアプリがフォアグラウンド復帰時にCAF変換を行う
class ShareViewController: UIViewController {

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm.share", category: "ShareExt")
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processSharedItems()
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = .systemBackground

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "保存中..."
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Processing

    private func processSharedItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(error: "データを受け取れませんでした")
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
                    loadAudio(from: provider)
                    return
                }
                // 動画の音声も受け付ける
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    loadAudio(from: provider, typeIdentifier: UTType.movie.identifier)
                    return
                }
            }
        }

        finish(error: "対応する音声ファイルが見つかりませんでした")
    }

    private func loadAudio(from provider: NSItemProvider, typeIdentifier: String? = nil) {
        let uti = typeIdentifier ?? UTType.audio.identifier

        provider.loadFileRepresentation(forTypeIdentifier: uti) { [weak self] url, error in
            guard let self else { return }
            if let url {
                // temp fileはこのcallback終了後に削除されるため、ここでコピーする
                let staging = AppGroup.stagingDirectory
                let ext = url.pathExtension
                let stagedFileName = "\(UUID().uuidString).\(ext)"
                let destURL = staging.appendingPathComponent(stagedFileName)
                let originalName = url.deletingPathExtension().lastPathComponent

                do {
                    try FileManager.default.copyItem(at: url, to: destURL)

                    let pending = PendingSoundImport(
                        displayName: originalName,
                        stagedFileName: stagedFileName
                    )
                    let metadataURL = staging.appendingPathComponent("\(UUID().uuidString).json")
                    let data = try JSONEncoder().encode(pending)
                    try data.write(to: metadataURL)

                    self.logger.info("Staged: \(originalName)")

                    DispatchQueue.main.async {
                        self.finish(success: originalName)
                    }
                } catch {
                    self.logger.error("Staging failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.finish(error: error.localizedDescription)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.finish(error: error?.localizedDescription ?? "ファイルの読み込みに失敗しました")
                }
            }
        }
    }


    // MARK: - Completion

    private func finish(success name: String) {
        spinner.stopAnimating()
        statusLabel.text = "「\(name)」を保存しました"

        let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmark.tintColor = .systemGreen
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.contentMode = .scaleAspectFit
        view.addSubview(checkmark)
        NSLayoutConstraint.activate([
            checkmark.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            checkmark.widthAnchor.constraint(equalToConstant: 60),
            checkmark.heightAnchor.constraint(equalToConstant: 60),
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func finish(error message: String) {
        spinner.stopAnimating()
        statusLabel.text = message
        statusLabel.textColor = .systemRed

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(
                domain: "com.tkysdev.customsoundalarm.share",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
        }
    }
}
