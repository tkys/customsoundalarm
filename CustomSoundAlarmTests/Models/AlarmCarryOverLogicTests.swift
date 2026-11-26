import Testing
import Foundation
@testable import CustomSoundAlarm

/// 新規アラームの引き継ぎと時刻の候補（#206）。
struct AlarmCarryOverLogicTests {

    private let playlistID = UUID()

    // MARK: - 引き継ぎ

    @Test
    func carryOverWithoutPreviousUsesDefaults() {
        let carryOver = AlarmCarryOverLogic.carryOver(
            from: nil,
            playlistExists: { _ in true }
        )

        #expect(carryOver == .defaults)
        #expect(carryOver.hasPrevious == false)
        #expect(carryOver.snoozeMinutes == 9)
        #expect(carryOver.playlistID == nil)
        #expect(carryOver.fadeIn == .off)
    }

    @Test
    func carryOverDropsDeletedPlaylist() {
        let snapshot = AlarmCarryOverSnapshot(
            snoozeMinutes: 5,
            playlistID: playlistID,
            fadeIn: .fifteen
        )

        let carryOver = AlarmCarryOverLogic.carryOver(
            from: snapshot,
            playlistExists: { _ in false }
        )

        #expect(carryOver.hasPrevious)
        #expect(carryOver.snoozeMinutes == 5)
        #expect(carryOver.playlistID == nil)
        #expect(carryOver.fadeIn == .fifteen)
    }

    @Test
    func carryOverKeepsExistingPlaylistAndValues() {
        let snapshot = AlarmCarryOverSnapshot(
            snoozeMinutes: 3,
            playlistID: playlistID,
            fadeIn: .thirty
        )

        let carryOver = AlarmCarryOverLogic.carryOver(
            from: snapshot,
            playlistExists: { $0 == self.playlistID }
        )

        #expect(carryOver.hasPrevious)
        #expect(carryOver.snoozeMinutes == 3)
        #expect(carryOver.playlistID == playlistID)
        #expect(carryOver.fadeIn == .thirty)
    }

