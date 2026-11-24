import XCTest

/// 時刻の書き方と大きさの比較スクショ（#283・手動実行）。
@MainActor
final class AlarmTimeFormatScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String], expectsAddScreen: Bool = false) {
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        if expectsAddScreen {
            XCTAssertTrue(
                app.collectionViews["addAlarm.root"].waitForExistence(timeout: 20),
                app.debugDescription
            )
        } else {
            XCTAssertTrue(
                app.buttons["alarmList.add"].waitForExistence(timeout: 20),
                app.debugDescription
            )
        }
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureAll() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ALARM_TIME_SCREENSHOTS"] == "1",
            "Alarm time screenshots run only with TEST_RUNNER_ALARM_TIME_SCREENSHOTS=1"
        )

        let ja = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        let enUS = ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        let enGB = ["-AppleLanguages", "(en-GB)", "-AppleLocale", "en_GB"]

        launch(["-uitest-seed-alarms"] + ja)
        attach("alarm-time-ja")

        launch(["-uitest-seed-alarms"] + enUS)
        attach("alarm-time-en-us")

        launch(["-uitest-seed-alarms"] + enGB)
        attach("alarm-time-en-gb")

        launch(
            ["-uitest-seed-alarms", "-uitest-open-add-alarm", "-uitest-add-time=17:30"] + enUS,
            expectsAddScreen: true
        )
        attach("alarm-time-en-us-add")

        launch([
            "-uitest-seed-alarms",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ] + ja)
        attach("alarm-time-ax-ja")

        launch([
            "-uitest-seed-alarms",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ] + enUS)
        attach("alarm-time-ax-en-us")

        launch(["-uitest-seed-alarms", "-uitest-force-dark"] + ja)
        attach("alarm-time-dark-ja")

        // ナイトモードの時計も端末の書き方に従う（#283）
        launch(["-uitest-seed-alarms"] + enUS)
        app.buttons["alarmList.settings"].tap()
        app.buttons["settings.bedside"].tap()
        XCTAssertTrue(
            app.otherElements["bedside.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        Thread.sleep(forTimeInterval: 1.2)
        attach("alarm-time-bedside-en-us")

        launch(["-uitest-seed-alarms"] + ja)
        app.buttons["alarmList.settings"].tap()
        app.buttons["settings.bedside"].tap()
        XCTAssertTrue(
            app.otherElements["bedside.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        Thread.sleep(forTimeInterval: 1.2)
        attach("alarm-time-bedside-ja")
    }
}
