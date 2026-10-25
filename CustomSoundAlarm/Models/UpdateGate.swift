import Foundation

/// サーバ不要のアプリ設定（#116）。GitHub Pages で配信する `docs/app-config.json`。
///
/// **比較はビルド番号（`CFBundleVersion`、Int）だけ**で行う。
/// マーケティングバージョンの文字列比較はしない。
struct AppConfig: Codable, Equatable, Sendable {

    /// これ未満のビルドは必須アップデート
    let minimumBuild: Int
    /// これ未満のビルドはおすすめアップデート
    let latestBuild: Int

    enum CodingKeys: String, CodingKey {
        case minimumBuild = "minimum_build"
        case latestBuild = "latest_build"
    }

    init(minimumBuild: Int, latestBuild: Int) {
        self.minimumBuild = minimumBuild
        self.latestBuild = latestBuild
    }

    /// JSON から読む。欠損・型違い・不正値（負数、latest < minimum）は nil。
    init?(data: Data) {
        guard let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return nil
        }
        guard decoded.minimumBuild >= 0,
              decoded.latestBuild >= 0,
              decoded.minimumBuild <= decoded.latestBuild
        else { return nil }
        self = decoded
    }
}

/// アップデート表示の種類
enum UpdatePromptKind: String, Sendable, Equatable {
    case required
    case recommended
}

/// 表示するアップデート案内
struct UpdatePrompt: Equatable, Sendable, Identifiable {
    let kind: UpdatePromptKind
    let currentBuild: Int
    let targetBuild: Int

    var id: String { kind.rawValue }
}

/// `UpdateGate` の入力。
struct UpdateGateInput: Equatable, Sendable {
    let currentBuild: Int?
    let config: AppConfig?
    let configFetchedAt: Date?
    let now: Date
    let dismissedRecommendedBuild: Int?
    let isOnboardingVisible: Bool
    let isAlarmRinging: Bool
    let isTestRinging: Bool
}

/// アップデート必須／おすすめの判定（純ロジック・#116）。
///
/// 運用:
/// - `minimum_build` は **重大な不具合（アラームが鳴らない等）のときだけ** 上げる。
///   通常の更新は `latest_build` だけ上げる（おすすめ表示）。
/// - 上げるのは新しい版が全地域・段階的リリースを含めて行き渡ってから（目安: 公開48時間後）。
/// - 取得できないときは絶対にブロックしない。
enum UpdateGate {

    /// キャッシュ由来の「必須」を有効にする最大経過時間
    static let requiredMaxCacheAge: TimeInterval = 7 * 24 * 60 * 60

    static func decide(_ input: UpdateGateInput) -> UpdatePrompt? {
        // 出さない場面
        if input.isOnboardingVisible || input.isAlarmRinging || input.isTestRinging {
            return nil
        }

        // 現在のビルドが読めない・設定が無い/壊れている → 何もしない
        guard let currentBuild = input.currentBuild, let config = input.config else {
            return nil
        }

        if currentBuild < config.minimumBuild {
            // キャッシュが古い場合は必須にしない（誤ブロック防止）
            guard let fetchedAt = input.configFetchedAt,
                  input.now.timeIntervalSince(fetchedAt) <= requiredMaxCacheAge
            else {
                return nil
            }
            return UpdatePrompt(
                kind: .required,
                currentBuild: currentBuild,
                targetBuild: config.minimumBuild
            )
        }

        if currentBuild < config.latestBuild {
            // 同じ latest_build につき1回だけ
            if input.dismissedRecommendedBuild == config.latestBuild {
                return nil
            }
            return UpdatePrompt(
                kind: .recommended,
                currentBuild: currentBuild,
                targetBuild: config.latestBuild
            )
        }

        return nil
    }

    /// アプリのビルド番号（CFBundleVersion）。読めなければ nil。
    static func currentBuild(bundle: Bundle = .main) -> Int? {
        guard let raw = bundle.infoDictionary?["CFBundleVersion"] as? String,
              let build = Int(raw),
              build >= 0
        else { return nil }
        return build
    }
}
