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
        // 初回起動のアラーム許可ダイアログを閉じる（#272 スクショ用）
        let springboardForPermission = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<5 {
            var tapped = false
            for label in ["許可", "Allow"] {
                if springboardForPermission.buttons[label].exists {
                    springboardForPermission.buttons[label].tap()
                    tapped = true
                    break
                }
            }
            if tapped { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
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
        Thread.sleep(forTimeInterval: 3.0)
        attach("control-gallery-opened")

        // 検索バーをタップして「Alarm」で絞り込む
        springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.145)
        ).tap()
        Thread.sleep(forTimeInterval: 0.8)
        springboard.typeText("Alarm")
        Thread.sleep(forTimeInterval: 2.0)
        attach("control-gallery-search")

        // 検索結果の「My Sound Alarm」をタップして Control Center に追加する
        springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.15, dy: 0.33)
        ).tap()
        Thread.sleep(forTimeInterval: 2.0)
        attach("control-center-after-add")

        // 編集モードを抜けて、実際にコントロールを押してアプリが開くか確認する
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2.0)
        let springboard2 = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let start2 = springboard2.coordinate(
            withNormalizedOffset: CGVector(dx: 0.95, dy: 0.01)
        )
        let end2 = springboard2.coordinate(
            withNormalizedOffset: CGVector(dx: 0.95, dy: 0.6)
        )
        start2.press(
            forDuration: 0.3,
            thenDragTo: end2,
            withVelocity: .fast,
            thenHoldForDuration: 0.2
        )
        Thread.sleep(forTimeInterval: 2.0)
        attach("control-center-reopened")
        // マイナスバッジではなく、コントロールの中央を押す
        springboard2.coordinate(
            withNormalizedOffset: CGVector(dx: 0.17, dy: 0.20)
        ).tap()
        Thread.sleep(forTimeInterval: 2.0)
        attach("control-pressed")
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "control should open the app: \(springboard2.debugDescription)"
        )
        attach("control-opened-app")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 追加コントロールを押して追加画面が開くことのスクショ（手動実行用・#272）。
    func testCaptureAddControlPress() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CONTROL_CENTER_SCREENSHOTS"] == "1",
            "Control Center screenshots run only with TEST_RUNNER_CONTROL_CENTER_SCREENSHOTS=1"
        )
        app.launchArguments = ["-uitest-seed-alarms"]
        app.launch()
        XCTAssertTrue(app.buttons["alarmList.add"].waitForExistence(timeout: 15))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<5 {
            var tapped = false
            for label in ["許可", "Allow"] {
                if springboard.buttons[label].exists {
                    springboard.buttons[label].tap()
                    tapped = true
                    break
                }
            }
            if tapped { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 1.0)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2.0)

        let start = springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.95, dy: 0.01)
        )
        let end = springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.95, dy: 0.6)
        )
        start.press(
            forDuration: 0.3,
            thenDragTo: end,
            withVelocity: .fast,
            thenHoldForDuration: 0.2
        )
        Thread.sleep(forTimeInterval: 2.0)
        springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.12, dy: 0.045)
        ).tap()
        Thread.sleep(forTimeInterval: 1.5)
        let addControl = springboard.buttons["Add a Control"]
        XCTAssertTrue(addControl.waitForExistence(timeout: 5), springboard.debugDescription)
        addControl.tap()
        Thread.sleep(forTimeInterval: 3.0)
        springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.145)
        ).tap()
        Thread.sleep(forTimeInterval: 0.8)
        springboard.typeText("Alarm")
        Thread.sleep(forTimeInterval: 2.0)
        // 2つ目の「Add Alarm」を追加
        springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.38, dy: 0.33)
        ).tap()
        Thread.sleep(forTimeInterval: 2.0)

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2.0)
        let springboard2 = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let start2 = springboard2.coordinate(
            withNormalizedOffset: CGVector(dx: 0.95, dy: 0.01)
        )
        let end2 = springboard2.coordinate(
            withNormalizedOffset: CGVector(dx: 0.95, dy: 0.6)
        )
        start2.press(
            forDuration: 0.3,
            thenDragTo: end2,
            withVelocity: .fast,
            thenHoldForDuration: 0.2
        )
        Thread.sleep(forTimeInterval: 2.0)
        attach("add-control-center")
        springboard2.coordinate(
            withNormalizedOffset: CGVector(dx: 0.17, dy: 0.20)
        ).tap()
        Thread.sleep(forTimeInterval: 2.0)
        attach("add-control-pressed")
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            "add control should open the add screen: \(springboard2.debugDescription)"
        )
        attach("add-control-opened-app")
    }
}
