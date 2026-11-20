import XCTest

/// コントロールセンターからの起動（#272）。
/// コントロール自体はシミュレータで操作しづらいため、
/// 同じ処理を起動引数で流して着地先を確認する。
@MainActor
final class ControlOpenUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String]) {
        app.launchArguments = arguments + [
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()
    }

    func testControlListOpensAlarmTab() {
        // ライブラリから始めても、コントロールの「一覧」でアラームタブへ移る
        launch(["-uitest-seed-alarms", "-uitest-open-library", "-uitest-control-list"])
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            "alarm list should open: \(app.debugDescription)"
        )
        XCTAssertFalse(app.collectionViews["addAlarm.root"].exists)
    }

    func testControlAddOpensAddScreen() {
        launch(["-uitest-seed-alarms", "-uitest-open-library", "-uitest-control-add"])
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 20),
            "add screen should open: \(app.debugDescription)"
        )
    }

    func testControlAddDuringOnboardingDoesNotOpenAddScreen() {
        launch(["-uitest-fresh-onboarding", "-uitest-control-add"])
        XCTAssertTrue(
            app.buttons["onboarding.next"].waitForExistence(timeout: 15),
            "onboarding should be shown: \(app.debugDescription)"
        )
        XCTAssertFalse(app.collectionViews["addAlarm.root"].exists)
    }

    /// コントロールセンターの検索結果・配置のスクショ（手動実行用・#272）。
    func testCaptureControlCenter() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CONTROL_CENTER_SCREENSHOTS"] == "1",
            "Control Center screenshots run only with TEST_RUNNER_CONTROL_CENTER_SCREENSHOTS=1"
        )
        app.launchArguments = ["-uitest-seed-alarms"]
        app.launch()
        XCTAssertTrue(app.buttons["alarmList.add"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.0)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let start = springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.95, dy: 0.01)
        )
        let end = springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)
        )
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
        Thread.sleep(forTimeInterval: 2.0)
        attach("control-center-opened")

        // 左上の「+」→「Add a Control」でコントロールギャラリーを開く
        springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.12, dy: 0.045)
        ).tap()
        Thread.sleep(forTimeInterval: 1.5)
        let addControl = springboard.buttons["Add a Control"]
        XCTAssertTrue(addControl.waitForExistence(timeout: 5), springboard.debugDescription)
        addControl.tap()
        Thread.sleep(forTimeInterval: 2.0)
        attach("control-gallery-opened")

        let search = springboard.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Alarm")
            Thread.sleep(forTimeInterval: 2.0)
            attach("control-gallery-search")

            // 検索結果の「My Sound Alarm」をタップして Control Center に追加する
            springboard.coordinate(
                withNormalizedOffset: CGVector(dx: 0.15, dy: 0.315)
            ).tap()
            Thread.sleep(forTimeInterval: 2.0)
            attach("control-center-after-add")
        }
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
