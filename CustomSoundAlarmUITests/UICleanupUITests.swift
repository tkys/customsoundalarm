import XCTest

@MainActor
final class UICleanupUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launchList() {
        app.launchArguments = [
            "-uitest-seed-alarms",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["06:24"].waitForExistence(timeout: 10))
    }

    func testAlarmRowSwitchHasAccessibleName() {
        launchList()

        let rowSwitch = app.switches["06:24 アラーム"]
        XCTAssertTrue(
            rowSwitch.waitForExistence(timeout: 5),
            "アラーム行のスイッチの読み上げ名は完全一致で「06:24 アラーム」であるべき。実際のスイッチ: \(app.switches.allElementsBoundByIndex.map(\.label))"
        )
    }

    func testNightModeAndAddButtonsHaveLabels() {
        launchList()

        XCTAssertTrue(
            app.buttons["ナイトモード"].waitForExistence(timeout: 5),
            "月のボタンは「ナイトモード」と読み上げるべき"
        )
        XCTAssertTrue(
            app.navigationBars.buttons["アラームを追加"].waitForExistence(timeout: 5),
            "＋ボタンは「アラームを追加」と読み上げるべき"
        )
    }
}
