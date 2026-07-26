import Foundation
import os
import PostHog

// MARK: - AnalyticsEvent

/// 型安全なアナリティクスイベント定義。
/// 新規イベントはこの enum に case を追加し、`name` / `properties` を実装すること。
/// 呼び出し側が文字列でイベント名やプロパティキーを指定する必要がない（typo 防止）。
enum AnalyticsEvent: Sendable {
    // MARK: Phase 1（中核3イベント）

    /// アラーム新規作成（編集は除く）
    /// - has_custom_sound: カスタムサウンドを割り当てたか（プリセット/空は false）
    /// - is_repeating: 繰り返し曜日が設定されたか
    /// - snooze_minutes: スヌーズ時間（分）
    case alarmCreated(hasCustomSound: Bool, isRepeating: Bool, snoozeMinutes: Int)

    /// カスタムサウンドのインポート成功
    /// - source: "video" または "audio"
    case customSoundImported(source: SoundImportSource)

    /// サウンドプレビュー再生
    case soundPreviewPlayed

    // MARK: Phase 2（リテンション/運用拡張）

    /// アラーム編集（既存アラームの更新）
    /// - props は alarm_created と揃える
    case alarmEdited(hasCustomSound: Bool, isRepeating: Bool, snoozeMinutes: Int)

    /// アラーム削除
    case alarmDeleted

    /// AlarmKit 権限要求の結果
    /// - status: 安定識別子（authorized / denied / notDetermined / requestFailed / unknown）
    case alarmPermission(status: AlarmPermissionStatus)

    /// 動画からの音声抽出・変換フローの開始
    case videoImportStarted

    /// 動画からの音声抽出・変換フローの失敗
    /// - reason: 安定識別子。`error.localizedDescription` は絶対に含めない（PII/パス混入リスク）
    case videoImportFailed(reason: VideoImportFailureReason)

    /// アラーム複製
    case alarmDuplicated

    /// サウンドピッカーの「最近使った」セクションから音を選択した
    case soundPickerRecentUsed

    // MARK: Phase 3（中核指標）

    /// アラーム発火（起動中の observer または起動時の reconcile で検知）
    /// - was_app_foreground: 発火時にアプリがフォアグラウンドだったか
    /// - hour: 発火時刻の時（PII なし・時刻帯のみ）
    /// - is_repeating: 繰り返しアラームか
    /// - detection: "observer" または "reconcile"
    case alarmFired(wasAppForeground: Bool, hour: Int, isRepeating: Bool, detection: String)

    /// アラーム停止（DismissAlarmIntent の buffer 経由）
    /// - hour: 停止時刻の「時」（PII なし・時刻帯のみ）。アプリ起動時にフラッシュされるため
    ///   PostHog のイベント時刻は信頼できない、明示的に送出する
    case alarmStopped(hour: Int)

    /// アラームスヌーズ（状態遷移 .alerting → .countdown を検知）
    /// - from: "observer" または "reconcile"
    case alarmSnoozed(from: String)

    /// PostHog に送信するイベント名
    var name: String {
        switch self {
        case .alarmCreated: return "alarm_created"
        case .customSoundImported: return "custom_sound_imported"
        case .soundPreviewPlayed: return "sound_preview_played"
        case .alarmEdited: return "alarm_edited"
        case .alarmDeleted: return "alarm_deleted"
        case .alarmPermission: return "alarm_permission"
        case .videoImportStarted: return "video_import_started"
        case .videoImportFailed: return "video_import_failed"
        case .alarmDuplicated: return "alarm_duplicated"
        case .soundPickerRecentUsed: return "sound_picker_recent_used"
        case .alarmFired: return "alarm_fired"
        case .alarmStopped: return "alarm_stopped"
        case .alarmSnoozed: return "alarm_snoozed"
        }
    }

    /// イベントに付与する構造化プロパティ。
    /// ここを単一情報源とすることで、送信内容のテストが SDK 非依存で可能。
    var properties: [String: Any] {
        switch self {
        case let .alarmCreated(hasCustomSound, isRepeating, snoozeMinutes):
            return [
                "has_custom_sound": hasCustomSound,
                "is_repeating": isRepeating,
                "snooze_minutes": snoozeMinutes
            ]
        case let .customSoundImported(source):
            return ["source": source.rawValue]
        case .soundPreviewPlayed:
            return [:]
        case let .alarmEdited(hasCustomSound, isRepeating, snoozeMinutes):
            return [
                "has_custom_sound": hasCustomSound,
                "is_repeating": isRepeating,
                "snooze_minutes": snoozeMinutes
            ]
        case .alarmDeleted:
            return [:]
        case let .alarmPermission(status):
            return ["status": status.rawValue]
        case .videoImportStarted:
            return [:]
        case let .videoImportFailed(reason):
            return ["reason": reason.rawValue]
        case .alarmDuplicated:
            return [:]
        case .soundPickerRecentUsed:
            return [:]
        case let .alarmFired(wasAppForeground, hour, isRepeating, detection):
            return [
                "was_app_foreground": wasAppForeground,
                "hour": hour,
                "is_repeating": isRepeating,
                "detection": detection
            ]
        case let .alarmStopped(hour):
            return ["hour": hour]
        case let .alarmSnoozed(from):
            return ["from": from]
        }
    }
}

