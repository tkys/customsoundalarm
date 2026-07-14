import Foundation
import os
import PostHog

// MARK: - AnalyticsEvent

/// 型安全なアナリティクスイベント定義。
/// 新規イベントはこの enum に case を追加し、`name` / `properties` を実装すること。
/// 呼び出し側が文字列でイベント名やプロパティキーを指定する必要がない（typo 防止）。
enum AnalyticsEvent: Sendable {
    /// アラーム新規作成（編集は除く）
    /// - has_custom_sound: カスタムサウンドを割り当てたか（プリセット/空は false）
    /// - is_repeating: 繰り返し曜日が設定されたか
    case alarmCreated(hasCustomSound: Bool, isRepeating: Bool)

    /// カスタムサウンドのインポート成功
    /// - source: "video" または "audio"
    case customSoundImported(source: SoundImportSource)

    /// サウンドプレビュー再生
    case soundPreviewPlayed

    /// PostHog に送信するイベント名
    var name: String {
        switch self {
        case .alarmCreated: return "alarm_created"
        case .customSoundImported: return "custom_sound_imported"
        case .soundPreviewPlayed: return "sound_preview_played"
        }
    }

    /// イベントに付与する構造化プロパティ。
    /// ここを単一情報源とすることで、送信内容のテストが SDK 非依存で可能。
    var properties: [String: Any] {
        switch self {
        case let .alarmCreated(hasCustomSound, isRepeating):
            return [
                "has_custom_sound": hasCustomSound,
                "is_repeating": isRepeating
            ]
        case let .customSoundImported(source):
            return ["source": source.rawValue]
        case .soundPreviewPlayed:
            return [:]
        }
    }
}

// MARK: - SoundImportSource

enum SoundImportSource: String, Sendable {
    case video
    case audio
}

// MARK: - AnalyticsBackend

/// PostHog SDK 呼び出しを抽象化するプロトコル。
/// ユニットテストではこのプロトコルをモックし、PostHog SDK に依存せずに
/// 「正しいイベント名・プロパティが渡されるか」を検証できる。
protocol AnalyticsBackend: AnyObject, Sendable {
    func capture(_ event: String, properties: [String: Any]?)
}

// MARK: - AnalyticsConfig

/// Info.plist (経由で xcconfig) から読み込む PostHog 設定。
struct AnalyticsConfig: Equatable, Sendable {
    let apiKey: String
    let host: String
    let isDebug: Bool

    /// 与えられた Bundle から設定を読み込む（テスト用に Bundle を注入可能）。
    /// 失敗時（キー不足・空文字）は nil を返す。
    static func from(bundle: Bundle = .main) -> AnalyticsConfig? {
        guard
            let apiKey = bundle.object(forInfoDictionaryKey: "PostHogAPIKey") as? String,
            let host = bundle.object(forInfoDictionaryKey: "PostHogHost") as? String,
            !apiKey.isEmpty,
            !host.isEmpty
        else { return nil }

        let debugRaw = bundle.object(forInfoDictionaryKey: "PostHogDebug") as? String
        let isDebug = debugRaw.map { $0.lowercased() == "yes" } ?? false

        return AnalyticsConfig(apiKey: apiKey, host: host, isDebug: isDebug)
    }
}

// MARK: - PostHogAnalyticsBackend

/// PostHog SDK を実際に呼び出すバックエンド実装。
/// `import PostHog` を使用する唯一の実装。将来差し替え可能にするためプロトコル背後で隠す。
final class PostHogAnalyticsBackend: AnalyticsBackend {
    func capture(_ event: String, properties: [String: Any]?) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
}

// MARK: - AnalyticsService

/// アプリ全体のアナリティクス送信を担う薄いラッパー。
/// PostHog への直接依存をこのファイルに閉じ込め、呼び出し側は `AnalyticsEvent` enum 経由で型安全に計測する。
/// PII（メール等）は絶対に送信しない。ユーザー識別は PostHog 既定の匿名IDに任せる（identify しない）。
final class AnalyticsService: @unchecked Sendable {
    static let shared = AnalyticsService()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "Analytics")
    private let lock = NSLock()
    private var backend: AnalyticsBackend?
    private(set) var isEnabled = false

    private init() {
        // デフォルトは無効。`configure()` で有効化する。
    }

    /// テスト・DI 用のコンストラクタ。本番では `.shared` と `configure()` を使用。
    init(backend: AnalyticsBackend?) {
        self.backend = backend
        self.isEnabled = backend != nil
    }

    /// Info.plist から PostHog 設定を読み込み、SDK を初期化する。
    /// アプリ起動時に1度だけ呼ぶこと（複数回呼び出しは無視される）。
    func configure(bundle: Bundle = .main) {
        lock.lock()
        defer { lock.unlock() }

        guard !isEnabled else {
            logger.info("AnalyticsService already configured — skipping")
            return
        }

        guard let config = AnalyticsConfig.from(bundle: bundle) else {
            logger.warning("PostHog config missing or empty — analytics disabled (set PostHogAPIKey/PostHogHost)")
            return
        }

        let posthogConfig = PostHogConfig(projectToken: config.apiKey, host: config.host)
        posthogConfig.debug = config.isDebug
        // Phase 1 では中核3イベントのみ計測。自動計測系はすべて無効化（拡張は次Phase）。
        posthogConfig.captureScreenViews = false
        posthogConfig.captureApplicationLifecycleEvents = false
        // Feature Flags / A-B / Session Replay / Surveys は Phase 1 では無効
        posthogConfig.preloadFeatureFlags = false
        posthogConfig.sendFeatureFlagEvent = false
        posthogConfig.sessionReplay = false
        if #available(iOS 15.0, *) {
            posthogConfig.surveys = false
        }

        PostHogSDK.shared.setup(posthogConfig)

        backend = PostHogAnalyticsBackend()
        isEnabled = true
        logger.info("PostHog configured (host=\(config.host, privacy: .public), debug=\(config.isDebug))")
    }

    /// イベントを送信する。
    /// - Parameters:
    ///   - event: 型安全なイベント定義
    ///   - properties: 追加プロパティ（任意）。同名キーは追加側で上書き。
    func capture(_ event: AnalyticsEvent, properties: [String: Any]? = nil) {
        let payload: [String: Any]?
        if let extra = properties, !extra.isEmpty {
            var merged = event.properties
            for (key, value) in extra {
                merged[key] = value
            }
            payload = merged
        } else {
            payload = event.properties.isEmpty ? nil : event.properties
        }

        lock.lock()
        let backend = self.backend
        lock.unlock()

        guard let backend else {
            // 計測無効時はサイレントにドロップ（呼び出し側で判定不要）
            return
        }

        backend.capture(event.name, properties: payload)
    }
}
