import Foundation
import StoreKit
import os

// MARK: - EntitlementResult

/// 課金権利の取得結果。3分岐（罠1）。
enum EntitlementResult: Sendable, Equatable {
    /// Pro 権利が確認できた（購入済み・有効）
    case active
    /// Pro 権利が明示的に無い（未購入・返金済み）
    case inactive
    /// 取得自体が失敗（ネットワーク等）。キャッシュを維持すべき
    case unavailable
}

// MARK: - EntitlementStore protocol

/// 課金権利の取得を抽象化するプロトコル。
/// `AnalyticsBackend` と同じ作法で、テスト時は StoreKit に依存せず
/// フェイク実装で3分岐を検証できる。
protocol EntitlementStore: Sendable {
    func currentProEntitlement() async -> EntitlementResult
    func purchasePro() async throws -> EntitlementResult
    func restorePurchases() async throws -> EntitlementResult
}

// MARK: - resolveProStatus（純粋関数・罠1）

/// `EntitlementResult` とキャッシュ値から新しい `isPro` を決定する純粋関数。
///
/// 3分岐:
/// - `.active` → `true`（キャッシュを更新）
/// - `.inactive` → `false`（キャッシュを更新）
/// - `.unavailable` → **キャッシュ維持**（fail-open。オフラインで Pro を失わせない）
///
/// キャッシュが `nil`（初回）で `.unavailable` の場合は `false`（安全側の初期値）。
func resolveProStatus(result: EntitlementResult, cachedValue: Bool?) -> Bool {
    switch result {
    case .active:
        return true
    case .inactive:
        return false
    case .unavailable:
        // キャッシュがあれば維持、無ければ false（初期値）
        return cachedValue ?? false
    }
}

// MARK: - ProDebugForce（DEBUG 強制ON・#28 と同じ作法）

/// DEBUG ビルドでのみ `ProDebugForceEnabled` UserDefault を参照し、
/// Release ビルドでは常に `false` を返す。
/// Release で強制ONする手段は存在しない（#28 と同じく `#else` で定数を与える）。
enum ProDebugForce {
    #if DEBUG
    /// DEBUG ビルド: UserDefaults の `ProDebugForceEnabled` が true なら強制ON
    static func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: "ProDebugForceEnabled")
    }
    #else
    /// Release ビルド: 常に false（強制ONの手段は存在しない）
    static func isEnabled() -> Bool { false }
    #endif
}

// MARK: - AppGroup cache key

extension AppGroup {
    /// Pro 権利のキャッシュ（オフライン時の fail-open 用）
    static var proEntitlementCached: Bool? {
        get {
            if userDefaults.object(forKey: "pro_entitlement_cached") == nil { return nil }
            return userDefaults.bool(forKey: "pro_entitlement_cached")
        }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: "pro_entitlement_cached")
            } else {
                userDefaults.removeObject(forKey: "pro_entitlement_cached")
            }
        }
    }
}

// MARK: - PromotionalUnlock（一時無料開放・#72 Phase2）

/// 一時無料開放の判定（純粋関数・単体テスト対象）。
/// 課金導線が未実装の間、Pro フェイス・Pro カラーを全ユーザーへ開放する。
/// `isPromotionalUnlockActive` が true の間は実質 Pro 扱い。
/// 閉じるときは `Entitlements.isPromotionalUnlockActive` を false に戻すだけで良い
/// （ClockLayout.isPro / ColorTheme.isPro の分類と available(isPro:) は残す）。
func isFeatureGateOpen(isPro: Bool, isPromotionalUnlockActive: Bool) -> Bool {
    isPromotionalUnlockActive || isPro
}

// MARK: - Entitlements

/// 課金権利の単一の情報源。
/// 機能側は `Entitlements.shared.isPro` のみを見る。
///
/// 罠1: `Transaction.currentEntitlements` の取得に失敗したときは
/// キャッシュを維持し `isPro` を `false` に落とさない（fail-open）。

/// 商品ID（非消耗型・買い切り）。nonisolated で広域参照可能。
private let proProductID = "com.tkysdev.customsoundalarm.pro"

@Observable
@MainActor
final class Entitlements {
    static let shared = Entitlements()

