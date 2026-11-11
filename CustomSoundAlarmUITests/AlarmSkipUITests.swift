import XCTest

/// 日付で休む → 表示 → 取り消し（#197）。
final class AlarmSkipUITests: XCTestCase {

    func testSkipDayShowsNoticeAndUndoRestores() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-design-audit"]
        app.launch()

        let skipDay = app.buttons["skip.day"]
        XCTAssertTrue(
            skipDay.waitForExistence(timeout: 15),
            "skip day button should appear: \(app.debugDescription)"
        )
        skipDay.tap()

        let notice = app.descendants(matching: .any)["skip.notice"]
        XCTAssertTrue(
            notice.waitForExistence(timeout: 10),
            "skip notice should appear: \(app.debugDescription)"
        )
        let undo = app.buttons["skip.undo"]
        XCTAssertTrue(undo.exists, "undo button should appear: \(app.debugDescription)")

        undo.tap()
        XCTAssertTrue(
            skipDay.waitForExistence(timeout: 10),
            "undo should bring the day group back"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["skip.notice"].exists,
            "notice should disappear after undo"
        )
    }

    func testSelectionAndRangeSheetsOpen() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-design-audit"]
        app.launch()

        let select = app.buttons["skip.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 15))
        select.tap()
        XCTAssertTrue(
            app.buttons["skipSelect.apply"].waitForExistence(timeout: 10),
            "selection sheet should open: \(app.debugDescription)"
        )
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let range = app.buttons["skip.range"]
        XCTAssertTrue(range.waitForExistence(timeout: 10))
        range.tap()
        XCTAssertTrue(
            app.buttons["skipRange.apply"].waitForExistence(timeout: 10),
            "range sheet should open: \(app.debugDescription)"
        )
    }
}
