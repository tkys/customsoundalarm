import XCTest

/// 保存直後・オンにしたときに、次に鳴るまでの1文が出て数秒で消える（#289）。
@MainActor
final class UntilRingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String], language: [String] = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]) {
        app.terminate()
        app.launchArguments = arguments + language
        app.launch()
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 20),
            app.debugDescription
        )
    }

    private var notice: XCUIElement {
        app.staticTexts["alarmList.untilRing"]
    }

    private func openAddAndSave() {
        app.buttons["alarmList.add"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10),
            app.debugDescription
        )
        app.buttons["addAlarm.save"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForNonExistence(timeout: 10),
            "add screen should close: \(app.debugDescription)"
        )
    }

    /// 新規保存で文が出て、数秒で消える。
    func testSavingNewAlarmShowsNextRingThenHides() {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized",
            "-uitest-add-time=11:00"
        ])

        openAddAndSave()

        XCTAssertTrue(
            notice.waitForExistence(timeout: 15),
            "next ring should appear: \(app.debugDescription)"
        )
        XCTAssertTrue(
            notice.waitForNonExistence(timeout: 8),
            "next ring should hide after a few seconds: \(app.debugDescription)"
        )
    }

    /// 一覧でスイッチをオンにしたときも文が出て、数秒で消える。
    func testTurningAlarmOnShowsNextRingThenHides() {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized"
        ])

        let toggle = app.switches["alarm.toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()

        XCTAssertTrue(
            notice.waitForExistence(timeout: 5),
            "next ring should appear after turning on: \(app.debugDescription)"
        )
        XCTAssertTrue(
            notice.waitForNonExistence(timeout: 8),
            "next ring should hide after a few seconds: \(app.debugDescription)"
        )
    }

    /// 文は1行だけで、アイコンや別の説明を足さない（#289）。
    func testNoticeIsASingleSentence() {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized"
        ])

        let toggle = app.switches["alarm.toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), app.debugDescription)
        toggle.tap()
        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)

        let text = notice.label
        XCTAssertTrue(text.contains("鳴ります"), text)
        XCTAssertFalse(text.contains("\n"), text)
    }

    // MARK: - スクリーンショット（手動実行・#289）

    private func timeString(afterMinutes minutes: Int) -> String {
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: date
        )
        return String(
            format: "%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureDuration(
        language: [String],
        name: String,
        afterMinutes: Int
    ) {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized",
            "-uitest-add-time=\(timeString(afterMinutes: afterMinutes))"
        ], language: language)
        openAddAndSave()
        XCTAssertTrue(notice.waitForExistence(timeout: 15), app.debugDescription)
        Thread.sleep(forTimeInterval: 0.6)
        attach(name)
    }

    private func captureWeekday(language: [String], name: String) {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized",
            "-uitest-add-time=07:30"
        ], language: language)
        app.buttons["alarmList.add"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10),
            app.debugDescription
        )

        // 3日後の曜日を選ぶ（必ず24時間以上先になる）
        let repeatRow = app.buttons["addAlarm.repeatRow"]
        XCTAssertTrue(repeatRow.waitForExistence(timeout: 10), app.debugDescription)
        var swipes = 0
        while !repeatRow.isHittable && swipes < 8 {
            app.collectionViews["addAlarm.root"].swipeUp()
            swipes += 1
        }
        repeatRow.tap()
        let weekday = Calendar.current.component(
            .weekday,
            from: Date().addingTimeInterval(3 * 24 * 60 * 60)
        )
        let day = app.buttons["repeat.day.\(weekday)"]
        XCTAssertTrue(day.waitForExistence(timeout: 10), app.debugDescription)
        day.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10),
            app.debugDescription
        )
        app.buttons["addAlarm.save"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForNonExistence(timeout: 10),
            app.debugDescription
        )
        XCTAssertTrue(notice.waitForExistence(timeout: 15), app.debugDescription)
        Thread.sleep(forTimeInterval: 0.6)
        attach(name)
    }

    func testCaptureScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["UNTIL_RING_SCREENSHOTS"] == "1",
            "Until-ring screenshots run only with TEST_RUNNER_UNTIL_RING_SCREENSHOTS=1"
        )

        let ja = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        let enUS = ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]

        captureDuration(language: ja, name: "until-ring-ja", afterMinutes: 7 * 60 + 26)
        captureDuration(language: enUS, name: "until-ring-en-us", afterMinutes: 26)
        captureWeekday(language: ja, name: "until-ring-ja-weekday")
        captureWeekday(language: enUS, name: "until-ring-en-us-weekday")
    }
}
