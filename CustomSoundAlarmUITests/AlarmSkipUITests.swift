import XCTest

/// 休みの画面（#197 画面作り直し）。
///
/// 一覧右上の目覚まし時計＋禁止マーク → 24時間 → 上部の1行 → 取り消し、
/// 行の右スワイプ → 次の1回を休む → 行の案内 → 取り消し。
final class AlarmSkipUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchSkipSeed() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uitest-seed-skip",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()
        return app
    }

    func testSkipAllPresetShowsNoticeAndUndoRestores() {
        let app = launchSkipSeed()

        let bell = app.buttons["alarmList.skipAll"]
        XCTAssertTrue(
            bell.waitForExistence(timeout: 15),
            "bell should appear: \(app.debugDescription)"
        )
        bell.tap()

        let preset = app.buttons["skipAll.preset.24h"]
        XCTAssertTrue(
            preset.waitForExistence(timeout: 10),
            "skip-all sheet should open: \(app.debugDescription)"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["skipAll.silencedList"]
                .waitForExistence(timeout: 5),
            "silenced alarm rows should appear before applying"
        )
        XCTAssertTrue(
            app.staticTexts["skipAll.oneTimeWarning"].waitForExistence(timeout: 5),
            "one-time warning should appear when a one-time alarm is in range"
        )

        preset.tap()

        let notice = app.staticTexts["skipAll.notice"]
        XCTAssertTrue(
            notice.waitForExistence(timeout: 10),
            "rest notice should appear: \(app.debugDescription)"
        )
        let gridLine = app.staticTexts["skip.row.globalSummary"].firstMatch
        XCTAssertTrue(
            gridLine.waitForExistence(timeout: 10),
            "included alarm rows should show the global rest line: \(app.debugDescription)"
        )
        let undo = app.buttons["skipAll.undo"]
        XCTAssertTrue(undo.exists, "undo should appear: \(app.debugDescription)")

        undo.tap()
        XCTAssertFalse(
            notice.waitForExistence(timeout: 5),
            "notice should disappear after undo"
        )
        XCTAssertTrue(bell.waitForExistence(timeout: 5), "bell should remain")
        XCTAssertFalse(
            app.staticTexts["skip.row.globalSummary"].firstMatch.exists,
            "global rest line should disappear after undo"
        )
    }

    func testLeadingSwipeSkipsNextAndShowsRowSummary() {
        let app = launchSkipSeed()

        let row = app.cells.firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "alarm row should appear: \(app.debugDescription)"
        )
        row.swipeRight()

        let skip = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "skip.row.skip.")
        ).firstMatch
        XCTAssertTrue(
            skip.waitForExistence(timeout: 10),
            "skip swipe action should appear: \(app.debugDescription)"
        )
        XCTAssertFalse(
            skip.label.contains("次") || skip.label.contains("明日"),
            "swipe action should use a date, not 次/明日: \(skip.label)"
        )
        skip.tap()

        let skippedToast = app.staticTexts.matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "skip.row.toast",
                "鳴らしません"
            )
        ).firstMatch
        XCTAssertTrue(
            skippedToast.waitForExistence(timeout: 5),
            "skipping one alarm should show the short notice: \(app.debugDescription)"
        )

        let summary = app.staticTexts["skip.row.summary"].firstMatch
        XCTAssertTrue(
            summary.waitForExistence(timeout: 10),
            "row should show the skipped date and the next date: \(app.debugDescription)"
        )

        row.swipeRight()
        let undo = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "skip.row.undo.")
        ).firstMatch
        XCTAssertTrue(
            undo.waitForExistence(timeout: 10),
            "undo swipe action should appear: \(app.debugDescription)"
        )
        undo.tap()
        let undoneToast = app.staticTexts.matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "skip.row.toast",
                "鳴らします"
            )
        ).firstMatch
        XCTAssertTrue(
            undoneToast.waitForExistence(timeout: 5),
            "undoing one alarm should show the short notice: \(app.debugDescription)"
        )
        XCTAssertFalse(
            summary.waitForExistence(timeout: 5),
            "row summary should disappear after undo"
        )
    }

    func testCustomDatesApplyAndShowNotice() {
        let app = launchSkipSeed()

        let bell = app.buttons["alarmList.skipAll"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15))
        bell.tap()

        let custom = app.buttons["skipAll.custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 10))
        custom.tap()

        XCTAssertTrue(
            app.otherElements["skipCalendar.root"].waitForExistence(timeout: 10)
                || app.descendants(matching: .any)["skipCalendar.root"]
                    .waitForExistence(timeout: 5),
            "calendar should open: \(app.debugDescription)"
        )
        let apply = app.buttons["skipCalendar.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        XCTAssertTrue(apply.isEnabled, "initial start/end should be valid")
        apply.tap()

        XCTAssertTrue(
            app.staticTexts["skipAll.notice"].waitForExistence(timeout: 10),
            "custom rest should show the notice: \(app.debugDescription)"
        )
        app.buttons["skipAll.undo"].tap()
        XCTAssertFalse(
            app.staticTexts["skipAll.notice"].waitForExistence(timeout: 5),
            "custom rest should be undone so later tests start clean"
        )
    }

    func testHolidayToggleInRepeatScreenSavesAndShowsInList() {
        let app = launchJapaneseSeed()
        openFirstAlarmRepeatScreen(app)

        let holiday = app.switches["addAlarm.holidaySkip"]
        XCTAssertTrue(
            holiday.waitForExistence(timeout: 10),
            "holiday toggle should be in the repeat screen: \(app.debugDescription)"
        )
        // List の行はラベル側をタップしても切り替わらないことがあるため、
        // 右端のスイッチを押す。
        holiday.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        // 同じ曜日のアラームがあるときの提案は、このアラームだけにする。
        let onlyThis = app.buttons["このアラームだけ"]
        XCTAssertTrue(
            onlyThis.waitForExistence(timeout: 10),
            "holiday offer should appear: \(app.debugDescription)"
        )
        onlyThis.tap()
        XCTAssertEqual(holiday.value as? String, "1")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10))
        app.buttons["addAlarm.save"].tap()

        XCTAssertTrue(
            app.staticTexts["holiday.summary"].firstMatch.waitForExistence(timeout: 15),
            "saved holiday setting should show on the alarm row: \(app.debugDescription)"
        )
    }

    func testDateSkipFromRepeatScreenShowsRowNotice() {
        let app = launchJapaneseSeed()
        openFirstAlarmRepeatScreen(app)

        let skipDates = app.buttons["addAlarm.skipDates"]
        XCTAssertTrue(
            skipDates.waitForExistence(timeout: 10),
            "date-skip row should be in the repeat screen: \(app.debugDescription)"
        )
        skipDates.tap()

        let today = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "今日")
        ).firstMatch
        XCTAssertTrue(
            today.waitForExistence(timeout: 10),
            "calendar should open: \(app.debugDescription)"
        )
        today.tap()
        app.buttons["skipDates.close"].tap()

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10))
        app.buttons["addAlarm.save"].tap()

        XCTAssertTrue(
            app.staticTexts["skip.row.summary"].firstMatch.waitForExistence(timeout: 15),
            "saved date skip should show on the alarm row: \(app.debugDescription)"
        )
    }

    private func launchJapaneseSeed() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uitest-seed-skip",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["alarmList.skipAll"].waitForExistence(timeout: 20))
        return app
    }

    private func openFirstAlarmRepeatScreen(_ app: XCUIApplication) {
        let firstRow = app.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10))
        firstRow.tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 20),
            "edit screen should open: \(app.debugDescription)"
        )
        let repeatRow = app.buttons["addAlarm.repeatRow"]
        XCTAssertTrue(repeatRow.waitForExistence(timeout: 10))
        repeatRow.tap()
        XCTAssertTrue(
            app.buttons["repeat.day.1"].waitForExistence(timeout: 10),
            "repeat screen should open: \(app.debugDescription)"
        )
    }

    func testRepeatResultListTogglesHolidayAndRemovesPickedDate() {
        let app = launchJapaneseSeed()
        openFirstAlarmRepeatScreen(app)

        // 先に日付を選ぶ（結果リストに「選んだ日」を出す）。
        let skipDates = app.buttons["addAlarm.skipDates"]
        XCTAssertTrue(skipDates.waitForExistence(timeout: 10))
        skipDates.tap()
        let today = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "今日")
        ).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        today.tap()
        app.buttons["skipDates.close"].tap()

        // 祝日をオンにする。
        let holiday = app.switches["addAlarm.holidaySkip"]
        scrollTo(holiday, app: app)
        holiday.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let onlyThis = app.buttons["このアラームだけ"]
        if onlyThis.waitForExistence(timeout: 10) {
            onlyThis.tap()
        }

        // 選んだ日の行を左スワイプで外す。
        let picked = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "skipResult.picked.")
        ).firstMatch
        scrollTo(picked, app: app)
        XCTAssertTrue(picked.waitForExistence(timeout: 10))
        picked.swipeLeft()
        let remove = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "skipResult.remove.")
        ).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()
        XCTAssertFalse(
            picked.waitForExistence(timeout: 5),
            "picked date should be removed from the result list"
        )

        // 祝日行の右端をタップして「鳴る」に変える。
        let status = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "skipResult.toggle.")
        ).firstMatch
        scrollTo(status, app: app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "鳴らない")
        status.tap()
        XCTAssertEqual(status.label, "鳴る")
    }

    private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < 14 {
            app.swipeUp()
            swipes += 1
        }
    }
}
