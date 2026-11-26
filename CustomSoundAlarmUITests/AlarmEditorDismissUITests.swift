import XCTest

/// #308: 追加・編集画面を、変更があるときだけ確認してから閉じる。
@MainActor
final class AlarmEditorDismissUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private var root: XCUIElement {
        app.collectionViews["addAlarm.root"]
    }

    private func findElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// iOS 26 のアクションシートは、cancel ロールの項目を出さず、
    /// 外側をタップしたときにその action を呼ぶ（純正のカレンダーと同じ）。
    private func tapOutsideConfirmation() {
        let outside = app.otherElements["PopoverDismissRegion"].firstMatch
        XCTAssertTrue(
            outside.waitForExistence(timeout: 5),
            "the confirmation should be open: \(app.debugDescription)"
        )
        outside.tap()
    }

    private func launchEdit() {
        app.launchArguments = [
            "-uitest-open-edit-alarm",
            "-uitest-skip-alarm-sync",
            "-uitest-force-light",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_GB"
        ]
        app.launch()
        XCTAssertTrue(root.waitForExistence(timeout: 15), app.debugDescription)
    }

    private func launchAdd() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-add-time=11:00",
            "-uitest-clear-alarms",
            "-uitest-disable-new-alarm",
            "-uitest-force-light",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_GB"
        ]
        app.launch()
        XCTAssertTrue(root.waitForExistence(timeout: 15), app.debugDescription)
    }

    /// 時刻のホイールを1つ進める。値は「07 o’clock」でも調整先は「09」。
    @discardableResult
    private func setHour(from oldHour: Int, to newHour: Int) -> Bool {
        let wheels = app.pickerWheels
        for index in 0..<wheels.count {
            let wheel = wheels.element(boundBy: index)
            let value = wheel.value as? String ?? ""
            let digits = value.prefix(while: \.isNumber)
            guard Int(digits) == oldHour else { continue }
            let target = digits.count == 2
                ? String(format: "%02d", newHour)
                : "\(newHour)"
            wheel.adjust(toPickerWheelValue: target)
            return true
        }
        return false
    }

    private func shownHour(_ hour: Int) -> Bool {
        let wheels = app.pickerWheels
        for index in 0..<wheels.count {
            let value = wheels.element(boundBy: index).value as? String ?? ""
            if Int(value.prefix(while: \.isNumber)) == hour { return true }
        }
        return false
    }

    private func assertSheetClosed() {
        XCTAssertTrue(
            root.waitForNonExistence(timeout: 10),
            "the editor should close: \(app.debugDescription)"
        )
    }

    /// 時刻を変えて「キャンセル」→ 確認 → 編集を続ける（外側をタップ）で残る
    /// →「変更を破棄」で閉じる。閉じたあと、一覧の時刻は元の 7:00 のまま。
    func testCancelWithChangesAsksBeforeDiscarding() {
        launchEdit()
        XCTAssertTrue(setHour(from: 7, to: 9), "hour wheel should be adjustable")
        XCTAssertTrue(shownHour(9), app.debugDescription)

        app.buttons["addAlarm.cancel"].tap()

        let discard = app.buttons.matching(
            NSPredicate(format: "label == 'Discard Changes'")
        ).firstMatch
        XCTAssertTrue(
            discard.waitForExistence(timeout: 5),
            "changing the time should ask before closing: \(app.debugDescription)"
        )
        // タイトル・説明文は出さない（確認の中身は2つだけ）
        XCTAssertEqual(app.popovers.firstMatch.staticTexts.count, 0)

        tapOutsideConfirmation()
        XCTAssertTrue(root.waitForExistence(timeout: 5), "keep editing should stay")
        XCTAssertTrue(shownHour(9), "the changed time should stay: \(app.debugDescription)")

        app.buttons["addAlarm.cancel"].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        discard.tap()

        assertSheetClosed()
        let row = findElement("alarm.row")
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(
            row.label.contains("7:00"),
            "discarding must keep the original time: \(row.label)"
        )
    }

    /// 変更がなければ、「キャンセル」でそのまま閉じる。
    func testCancelWithoutChangesClosesRightAway() {
        launchEdit()
        app.buttons["addAlarm.cancel"].tap()

        assertSheetClosed()
        XCTAssertFalse(app.buttons["Discard Changes"].exists)
        XCTAssertTrue(findElement("alarm.row").waitForExistence(timeout: 10))
    }

    /// 新規作成も同じ。初期値から変えたら確認を出す。
    func testNewAlarmWithChangesAsksBeforeDiscarding() {
        launchAdd()
        XCTAssertTrue(setHour(from: 11, to: 12), "hour wheel should be adjustable")
        XCTAssertTrue(shownHour(12), app.debugDescription)

        app.buttons["addAlarm.cancel"].tap()

        let discard = app.buttons.matching(
            NSPredicate(format: "label == 'Discard Changes'")
        ).firstMatch
        XCTAssertTrue(
            discard.waitForExistence(timeout: 5),
            "a changed new alarm should ask before closing: \(app.debugDescription)"
        )
        tapOutsideConfirmation()
        XCTAssertTrue(root.waitForExistence(timeout: 5))

        app.buttons["addAlarm.cancel"].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        discard.tap()

        assertSheetClosed()
    }

    /// 下に払っても、変更があるときは閉じずに同じ確認を出す。
    func testSwipeDownWithChangesAsksBeforeDiscarding() {
        launchEdit()
        XCTAssertTrue(setHour(from: 7, to: 9), "hour wheel should be adjustable")

        // シートの上端から下へ払う（行の上だとスクロールになる）
        swipeDownFromSheet()

        let discard = app.buttons.matching(
            NSPredicate(format: "label == 'Discard Changes'")
        ).firstMatch
        XCTAssertTrue(
            discard.waitForExistence(timeout: 5),
            "swiping down with changes should ask before closing: \(app.debugDescription)"
        )
        XCTAssertTrue(root.exists, "the editor should stay open")

        tapOutsideConfirmation()
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        XCTAssertTrue(shownHour(9))
    }

    // MARK: - 閉じたあとに、もう一度開ける（#308 レビュー）

    private func swipeDownFromSheet() {
        // シートの上端から下へ払う（行の上だとスクロールになる）
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.5, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    private func launchList() {
        app.launchArguments = [
            "-uitest-seed-alarms",
            "-uitest-skip-alarm-sync",
            "-uitest-force-light",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_GB"
        ]
        app.launch()
        XCTAssertTrue(
            findElement("alarm.row").waitForExistence(timeout: 15),
            app.debugDescription
        )
    }

    private func openFirstAlarmFromList() {
        let row = findElement("alarm.row")
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(
            root.waitForExistence(timeout: 10),
            "the edit screen should open: \(app.debugDescription)"
        )
    }

    /// 時刻のホイールを1時間進める（一覧の1本目の時刻に依存しない）。
    @discardableResult
    private func advanceHour() -> Bool {
        let wheel = app.pickerWheels.element(boundBy: 0)
        let value = wheel.value as? String ?? ""
        let digits = value.prefix(while: \.isNumber)
        guard let hour = Int(digits) else { return false }
        let next = (hour + 1) % 24
        let target = digits.count == 2 ? String(format: "%02d", next) : "\(next)"
        wheel.adjust(toPickerWheelValue: target)
        return true
    }

    /// 変更なしで払って閉じたあとも、同じアラームをもう一度開ける。
    func testSwipeDownWithoutChangesCanReopenTheSameAlarm() {
        launchList()
        openFirstAlarmFromList()

        swipeDownFromSheet()
        XCTAssertTrue(
            root.waitForNonExistence(timeout: 10),
            "the editor should close: \(app.debugDescription)"
        )
        XCTAssertFalse(app.buttons["Discard Changes"].exists)

        // 親の選択状態が残っていると、ここで開けない
        openFirstAlarmFromList()
    }

    /// 新規作成も、変更なしで払って閉じたあと「＋」からもう一度開ける。
    func testSwipeDownOnNewAlarmCanOpenItAgain() {
        launchList()
        app.buttons["alarmList.add"].tap()
        XCTAssertTrue(root.waitForExistence(timeout: 10), app.debugDescription)

        swipeDownFromSheet()
        XCTAssertTrue(
            root.waitForNonExistence(timeout: 10),
            "the editor should close: \(app.debugDescription)"
        )
        XCTAssertFalse(app.buttons["Discard Changes"].exists)

        app.buttons["alarmList.add"].tap()
        XCTAssertTrue(
            root.waitForExistence(timeout: 10),
            "add should open again: \(app.debugDescription)"
        )
    }

    /// 変更ありで払って「変更を破棄」で閉じたあとも、同じアラームをもう一度開ける。
    func testDiscardingChangesThenReopeningTheSameAlarm() {
        launchList()
        openFirstAlarmFromList()
        XCTAssertTrue(advanceHour(), "hour wheel should be adjustable")

        swipeDownFromSheet()
        let discard = app.buttons.matching(
            NSPredicate(format: "label == 'Discard Changes'")
        ).firstMatch
        XCTAssertTrue(
            discard.waitForExistence(timeout: 5),
            "swiping down with changes should ask before closing: \(app.debugDescription)"
        )
        discard.tap()
        XCTAssertTrue(
            root.waitForNonExistence(timeout: 10),
            "the editor should close: \(app.debugDescription)"
        )

        openFirstAlarmFromList()
    }
}
