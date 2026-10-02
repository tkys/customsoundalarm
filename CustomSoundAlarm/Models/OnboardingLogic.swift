import Foundation

/// オンボーディング（#98「好きな瞬間を選ぶだけ」）の表示判定とステップ定義。純ロジック。
///
/// 設計意図（docs/onboarding_refresh_instructions.md）:
/// - 価値を見せてから許可を聞く（許可要求は場面3へ移動）
/// - 新規インストール（アラーム0件・取り込み音源0件）にだけ出す
/// - 既存ユーザー（アップデートで来た人）には出さない。初回起動時に条件を満たさなければ
///   完了フラグを立てて以後出さない
enum OnboardingLogic {

    /// オンボを出すか。未完了 かつ アラーム0件 かつ 取り込み音源0件 のときだけ true
    static func shouldShow(hasCompleted: Bool, alarmCount: Int, importedSoundCount: Int) -> Bool {
        if hasCompleted { return false }
        if alarmCount > 0 { return false }
        if importedSoundCount > 0 { return false }
        return true
    }

    /// 起動時に AlarmKit の許可要求を呼ぶか。
    /// オンボを出す人は場面3で聞くため起動時には呼ばない（#98 Phase 1）
    static func shouldRequestAuthorizationAtLaunch(shouldShowOnboarding: Bool) -> Bool {
        !shouldShowOnboarding
    }

    /// 既存ユーザー（条件を満たさない）の初回起動時に完了フラグを立てるか。
    /// shouldShow が false かつ未完了のとき true → 立てて以後出さない
    static func shouldMarkCompleted(hasCompleted: Bool, shouldShowOnboarding: Bool) -> Bool {
        !hasCompleted && !shouldShowOnboarding
    }
}

/// オンボの場面4「どこから音を持ってくる？」の選択（計測の source 値と一致させる）
enum OnboardingSource: String, Equatable, Sendable {
    case video
    case audio
    case preset
    case later

    /// 追加画面（AlarmDetailView）を開いた直後に直接開く入口があるか
    var opensAddScreen: Bool {
        self != .later
    }
}

/// オンボの場面（計測の step 値と一致させる）
enum OnboardingStep: String, Equatable, Sendable {
    case intro
    case loop
    case permission
    case source
}