    /// 一時無料開放フラグ（#72 Phase2）。
    /// 課金導線実装までの間 true。閉じるときはここを false に戻すだけ。
    /// 分類・ゲートのコード（isPro / available(isPro:)）は削除しないこと。
    static let isPromotionalUnlockActive = true

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "Entitlements")

    /// 機能側が参照する唯一のプロパティ
    private(set) var isPro: Bool

    /// 機能ゲートの最終判定。available(isPro:) に渡す値。
    /// 一時開放中は実質 true（単一フラグで開閉できる）。
    var effectiveIsPro: Bool {
        isFeatureGateOpen(isPro: isPro, isPromotionalUnlockActive: Self.isPromotionalUnlockActive)
    }

    /// 権利取得のバックエンド（本番: StoreKit / テスト: フェイク）
    private let store: EntitlementStore

    /// Transaction.updates 監視タスク
    private var updatesTask: Task<Void, Never>?

    init(store: EntitlementStore = StoreKitEntitlementStore()) {
        self.store = store

        // キャッシュから初期値を復元
        let cached = AppGroup.proEntitlementCached
        self.isPro = cached ?? false

        // DEBUG 強制ON（Release では ProDebugForce.isEnabled() は常に false）
        if ProDebugForce.isEnabled() {
            self.isPro = true
            logger.info("Pro debug force enabled")
        }
    }

    // MARK: - Refresh

    /// 権利状態を最新化する。アプリ起動時・ foreground 復帰時・購入後に呼ぶ。
    func refresh() async {
        let result = await store.currentProEntitlement()
        let cached = AppGroup.proEntitlementCached
        let newPro = resolveProStatus(result: result, cachedValue: cached)

        // DEBUG 強制ON がある場合は isPro を上書きしない
        let forceEnabled = ProDebugForce.isEnabled()
        if !forceEnabled {
            isPro = newPro
        }

        // キャッシュ更新（.unavailable は維持）
        if !forceEnabled {
            switch result {
            case .active, .inactive:
                AppGroup.proEntitlementCached = newPro
            case .unavailable:
                break
            }
        }

        logger.info("Entitlement refresh: result=\(String(describing: result)), cached=\(String(describing: cached)), isPro=\(self.isPro)")
    }

    // MARK: - Purchase

    /// Pro を購入する。
    /// - Returns: 購入成功 → `.active`、失敗 → それ以外
    @discardableResult
    func purchase() async -> EntitlementResult {
        do {
            let result = try await store.purchasePro()
            await refresh()
            return result
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription)")
            return .unavailable
        }
    }

    // MARK: - Restore

    /// App Store に同期を要求し、購入履歴を復元する。
    func restore() async {
        do {
            _ = try await store.restorePurchases()
            await refresh()
        } catch {
            logger.error("Restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Transaction.updates 監視

    /// `Transaction.updates` の監視を開始する（購入・返金・家族共有の即時反映）。
    /// アプリ起動時に1度だけ呼ぶ。
    func startObservingUpdates() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard !Task.isCancelled else { break }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refresh()
                }
            }
        }
    }

    func stopObservingUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
    }
}

// MARK: - StoreKitEntitlementStore（本番実装）

/// `EntitlementStore` の本番実装。StoreKit 2 を叩く。
struct StoreKitEntitlementStore: EntitlementStore {

    func currentProEntitlement() async -> EntitlementResult {
        do {
            let hasPro = try await hasActiveProEntitlement()
            return hasPro ? .active : .inactive
        } catch {
            return .unavailable
        }
    }

    func purchasePro() async throws -> EntitlementResult {
        let products = try await Product.products(for: [proProductID])
        guard let product = products.first else {
            // 商品が未登録（ASC に未配置の段階）
            return .inactive
        }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                return .active
            }
            return .inactive
        case .userCancelled:
            return .inactive
        case .pending:
            return .inactive
        @unknown default:
            return .inactive
        }
    }

    func restorePurchases() async throws -> EntitlementResult {
        try await AppStore.sync()
        let hasPro = try await hasActiveProEntitlement()
        return hasPro ? .active : .inactive
    }

    // MARK: - Private

    /// `Transaction.currentEntitlements` を走査し、Pro 商品の有効な取引があるか確認する。
    private func hasActiveProEntitlement() async throws -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == proProductID {
                return true
            }
        }
        return false
    }
}