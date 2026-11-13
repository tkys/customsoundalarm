import XCTest

/// 休みの画面（#197 画面作り直し）。
///
/// 一覧右上の bell.slash → 24時間 → 上部の1行 → 取り消し、
/// 行の右スワイプ → 次の1回を休む → 行の案内 → 取り消し。
final class AlarmSkipUITests: XCTestCase {

    private func launchSkipSeed() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-skip"]
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
            app.staticTexts["skipAll.summary"].waitForExistence(timeout: 5),
            "summary should appear before applying"
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
        let undo = app.buttons["skipAll.undo"]
        XCTAssertTrue(undo.exists, "undo should appear: \(app.debugDescription)")

        undo.tap()
        XCTAssertFalse(
            notice.waitForExistence(timeout: 5),
            "notice should disappear after undo"
        )
        XCTAssertTrue(bell.waitForExistence(timeout: 5), "bell should remain")
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
}
