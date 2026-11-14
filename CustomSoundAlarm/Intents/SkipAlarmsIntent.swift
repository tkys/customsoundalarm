import AppIntents
import Foundation

/// 日付でアラームを休む AppIntent（#197）。
///
/// いまは画面から同じ処理（`AlarmSkipService`）を呼んでいる。
/// あとでウィジェット・コントロールセンター・ショートカットから呼べるように、
/// 処理そのものを Intent から切り離しておく。
/// パラメータの説明がまだ無いため、ショートカットの一覧には出さない。
struct SkipAlarmsIntent: AppIntent {
    static let title: LocalizedStringResource = "skip_alarms_intent"
    static let isDiscoverable = false

    @Parameter(title: "Scope")
    var scope: String

    @Parameter(title: "Date")
    var date: Date?

    @Parameter(title: "End Date")
    var endDate: Date?

    @Parameter(title: "Alarm IDs")
    var alarmIDs: [String]?

    init() {
        self.scope = AlarmSkipScope.day.rawValue
    }

    init(scope: AlarmSkipScope, date: Date?, endDate: Date? = nil, alarmIDs: [String]? = nil) {
        self.scope = scope.rawValue
        self.date = date
        self.endDate = endDate
        self.alarmIDs = alarmIDs
    }

    func perform() async throws -> some IntentResult {
        let scope = AlarmSkipScope(rawValue: self.scope) ?? .day
        let date = self.date ?? Date()
        let endDate = self.endDate
        let ids = Set((alarmIDs ?? []).compactMap(UUID.init(uuidString:)))

        await MainActor.run {
            switch scope {
            case .day:
                let entries = AlarmSkipLogic.entries(
                    firingOn: date,
                    among: AlarmStore.shared.alarms
                )
                AlarmSkipService.skipDay(date, entries: entries)
            case .selected:
                AlarmSkipService.skipSelected(ids, date: date)
            case .range:
                AlarmSkipService.skipRange(from: date, to: endDate ?? date)
            }
        }
        return .result()
    }
}