    @Test
    func carriedOverIsFalseWhenValuesChanged() {
        let initial = AlarmCarryOver(
            hasPrevious: true,
            snoozeMinutes: 5,
            playlistID: playlistID,
            fadeIn: .five
        )

        #expect(AlarmCarryOverLogic.carriedOver(
            initial: initial,
            snoozeMinutes: 5,
            playlistID: playlistID,
            fadeIn: .five
        ))
        #expect(!AlarmCarryOverLogic.carriedOver(
            initial: initial,
            snoozeMinutes: 9,
            playlistID: playlistID,
            fadeIn: .five
        ))
        #expect(!AlarmCarryOverLogic.carriedOver(
            initial: initial,
            snoozeMinutes: 5,
            playlistID: nil,
            fadeIn: .five
        ))
        #expect(!AlarmCarryOverLogic.carriedOver(
            initial: initial,
            snoozeMinutes: 5,
            playlistID: playlistID,
            fadeIn: .off
        ))
    }

    @Test
    func carriedOverIsFalseWithoutPrevious() {
        #expect(!AlarmCarryOverLogic.carriedOver(
            initial: .defaults,
            snoozeMinutes: 9,
            playlistID: nil,
            fadeIn: .off
        ))
    }

    // MARK: - 時刻の候補

    @Test
    func suggestionsAreEmptyWithoutAlarms() {
        #expect(AlarmTimeSuggestionLogic.suggestions(
            entries: [],
            after: date(2026, 11, 17, 8, 0),
            calendar: calendar
        ).isEmpty)
    }

    @Test
    func suggestionsUseLatestAlarmOfEarliestNextDay() {
        // 6:00 は今日過ぎているので明日、23:00 は今日。次に鳴る日は今日で、
        // その日の一番遅い 23:00 から +5/+10 分を出す。
        let entries = [
            entry(hour: 6, minute: 0),
            entry(hour: 23, minute: 0)
        ]

        let suggestions = AlarmTimeSuggestionLogic.suggestions(
            entries: entries,
            after: date(2026, 11, 17, 8, 0),
            calendar: calendar
        )

        #expect(suggestions == [
            AlarmTimeSuggestion(hour: 23, minute: 5),
            AlarmTimeSuggestion(hour: 23, minute: 10)
        ])
    }

    @Test
    func suggestionsExcludeDisabledAlarms() {
        let entries = [
            entry(hour: 6, minute: 0),
            entry(hour: 23, minute: 58, isEnabled: false)
        ]

        let suggestions = AlarmTimeSuggestionLogic.suggestions(
            entries: entries,
            after: date(2026, 11, 17, 5, 0),
            calendar: calendar
        )

        #expect(suggestions == [
            AlarmTimeSuggestion(hour: 6, minute: 5),
            AlarmTimeSuggestion(hour: 6, minute: 10)
        ])
    }

    @Test
    func suggestionsRollOverMidnight() {
        let entries = [entry(hour: 23, minute: 58)]

        let suggestions = AlarmTimeSuggestionLogic.suggestions(
            entries: entries,
            after: date(2026, 11, 17, 8, 0),
            calendar: calendar
        )

        #expect(suggestions == [
            AlarmTimeSuggestion(hour: 0, minute: 3),
            AlarmTimeSuggestion(hour: 0, minute: 8)
        ])
        #expect(suggestions.map(\.label) == ["0:03", "0:08"])
    }

    @Test
    func suggestionLabelFollowsLocaleTimeStyle() {
        let suggestion = AlarmTimeSuggestion(hour: 23, minute: 5)

        let japanese = suggestion.label(
            locale: Locale(identifier: "ja_JP"),
            calendar: calendar
        )
        #expect(japanese == "23:05")

        let english = suggestion.label(
            locale: Locale(identifier: "en_US"),
            calendar: calendar
        )
        #expect(english.contains("11:05"))
        #expect(english.contains("PM"))
    }

    // MARK: - Helpers

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func entry(
        hour: Int,
        minute: Int,
        isEnabled: Bool = true
    ) -> AlarmEntry {
        AlarmEntry(
            hour: hour,
            minute: minute,
            isEnabled: isEnabled,
            label: "Alarm"
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

/// 「その他」1行の要約（#211）。
struct AlarmEditorMoreSummaryTests {

    private let strings = AlarmEditorMoreSummary.Strings(
        labelFormat: "Label: %@",
        noLabel: "No label",
        snoozeTitle: "Snooze",
        fadeTitle: "Gentle start",
        separator: " · ",
        accessibilityFormat: "%1$@, %2$@",
        moreTitle: "More"
    )

    private func make(
        label: String = "Alarm",
        snooze: Int = 9,
        fadeIn: PlaylistFadeIn = .off,
        fadeInAvailable: Bool = true
    ) -> AlarmEditorMoreSummary.Result {
        AlarmEditorMoreSummary.make(
            label: label,
            defaultLabel: "Alarm",
            snoozeMinutes: snooze,
            snoozeValue: "\(snooze) min",
            fadeIn: fadeIn,
            fadeValue: fadeIn == .off ? "Off" : "\(fadeIn.rawValue) sec",
            fadeInAvailable: fadeInAvailable,
            strings: strings
        )
    }

    @Test
    func untouchedShowsSnoozeDefaultOnly() {
        let result = make()
        #expect(result.displayItems == ["Snooze 9 min"])
        #expect(result.accessibilityText == "More, Snooze 9 min · No label")
    }

    @Test
    func customLabelComesFirst() {
        let result = make(label: "Gym")
        #expect(result.displayItems == ["Label: Gym", "Snooze 9 min"])
        #expect(result.accessibilityText == "More, Snooze 9 min · Label: Gym")
    }

    @Test
    func changedLabelAndSnoozeKeepChangedOrder() {
        let result = make(label: "Gym", snooze: 5)
        #expect(result.displayItems == ["Label: Gym", "Snooze 5 min"])
        #expect(result.accessibilityText == "More, Snooze 5 min · Label: Gym")
    }

    @Test
    func changedSnoozeOnlyIsNotDuplicated() {
        let result = make(snooze: 5)
        #expect(result.displayItems == ["Snooze 5 min"])
    }

    @Test
    func gentleStartIsSecondWhenLabelChanged() {
        let result = make(label: "Gym", fadeIn: .five)
        #expect(result.displayItems == ["Label: Gym", "Gentle start 5 sec"])
        #expect(
            result.accessibilityText
                == "More, Snooze 9 min · Label: Gym · Gentle start 5 sec"
        )
    }

    @Test
    func summaryKeepsAtMostTwoItems() {
        let result = make(label: "Gym", snooze: 5, fadeIn: .thirty)
        #expect(result.displayItems.count == 2)
        #expect(result.displayItems == ["Label: Gym", "Snooze 5 min"])
    }

    /// #312: 音がデフォルトで効かない間は、やさしく鳴り始めるを要約に残さない。
    @Test
    func gentleStartIsHiddenWhileUnavailable() {
        let result = make(label: "Gym", fadeIn: .fifteen, fadeInAvailable: false)
        #expect(result.displayItems == ["Label: Gym", "Snooze 9 min"])
        #expect(result.accessibilityText == "More, Snooze 9 min · Label: Gym")
    }

    @Test
    func whitespaceOnlyLabelIsTreatedAsNoLabel() {
        let result = make(label: "  \n")
        #expect(result.displayItems == ["Snooze 9 min"])
        #expect(result.accessibilityText == "More, Snooze 9 min · No label")
    }
}
