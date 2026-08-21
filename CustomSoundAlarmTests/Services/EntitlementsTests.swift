import Testing
import Foundation
@testable import CustomSoundAlarm

/// `resolveProStatus`（罠1の3分岐純粋関数）の検証。
/// StoreKit に依存せず純粋関数のみでテストする。
struct EntitlementsTests {

    // MARK: - resolveProStatus 基本3分岐

    @Test
    func resolve_active_returnsTrue() {
        #expect(resolveProStatus(result: .active, cachedValue: nil) == true)
        #expect(resolveProStatus(result: .active, cachedValue: false) == true)
        #expect(resolveProStatus(result: .active, cachedValue: true) == true)
    }

    @Test
    func resolve_inactive_returnsFalse() {
        #expect(resolveProStatus(result: .inactive, cachedValue: nil) == false)
        #expect(resolveProStatus(result: .inactive, cachedValue: false) == false)
        #expect(resolveProStatus(result: .inactive, cachedValue: true) == false)
    }

    @Test
    func resolve_unavailable_preservesCache() {
        #expect(resolveProStatus(result: .unavailable, cachedValue: true) == true)
        #expect(resolveProStatus(result: .unavailable, cachedValue: false) == false)
    }

    @Test
    func resolve_unavailable_noCache_returnsFalse() {
        // キャッシュが無い（初回）状態での unavailable → false（安全側の初期値）
        #expect(resolveProStatus(result: .unavailable, cachedValue: nil) == false)
    }

    // MARK: - シナリオテスト（連続する状態遷移）

    @Test
    func scenario_activeThenUnavailable_maintainsTrue() {
        // 購入 → オフライン → Pro が維持されること
        let afterPurchase = resolveProStatus(result: .active, cachedValue: nil)
        #expect(afterPurchase == true)

        // オフライン（取得失敗）でも true が維持される
        let offline = resolveProStatus(result: .unavailable, cachedValue: afterPurchase)
        #expect(offline == true)
    }

    @Test
    func scenario_activeThenInactive_returnsFalse() {
        // 購入 → 返金 → false になること
        let afterPurchase = resolveProStatus(result: .active, cachedValue: nil)
        #expect(afterPurchase == true)

        // 返金
        let refunded = resolveProStatus(result: .inactive, cachedValue: afterPurchase)
        #expect(refunded == false)
    }

    @Test
    func scenario_unavailableThenActive_recovers() {
        // 初回オフライン → オンライン復帰 → true になること
        let first = resolveProStatus(result: .unavailable, cachedValue: nil)
        #expect(first == false)

        // オンライン復帰で購入確認
        let recovered = resolveProStatus(result: .active, cachedValue: first)
        #expect(recovered == true)
    }

    // MARK: - 一時無料開放（#72 Phase2）

    @Test
    func gate_openWhenUnlockActive() {
        // 開放フラグが有効なら無料ユーザーも Pro 機能にアクセスできる（実質 Pro）
        #expect(isFeatureGateOpen(isPro: false, isPromotionalUnlockActive: true) == true)
        #expect(isFeatureGateOpen(isPro: true, isPromotionalUnlockActive: true) == true)
    }

    @Test
    func gate_closedWhenUnlockInactive() {
        // 開放フラグが無効なら通常の分類に従う
        #expect(isFeatureGateOpen(isPro: false, isPromotionalUnlockActive: false) == false)
        #expect(isFeatureGateOpen(isPro: true, isPromotionalUnlockActive: false) == true)
    }

    @Test
    func gate_pureFunction_isDeterministic() {
        // 同一入力 → 同一出力（単一フラグで開閉できる）
        for unlock in [true, false] {
            for pro in [true, false] {
                let a = isFeatureGateOpen(isPro: pro, isPromotionalUnlockActive: unlock)
                let b = isFeatureGateOpen(isPro: pro, isPromotionalUnlockActive: unlock)
                #expect(a == b)
            }
        }
    }

    // MARK: - EntitlementResult Equatable

    @Test
    func entitlementResult_equality() {
        #expect(EntitlementResult.active == EntitlementResult.active)
        #expect(EntitlementResult.inactive == EntitlementResult.inactive)
        #expect(EntitlementResult.unavailable == EntitlementResult.unavailable)
        #expect(EntitlementResult.active != EntitlementResult.inactive)
    }

    // MARK: - ProDebugForce（Release では常に false）

    @Test
    func proDebugForce_returnsBool() {
        // DEBUG ビルドでは UserDefaults 依存、Release では false
        // いずれにせよ Bool が返ることのみ検証
        let _ = ProDebugForce.isEnabled()
    }
}
