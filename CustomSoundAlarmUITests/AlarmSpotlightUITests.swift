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
        Thread.sleep(forTimeInterval: 0.8)
        assertRowInsideBars("11:00")

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
        attach("bottom-edge-11-00")
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
        assertRowInsideBars("23:50")
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

        let newRow = app.staticTexts["4:00"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 15), app.debugDescription)
        let deadline = Date().addingTimeInterval(5)
        while !newRow.isHittable && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(newRow.isHittable, app.debugDescription)
        Thread.sleep(forTimeInterval: 0.8)
        attach("top-edge-04-00")
        assertRowInsideBars("4:00")

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
        let existing = app.staticTexts["5:30"]
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

        let newRow = app.staticTexts["5:45"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 15), app.debugDescription)
        let deadline = Date().addingTimeInterval(5)
        while !newRow.isHittable && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(newRow.isHittable, app.debugDescription)
        assertRowInsideBars("5:45")

        // 入る行より上にある行は動かない（スクロールしていない）
        let after = existing.frame.midY
        XCTAssertEqual(
            after,
            before,
            accuracy: 2.0,
            "rows above the inserted row should not move: before=\(before) after=\(after)"
        )
    }


    /// 画面外の中ほど（上）に入れるときも、最小限だけ送ってバーに重ねない（#282 レビュー）。
    func testAddingAlarmInTheMiddleOutsideViewportScrollsToIt() {
        launch([
            "-uitest-seed-morning-alarms",
            "-uitest-add-time=06:15",
            "-uitest-save-alarm-disabled"
        ])
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        // 06:15 が画面の外・上に来るよう、一覧を下まで送る
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

        let predicate = NSPredicate(
            format: "label == %@ OR label == %@",
            "06:15",
            "6:15"
        )
        let newRow = app.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(newRow.waitForExistence(timeout: 15), app.debugDescription)
        let deadline = Date().addingTimeInterval(5)
        while !newRow.isHittable && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(newRow.isHittable, app.debugDescription)
        Thread.sleep(forTimeInterval: 0.8)
        assertFrameInsideBars(newRow.frame)

        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(
            newRow.frame.minY,
            window.height * 0.5,
            "middle row should stop near the top: \(newRow.frame)"
        )
    }

    /// 一覧が短い（2本）ときは、最後の行をスクロールせずその場で開いて見せる（#282 レビュー）。
    func testAddingLatestAlarmToShortListRevealsWithoutScrolling() {
        launch([
            "-uitest-seed-two-alarms",
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

        let newRow = app.staticTexts["23:50"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 15), app.debugDescription)
        // 開く動き（高さ）が終わるまで待ってから位置を見る
        Thread.sleep(forTimeInterval: 2.0)
        assertRowInsideBars("23:50")

        let after = existing.frame.midY
        XCTAssertEqual(
            after,
            before,
            accuracy: 2.0,
            "short list should not scroll: before=\(before) after=\(after)"
        )
        XCTAssertLessThan(
            newRow.frame.maxY,
            app.tabBars.firstMatch.frame.minY - 8,
            "new row should be fully inside the list: \(newRow.frame)"
        )
    }

    /// 広告枠が出ていても、最下段の行が枠に重ならない（#282 レビュー）。
    func testAddingLatestAlarmStaysAboveAdSlot() {
        launch([
            "-uitest-seed-morning-alarms",
            "-uitest-add-time=11:00",
            "-uitest-save-alarm-disabled",
            "-uitest-force-ad-slot"
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

        let newRow = app.staticTexts["11:00"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 15), app.debugDescription)
        let deadline = Date().addingTimeInterval(5)
        while !newRow.isHittable && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(newRow.isHittable, app.debugDescription)
        Thread.sleep(forTimeInterval: 0.8)

        let ad = app.descendants(matching: .any)["adSlot.banner_alarm_list"].firstMatch
        XCTAssertTrue(ad.waitForExistence(timeout: 5), app.debugDescription)
        let row = rowElement(containing: "11:00")
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        print("ADROW row=\(row.frame) ad=\(ad.frame)")
        XCTAssertLessThan(
            row.frame.maxY,
            ad.frame.minY - 8,
            "row should be above the ad slot: row=\(row.frame) ad=\(ad.frame)"
        )
        assertFrameInsideBars(row.frame)
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

    /// 行そのもの（セルの余白を含まないボタン）を返す。
    private func rowElement(containing text: String) -> XCUIElement {
        let button = app.buttons.containing(.staticText, identifier: text).firstMatch
        let cell = app.cells.containing(.staticText, identifier: text).firstMatch
        return button.exists ? button : cell
    }

    /// 行の frame がナビゲーションバー／タブバーに重なっていないことを数値で確認する。
    private func assertFrameInsideBars(
        _ rowFrame: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let nav = app.navigationBars.firstMatch
        let tab = app.tabBars.firstMatch
        XCTAssertTrue(nav.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(tab.exists, app.debugDescription, file: file, line: line)
        let navFrame = nav.frame
        let tabFrame = tab.frame
        print("ROWFRAME row=\(rowFrame) nav=\(navFrame) tab=\(tabFrame)")
        XCTAssertGreaterThan(
            rowFrame.minY,
            navFrame.maxY + 8,
            "row should be below the navigation bar: row=\(rowFrame) nav=\(navFrame)",
            file: file,
            line: line
        )
        XCTAssertLessThan(
            rowFrame.maxY,
            tabFrame.minY - 8,
            "row should be above the tab bar: row=\(rowFrame) tab=\(tabFrame)",
            file: file,
            line: line
        )
    }

    private func assertRowInsideBars(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let row = rowElement(containing: text)
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        assertFrameInsideBars(row.frame, file: file, line: line)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
