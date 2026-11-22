import XCTest

/// アラームを作った・時刻を変えたあとのスクロールとスポットライト（#282）。
@MainActor
final class AlarmSpotlightUITests: XCTestCase {

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

    /// 朝のアラーム10本の下に入る 11:00 を追加すると、行が画面内に入る。
    func testAddingAlarmOutsideViewportScrollsToIt() {
        launch([
            "-uitest-seed-morning-alarms",
            "-uitest-add-time=11:00",
            "-uitest-save-alarm-disabled"
        ])
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            app.debugDescription
        )
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

        let newRow = app.staticTexts["11:00"]
        XCTAssertTrue(
            newRow.waitForExistence(timeout: 15),
            "new row should be scrolled into view: \(app.debugDescription)"
        )
        XCTAssertTrue(newRow.isHittable, "new row should be visible")

        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(
            newRow.frame.midY,
            window.height * 0.2,
            "new row should not stick to the top: \(newRow.frame)"
        )
        XCTAssertLessThan(
            newRow.frame.midY,
            window.height * 0.8,
            "new row should not stick to the bottom: \(newRow.frame)"
        )
    }

    /// すでに見えている位置に追加したときは、一覧を動かさない。
    func testAddingAlarmAlreadyVisibleDoesNotScroll() {
        launch([
            "-uitest-seed-alarms",
            "-uitest-add-time=23:50",
            "-uitest-save-alarm-disabled"
        ])
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        let existing = app.staticTexts["23:44"]
        XCTAssertTrue(existing.waitForExistence(timeout: 10), app.debugDescription)
        let before = existing.frame.midY

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
        XCTAssertTrue(
            app.staticTexts["23:50"].waitForExistence(timeout: 15),
            "new row should appear: \(app.debugDescription)"
        )

        // スポットライトが終わるまで待ってから、保存前の位置のままかを見る。
        Thread.sleep(forTimeInterval: 2.0)
        let after = existing.frame.midY
        XCTAssertEqual(
            after,
            before,
            accuracy: 2.0,
            "visible row should not scroll: before=\(before) after=\(after)"
        )
    }

    /// スクロールと光りの録画・スクショ用（手動実行・#282）。
    func testCaptureSpotlightFlow() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SPOTLIGHT_SCREENSHOTS"] == "1",
            "Spotlight screenshots run only with TEST_RUNNER_SPOTLIGHT_SCREENSHOTS=1"
        )
        launch([
            "-uitest-seed-morning-alarms",
            "-uitest-add-time=11:00",
            "-uitest-save-alarm-disabled"
        ])
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        Thread.sleep(forTimeInterval: 0.8)
        attach("spotlight-01-list")

        app.buttons["alarmList.add"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10),
            app.debugDescription
        )
        Thread.sleep(forTimeInterval: 0.8)
        attach("spotlight-02-add")

        app.buttons["addAlarm.save"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForNonExistence(timeout: 10),
            app.debugDescription
        )
        // スクロール中（止まり際）と、光り終わったあと
        Thread.sleep(forTimeInterval: 0.62)
        attach("spotlight-03-rising")
        Thread.sleep(forTimeInterval: 2.0)
        attach("spotlight-04-list")
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
