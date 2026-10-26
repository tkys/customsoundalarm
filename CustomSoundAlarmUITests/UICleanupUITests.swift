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

    func testSoundPickerHasNoRecentSectionOrPlusMenu() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10))

        let soundRow = app.buttons["addAlarm.soundRow"]
        XCTAssertTrue(soundRow.waitForExistence(timeout: 5))
        soundRow.tap()

        let navBar = app.navigationBars["サウンド"]
        XCTAssertTrue(navBar.waitForExistence(timeout: 5), "sound picker should open")

        XCTAssertFalse(app.staticTexts["最近使った"].exists, "最近使ったセクションは削除済み")
        XCTAssertEqual(
            navBar.buttons.count,
            1,
            "サウンド選択のナビゲーションバーは戻るボタンだけ（＋メニューなし）。実際: \(navBar.buttons.allElementsBoundByIndex.map(\.label))"
        )
        XCTAssertEqual(app.buttons.matching(identifier: "soundPicker.addVideo").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "soundPicker.addAudio").count, 1)
    }
}
