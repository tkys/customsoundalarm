import XCTest

@MainActor
final class EmptyStateQuickAlarmUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func findElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// 空の一覧で 7:00 を押すと、一覧に 7:00 のアラームが1本できる（#231）。
    func testQuickTimeCreatesAlarm() {
        app.launchArguments = [
            "-uitest-clear-alarms",
            "-uitest-reset-sounds",
            "-uitest-force-light",
            "-uitest-alarm-permission-authorized",
            "-uitest-skip-alarm-sync",
            "-uitest-expose-until-ring"
        ]
        app.launch()

        XCTAssertTrue(
            findElement("emptyState.root").waitForExistence(timeout: 15),
            "empty state should appear: \(app.debugDescription)"
        )
        let button = findElement("emptyState.quick.7_00")
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        button.tap()

        XCTAssertTrue(
            app.staticTexts["alarm.row.untilRing"].waitForExistence(timeout: 5),
            "next ring should appear after creating a quick alarm: \(app.debugDescription)"
        )
        XCTAssertTrue(
            app.staticTexts["7:00"].waitForExistence(timeout: 15),
            "quick alarm should appear in the list: \(app.debugDescription)"
        )
    }

    /// 「ほかの時刻」は今の追加画面を開く。
    func testOtherTimeOpensAddAlarm() {
        app.launchArguments = [
            "-uitest-clear-alarms",
            "-uitest-reset-sounds",
            "-uitest-force-light"
        ]
        app.launch()

        let other = findElement("emptyState.other")
        XCTAssertTrue(other.waitForExistence(timeout: 15), app.debugDescription)
        other.tap()

        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            "add alarm should open: \(app.debugDescription)"
        )
    }
}
