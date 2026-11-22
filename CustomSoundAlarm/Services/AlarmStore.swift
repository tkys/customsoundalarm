import Foundation
import os

/// アラーム設定の管理（保存・読み込み・削除）
@Observable
@MainActor
final class AlarmStore {
    static let shared = AlarmStore()

    private let logger = Logger(subsystem: "com.tkysdev.customsoundalarm", category: "AlarmStore")
    private let key = "saved_alarms"

    private(set) var alarms: [AlarmEntry] = []

    /// データ変更検知用（reload 前後で比較し、変化があった場合のみ sync するために使用）
    private(set) var contentHash: Int = 0

    private init() {
        load()
    }

    func add(_ alarm: AlarmEntry) {
        alarms.append(alarm)
        save()
    }

    func update(_ alarm: AlarmEntry) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index] = alarm
        save()
    }

    /// 複数件をまとめて置き換える（休みの一括適用・#197）。
    func replaceAll(_ newAlarms: [AlarmEntry]) {
        alarms = newAlarms
        save()
    }

    /// 複数件をまとめて削除する（#282 レビュー）。
    /// 一覧のスワイプ削除で、保存と `alarms` の変更を1回にまとめる。
    func remove(_ targets: [AlarmEntry]) {
        guard !targets.isEmpty else { return }
        let ids = Set(targets.map(\.id))
        for alarm in targets {
            let context = AlarmHistoryLogic.context(for: alarm)
            AnalyticsService.shared.capture(.alarmDeletedWithContext(context: context))
        }
        alarms.removeAll { ids.contains($0.id) }
        save()
        // 全体の休みの対象からも外す（#197 画面作り直し）
        if var skip = AppGroup.globalSkip {
            skip.entryIDs.removeAll { ids.contains($0) }
            skip.disabledOneTimeIDs.removeAll { ids.contains($0) }
            AppGroup.globalSkip = skip.entryIDs.isEmpty ? nil : skip
        }
    }

    func remove(_ alarm: AlarmEntry) {
        remove([alarm])
    }

    /// アラームを複製する。新しい id・`isEnabled = true` で追加し、
    /// 元のアラームの設定（時刻/ラベル/繰り返し/サウンド）を引き継ぐ。
    func duplicate(_ alarm: AlarmEntry) {
        let copy = alarm.duplicated()
        AlarmUIDStore.recordCreation(copy.id)
        let context = AlarmHistoryLogic.context(for: copy)
        alarms.append(copy)
        save()

        AnalyticsService.shared.capture(.alarmDuplicatedWithContext(context: context))
    }

    func toggleEnabled(_ alarm: AlarmEntry, recordEvent: Bool = true) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        let listBefore = alarms
        alarms[index].isEnabled.toggle()
        if alarms[index].isEnabled {
            // 休みで止めた1回だけのアラームを、手動でオンに戻した（#197 レビュー）
            alarms[index].skipDisabledDate = nil
            // 全体の休みの最中にオンにし直したアラームは鳴らす（#197 画面作り直し）
            if var skip = AppGroup.globalSkip {
                skip.entryIDs.removeAll { $0 == alarms[index].id }
                skip.disabledOneTimeIDs.removeAll { $0 == alarms[index].id }
                AppGroup.globalSkip = skip.entryIDs.isEmpty ? nil : skip
            }
        }
        save()
        if recordEvent {
            var context = AlarmHistoryLogic.context(for: alarms[index])
            context.list = AlarmHistoryLogic.listSnapshot(listBefore)
            AnalyticsService.shared.capture(.alarmToggled(
                enabled: alarms[index].isEnabled,
                daysSinceCreated: AlarmHistoryLogic.daysSinceCreated(alarmID: alarm.id),
                context: context
            ))
        }
    }

    /// 外部変更（Share Extension等）後にデータを再読み込み
    /// - Returns: データが変更されたかどうか
    @discardableResult
    func reload() -> Bool {
        let oldHash = contentHash
        load()
        return contentHash != oldHash
    }

    // MARK: - Persistence

    private func load() {
        guard let data = AppGroup.userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AlarmEntry].self, from: data) else {
            return
        }
        // 過ぎた休み・祝日の上書きは読み込み時に落とす（#197）
        let pruned = decoded.map { AlarmSkipLogic.pruning($0, now: Date()) }
        alarms = pruned
        if pruned != decoded {
            save()
        } else {
            contentHash = data.hashValue
        }
        logger.info("Loaded \(self.alarms.count) alarms")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        AppGroup.userDefaults.set(data, forKey: key)
        contentHash = data.hashValue
    }

#if DEBUG
    /// UIテスト用: 保存済みアラームをクリア
    func resetForUITest() {
        alarms = []
        AppGroup.userDefaults.removeObject(forKey: key)
        contentHash = 0
    }
#endif
}
