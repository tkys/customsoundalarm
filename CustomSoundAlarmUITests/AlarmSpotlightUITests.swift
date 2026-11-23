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
        // 一番遅い時刻は一覧の自然な下端に入る（400ptの余白を足さない）
        XCTAssertGreaterThan(
            newRow.frame.maxY,
            window.height * 0.7,
            "new row should sit at the bottom: \(newRow.frame)"
        )
        XCTAssertLessThan(
            newRow.frame.maxY,
            window.height - 20,
            "new row should not be clipped by the tab bar: \(newRow.frame)"
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


    /// 連続で3本追加しても落ちない（#282 レビュー）。
    func testAddingThreeAlarmsInARowDoesNotCrash() {
        launch([
            "-uitest-seed-morning-alarms",
            "-uitest-add-time=11:00",
            "-uitest-save-alarm-disabled"
        ])
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            app.debugDescription
        )

        for _ in 0..<3 {
            app.buttons["alarmList.add"].tap()
            let addRoot = app.collectionViews["addAlarm.root"]
            XCTAssertTrue(
                addRoot.waitForExistence(timeout: 10),
                app.debugDescription
            )
            let save = app.buttons["addAlarm.save"]
            XCTAssertTrue(save.waitForExistence(timeout: 5), app.debugDescription)
            let ready = Date().addingTimeInterval(2)
            while !save.isHittable && Date() < ready {
                Thread.sleep(forTimeInterval: 0.05)
            }
            save.tap()
            XCTAssertTrue(
                addRoot.waitForNonExistence(timeout: 10),
                app.debugDescription
            )
            // 次の追加までに、スクロール/行の挿入が始まるのを少し待つ
            Thread.sleep(forTimeInterval: 0.4)
        }

        // 連続追加は落ちないことが目的（見た目の着地は #198 のまとめ追加で扱う）
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 5),
            app.debugDescription
        )
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }


    /// 画面の外・上（一番早い時刻）に追加すると、上端に少し余白を残して止まる（#282 レビュー）。
    func testAddingAlarmAboveTheViewportScrollsUpToIt() {
        launch([
            "-uitest-seed-morning-alarms",
            "-uitest-add-time=04:00",
            "-uitest-save-alarm-disabled"
        ])
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            app.debugDescription
        )

        // 04:00 が画面の外・上に来るよう、一覧を下まで送っておく
        for _ in 0..<3 {
            app.swipeUp()
        }
        app.buttons["alarmList.add"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10),
            app.debugDescription
        )
        app.buttons["addAlarm.save"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForNonExistence(timeout: 10),
            app.debugDescription
        )

        let newRow = app.staticTexts["04:00"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 15), app.debugDescription)
        let deadline = Date().addingTimeInterval(5)
        while !newRow.isHittable && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(newRow.isHittable, app.debugDescription)

        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(
            newRow.frame.minY,
            window.height * 0.4,
            "new row should stop near the top: \(newRow.frame)"
        )
        XCTAssertGreaterThan(
            newRow.frame.minY,
            window.height * 0.05,
            "new row should keep a small inset at the top: \(newRow.frame)"
        )
    }


    /// すでに見えている位置（3本目と4本目のあいだ）に入れるときは、
    /// スクロールせず、その場で開いて光る（#282 レビュー）。
    func testAddingAlarmInTheMiddleDoesNotScroll() {
        launch([
            "-uitest-seed-morning-alarms",
            "-uitest-add-time=05:45",
            "-uitest-save-alarm-disabled"
        ])
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        let existing = app.staticTexts["05:30"]
        XCTAssertTrue(existing.waitForExistence(timeout: 15), app.debugDescription)
        let before = existing.frame.midY

        app.buttons["alarmList.add"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10),
            app.debugDescription
        )
        app.buttons["addAlarm.save"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForNonExistence(timeout: 10),
            app.debugDescription
        )

        let newRow = app.staticTexts["05:45"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 15), app.debugDescription)
        let deadline = Date().addingTimeInterval(5)
        while !newRow.isHittable && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(newRow.isHittable, app.debugDescription)

        // 入る行より上にある行は動かない（スクロールしていない）
        let after = existing.frame.midY
        XCTAssertEqual(
            after,
            before,
            accuracy: 2.0,
            "rows above the inserted row should not move: before=\(before) after=\(after)"
        )
    }

    /// 追加直後（光っている間）に削除しても落ちない（#282 レビュー）。
    func testDeletingImmediatelyAfterAddingDoesNotCrash() {
        launch([
            "-uitest-seed-alarms",
            "-uitest-add-time=23:50",
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
            app.debugDescription
        )

        let newTime = app.staticTexts["23:50"]
        XCTAssertTrue(newTime.waitForExistence(timeout: 15), app.debugDescription)
        let deadline = Date().addingTimeInterval(5)
        while !newTime.isHittable && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(newTime.isHittable, "new row should be inserted: \(app.debugDescription)")

        let cell = app.cells.containing(.staticText, identifier: "23:50").firstMatch
        let target = cell.exists
            ? cell
            : app.buttons.containing(.staticText, identifier: "23:50").firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        target.swipeLeft()

        let delete = app.buttons["削除"].firstMatch
        let deleteEn = app.buttons["Delete"].firstMatch
        if delete.waitForExistence(timeout: 2) {
            delete.tap()
        } else if deleteEn.waitForExistence(timeout: 2) {
            deleteEn.tap()
        } else {
            XCTFail("Delete button should appear: \(app.debugDescription)")
        }

        XCTAssertFalse(
            app.staticTexts["23:50"].waitForExistence(timeout: 3),
            "deleted row should disappear"
        )
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
