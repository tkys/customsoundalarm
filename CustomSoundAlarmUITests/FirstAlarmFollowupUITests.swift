import XCTest

/// 初めての1回きりアラームが鳴って止まったあとの提案（#247）。
final class FirstAlarmFollowupUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(seeded: Bool, extra: [String] = []) {
        app = XCUIApplication()
        var arguments = [
            "-uitest-force-light",
            "-uitest-skip-alarm-sync",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        if seeded {
            arguments.append("-uitest-seed-first-followup")
        }
        app.launchArguments = arguments + extra
        app.launch()
    }

    private func find(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private var hasFollowupButtons: Bool {
        find("alarm.followup.tomorrow").exists
            || find("alarm.followup.weekdays").exists
            || find("alarm.followup.everyday").exists
    }

    func testWeekdaysTurnsOnRepeatingAndNeverShowsAgain() {
        launch(seeded: true)
        XCTAssertTrue(find("alarm.row").waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(
            find("alarm.followup.weekdays").waitForExistence(timeout: 10),
            "three follow-up buttons should appear: \(app.debugDescription)"
        )
        XCTAssertTrue(find("alarm.followup.tomorrow").exists)
        XCTAssertTrue(find("alarm.followup.everyday").exists)
        // 押すまでアラームは何も変えない
        XCTAssertEqual(app.switches["alarm.toggle"].value as? String, "0")

        find("alarm.followup.weekdays").tap()

        XCTAssertFalse(hasFollowupButtons)
        XCTAssertTrue(
            app.staticTexts["Weekdays"].waitForExistence(timeout: 5),
            "the alarm should become a weekday repeat: \(app.debugDescription)"
        )
        XCTAssertEqual(app.switches["alarm.toggle"].value as? String, "1")

        // 2回目以降は出ない
        app.terminate()
        launch(seeded: false)
        XCTAssertTrue(find("alarm.row").waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(
            find("alarm.followup.weekdays").waitForExistence(timeout: 3),
            "the follow-up must not appear again: \(app.debugDescription)"
        )
    }

    func testLeavingTheListWithoutTappingNeverShowsAgain() {
        launch(seeded: true)
        XCTAssertTrue(
            find("alarm.followup.tomorrow").waitForExistence(timeout: 15),
            app.debugDescription
        )

        // 設定を開く = 一覧を離れる
        app.buttons["alarmList.settings"].tap()
        XCTAssertTrue(find("settings.close").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons.matching(identifier: "settings.close").firstMatch.tap()
        XCTAssertTrue(find("alarm.row").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(hasFollowupButtons)

        app.terminate()
        launch(seeded: false)
        XCTAssertTrue(find("alarm.row").waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(
            find("alarm.followup.tomorrow").waitForExistence(timeout: 3),
            "ignored follow-up must not appear again: \(app.debugDescription)"
        )
    }
}
