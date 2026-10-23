import XCTest

final class AlarmListUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-alarms"]
    }

    func testAlarmListSortedByTime() {
        app.launch()
        // List should show times in ascending order 06:24, 18:00, 23:44
        let time1 = app.staticTexts["06:24"]
        let time2 = app.staticTexts["18:00"]
        let time3 = app.staticTexts["23:44"]
        XCTAssertTrue(time1.waitForExistence(timeout: 5), "06:24 should be visible")
        XCTAssertTrue(time2.waitForExistence(timeout: 2))
        XCTAssertTrue(time3.waitForExistence(timeout: 2))

        // Verify vertical order by Y coordinate
        let y1 = time1.frame.origin.y
        let y2 = time2.frame.origin.y
        let y3 = time3.frame.origin.y
        XCTAssertTrue(y1 < y2, "06:24 should be above 18:00 (y1=\(y1) y2=\(y2))")
        XCTAssertTrue(y2 < y3, "18:00 should be above 23:44 (y2=\(y2) y3=\(y3))")
    }

    func testSwipeDeleteRemovesTappedRow() {
        app.launch()
        let time1 = app.staticTexts["06:24"]
        XCTAssertTrue(time1.waitForExistence(timeout: 5))

        // Find the cell containing 06:24 and swipe to delete
        // List rows are cells; find the cell that contains the time
        let cell = app.cells.containing(.staticText, identifier: "06:24").firstMatch
        // Fallback: find via table
        let targetCell: XCUIElement
        if cell.waitForExistence(timeout: 2) {
            targetCell = cell
        } else {
            // Alternative: find the button containing the time
            targetCell = app.buttons.containing(.staticText, identifier: "06:24").firstMatch
        }
        XCTAssertTrue(targetCell.waitForExistence(timeout: 2), "Cell for 06:24 should exist")
        targetCell.swipeLeft()

        let deleteButton = app.buttons["Delete"].firstMatch
        // Japanese locale fallback
        let deleteJa = app.buttons["削除"].firstMatch
        if deleteButton.waitForExistence(timeout: 2) {
            deleteButton.tap()
        } else if deleteJa.waitForExistence(timeout: 2) {
            deleteJa.tap()
        } else {
            XCTFail("Delete button should appear after swipe")
        }

        // 06:24 should disappear, 18:00 and 23:44 remain
        XCTAssertFalse(time1.waitForExistence(timeout: 2), "06:24 should be deleted")
        XCTAssertTrue(app.staticTexts["18:00"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["23:44"].waitForExistence(timeout: 2))
    }
}
