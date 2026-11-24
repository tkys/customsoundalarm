import XCTest

/// 保存直後・オンにしたときに、光っている行の2行目へ
/// 次に鳴るまでの1文が出て数秒で戻る（#289）。
@MainActor
final class UntilRingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(
        _ arguments: [String],
        language: [String] = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
    ) {
        app.terminate()
        app.launchArguments = arguments + [
            "-uitest-expose-until-ring"
        ] + language
        app.launch()
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 20),
            app.debugDescription
        )
    }

    private var notice: XCUIElement {
        app.staticTexts["alarm.row.untilRing"]
    }

    private func rowCell(containing time: String) -> XCUIElement {
        app.cells.containing(.staticText, identifier: time).firstMatch
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

    private func assertSameFrame(
        _ before: CGRect,
        _ after: CGRect,
        _ message: String
    ) {
        XCTAssertEqual(after.minY, before.minY, accuracy: 1, message)
        XCTAssertEqual(after.height, before.height, accuracy: 1, message)
    }

    /// 新規保存で、その行の2行目が文に変わり、数秒で戻る。
    func testSavingNewAlarmShowsNextRingInRowThenRestoresMetadata() {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized",
            "-uitest-add-time=11:00"
        ])

        openAddAndSave()

        XCTAssertTrue(
            notice.waitForExistence(timeout: 15),
            "next ring should appear in the saved row: \(app.debugDescription)"
        )
        XCTAssertTrue(
            rowCell(containing: "11:00").exists,
            app.debugDescription
        )
        XCTAssertTrue(
            notice.waitForNonExistence(timeout: 8),
            "next ring should return to the metadata after a few seconds: \(app.debugDescription)"
        )
    }

    /// 一覧でスイッチをオンにした行にも出て、数秒で戻る。
    func testTurningAlarmOnShowsNextRingInThatRowThenHides() {
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
            "next ring should appear in the row that was turned on: \(app.debugDescription)"
        )
        XCTAssertTrue(
            notice.waitForNonExistence(timeout: 8),
            "next ring should return to the metadata after a few seconds: \(app.debugDescription)"
        )
    }

    /// 続けて別の行をオンにしたら、前の行はすぐ戻り、新しい行に出る。
    func testTurningAnotherAlarmOnMovesNoticeToTheNewRow() {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized"
        ])

        let firstCell = rowCell(containing: "6:24")
        let secondCell = rowCell(containing: "23:44")
        XCTAssertTrue(firstCell.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(secondCell.exists, app.debugDescription)

        let toggles = app.switches.matching(identifier: "alarm.toggle")
        XCTAssertTrue(toggles.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        toggles.element(boundBy: 0).tap()
        XCTAssertTrue(
            firstCell.staticTexts["alarm.row.untilRing"].waitForExistence(timeout: 5),
            "first row should show the notice: \(app.debugDescription)"
        )

        toggles.element(boundBy: 1).tap()
        XCTAssertTrue(
            secondCell.staticTexts["alarm.row.untilRing"].waitForExistence(timeout: 5),
            "second row should show the notice: \(app.debugDescription)"
        )
        XCTAssertFalse(
            firstCell.staticTexts["alarm.row.untilRing"].exists,
            "first row should return to the metadata: \(app.debugDescription)"
        )
    }

    /// 文が出る前後で、その行と下の行の高さ・位置が変わらない（#289）。
    func testRowFramesDoNotChangeWhileNoticeAppearsAndDisappears() {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized"
        ])

        let row = rowCell(containing: "6:24")
        let nextRow = rowCell(containing: "23:44")
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(nextRow.exists, app.debugDescription)
        let rowBefore = row.frame
        let nextBefore = nextRow.frame

        let toggle = app.switches["alarm.toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), app.debugDescription)
        toggle.tap()

        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        assertSameFrame(rowBefore, row.frame, "the row should keep its height and position")
        assertSameFrame(nextBefore, nextRow.frame, "the next row should not move")

        XCTAssertTrue(notice.waitForNonExistence(timeout: 8), app.debugDescription)
        assertSameFrame(rowBefore, row.frame, "the row should return to the same frame")
        assertSameFrame(nextBefore, nextRow.frame, "the next row should not move")
    }

    /// AX サイズ（縦並び）でも、文が出る前後で行の高さ・位置が変わらない。
    func testRowFramesDoNotChangeAtAccessibilitySize() {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])

        let row = rowCell(containing: "6:24")
        let nextRow = rowCell(containing: "23:44")
        XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(nextRow.exists, app.debugDescription)
        let rowBefore = row.frame
        let nextBefore = nextRow.frame

        let toggle = app.switches["alarm.toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), app.debugDescription)
        toggle.tap()

        XCTAssertTrue(notice.waitForExistence(timeout: 5), app.debugDescription)
        assertSameFrame(rowBefore, row.frame, "the AX row should keep its height")
        assertSameFrame(nextBefore, nextRow.frame, "the next AX row should not move")

        XCTAssertTrue(notice.waitForNonExistence(timeout: 8), app.debugDescription)
        assertSameFrame(rowBefore, row.frame, "the AX row should return to the same frame")
        assertSameFrame(nextBefore, nextRow.frame, "the next AX row should not move")
    }

    /// 文は1行だけで、別の説明を足さない（#289）。
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
        afterMinutes: Int,
        extraArguments: [String] = []
    ) {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized",
            "-uitest-hold-until-ring",
            "-uitest-add-time=\(timeString(afterMinutes: afterMinutes))"
        ] + extraArguments, language: language)
        openAddAndSave()
        XCTAssertTrue(notice.waitForExistence(timeout: 15), app.debugDescription)
        Thread.sleep(forTimeInterval: 1.2)
        attach(name)
    }

    private func captureWeekday(
        language: [String],
        name: String,
        extraArguments: [String] = []
    ) {
        launch([
            "-uitest-seed-two-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-alarm-permission-authorized",
            "-uitest-hold-until-ring",
            "-uitest-add-time=07:30"
        ] + extraArguments, language: language)
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
        Thread.sleep(forTimeInterval: 1.2)
        attach(name)
    }

    func testCaptureScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["UNTIL_RING_SCREENSHOTS"] == "1",
            "Until-ring screenshots run only with TEST_RUNNER_UNTIL_RING_SCREENSHOTS=1"
        )

        let ja = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        let enUS = ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        let ax = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]

        captureDuration(language: ja, name: "until-ring-ja", afterMinutes: 7 * 60 + 26)
        captureDuration(language: enUS, name: "until-ring-en-us", afterMinutes: 26)
        captureDuration(
            language: ja,
            name: "until-ring-dark-ja",
            afterMinutes: 7 * 60 + 26,
            extraArguments: ["-uitest-force-dark"]
        )
        captureDuration(
            language: ja,
            name: "until-ring-ax-ja",
            afterMinutes: 7 * 60 + 26,
            extraArguments: ax
        )
        captureWeekday(language: ja, name: "until-ring-ja-weekday")
        captureWeekday(language: enUS, name: "until-ring-en-us-weekday")
    }
}
