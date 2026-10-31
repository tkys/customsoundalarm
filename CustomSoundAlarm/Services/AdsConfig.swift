import CoreGraphics
import Foundation

/// 広告の全体スイッチと定数（#111）。
/// このIssueでは広告 SDK を入れないため、`isEnabled` は false のまま。
enum AdsConfig {

    /// 全体スイッチ。false の間は何も表示せず、判定と計測だけ動く。
    static let isEnabled: Bool = false

    /// 広告導入ビルド（これより前にインストールしたユーザーには出さない）。
    ///
    /// `AppTransaction.originalAppVersion` は **CFBundleVersion（ビルド番号）** を返すため、
    /// マーケティングバージョンではなくビルド番号で比較する。
    /// 1.9.0 のビルド番号が確定したら、リリース前にこの値を合わせること。
    /// 1.8.0=10、1.8.1=11（広告・制限なし）を先に出すため、1.9.0=12（2026-10-30）。
    /// 11 のままだと 1.8.1 で入れた人が「新規」扱いになり、広告と音3つ制限の対象になってしまう。
    static let introductionBuild: Int = 12

    /// 初回起動からの猶予（日）
    static let firstLaunchGraceDays: Int = 7

    /// 全画面広告の最小間隔（日）
    static let interstitialMinIntervalDays: Int = 7

    /// 出さない時間帯（端末の地元時刻）。21:00〜6:59
    static let quietHoursStart: Int = 21
    static let quietHoursEnd: Int = 7

    /// バナーの高さ（SDK 組み込み時に使う。今は高さ0で描画しない）
    static let bannerHeight: CGFloat = 50
}

/// バナー枠の表示制御（純ロジック・テスト対象）。
enum AdSlotLayout {
    static func shouldRender(isEnabled: Bool, allowed: Bool) -> Bool {
        isEnabled && allowed
    }

    static func height(isEnabled: Bool = AdsConfig.isEnabled) -> CGFloat {
        isEnabled ? AdsConfig.bannerHeight : 0
    }
}