// MARK: - SoundImportSource

enum SoundImportSource: String, Sendable {
    case video
    case audio
}

// MARK: - AlarmPermissionStatus

/// AlarmKit 権限状態の安定識別子。
/// `error.localizedDescription` 等は使わず、ダッシュボードで安定して集計できる文字列のみ。
enum AlarmPermissionStatus: String, Sendable {
    case authorized
    case denied
    case notDetermined = "not_determined"
    case requestFailed = "request_failed"
    case unknown
}

// MARK: - VideoImportFailureReason

/// 動画インポート失敗理由の安定識別子。
/// **PII 安全**: `error.localizedDescription`（ファイルパス等が混入しうる）を
/// そのまま送信せず、発生したエラーの case を固定文字列にマップする。
/// 想定外エラーは `.unknown` に集約。
enum VideoImportFailureReason: String, Sendable {
    case noAudioTrack = "no_audio_track"
    case exportSessionFailed = "export_session_failed"
    case exportFailed = "export_failed"
    case converterSetupFailed = "converter_setup_failed"
    case conversionFailed = "conversion_failed"
    case unknown

    /// 任意の Error を安定識別子にマップする。
    /// 既知の case は個別の識別子に、それ以外は `.unknown` に集約される。
    static func from(_ error: Error) -> VideoImportFailureReason {
        switch error {
        case VideoExtractionError.noAudioTrack:
            return .noAudioTrack
        case VideoExtractionError.exportSessionFailed:
            return .exportSessionFailed
        case VideoExtractionError.exportFailed:
            return .exportFailed
        case AudioConverterError.bufferCreationFailed,
             AudioConverterError.converterCreationFailed:
            return .converterSetupFailed
        case AudioConverterError.conversionFailed:
            return .conversionFailed
        default:
            return .unknown
        }
    }
}

// MARK: - AnalyticsBackend

/// PostHog SDK 呼び出しを抽象化するプロトコル。
/// ユニットテストではこのプロトコルをモックし、PostHog SDK に依存せずに
/// 「正しいイベント名・プロパティが渡されるか」を検証できる。
protocol AnalyticsBackend: AnyObject, Sendable {
    func capture(_ event: String, properties: [String: Any]?)
    /// ユーザープロパティを設定する（identify）。PII は絶対に含めないこと。
    func setUserProperties(_ properties: [String: Any])
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

    func setUserProperties(_ properties: [String: Any]) {
        PostHogSDK.shared.identify(PostHogSDK.shared.getDistinctId(), userProperties: properties)
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
        // Phase 2: ライフサイクル自動計測を有効化（Application Opened 等 → PostHog 標準 Insights で
        // リテンション/DAU/MAU を取るため）。画面遷移は不要なので screen views は引き続き false。
        posthogConfig.captureScreenViews = false
        posthogConfig.captureApplicationLifecycleEvents = true
        // Feature Flags / A-B / Session Replay / Surveys は引き続き無効
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

        // configure 後に保留中のアラームイベント（Intent 経由）をフラッシュ
        flushPendingAlarmEvents()
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

    /// PostHog ユーザープロパティを設定する（identify）。
    /// PII は絶対に含めないこと。起動時に1回呼べば十分。
    func setUserProperties(_ properties: [String: Any]) {
        lock.lock()
        let backend = self.backend
        lock.unlock()

        guard let backend else { return }
        backend.setUserProperties(properties)
    }

    /// PendingAlarmEvent キューをフラッシュする。configure() 完了後に自動で呼ばれる。
    /// Intent 実行時にバッファされたイベント（alarm_stopped 等）を PostHog へ送信する。
    func flushPendingAlarmEvents() {
        let events = AlarmEventBuffer.dequeueAll()
        guard !events.isEmpty else { return }
        for event in events {
            var props: [String: Any] = ["timestamp": event.timestamp.timeIntervalSince1970]
            for (k, v) in event.properties {
                props[k] = v
            }
            backend?.capture(event.name, properties: props)
        }
        logger.info("Flushed \(events.count) pending alarm events")
    }
}
