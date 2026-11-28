import XCTest

@MainActor
final class PlaylistUnlockUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func findElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// 取り込んだ音が1つある状態から2つ目を取り込み、追加画面を閉じると解放が出る。
    /// 「作る」で使うアラームを選ぶシートが開き、選んだアラームがプレイリストになる。
    func testSecondImportUnlocksPlaylistAndAppliesToAlarm() {
        app.launchArguments = [
            "-uitest-seed-one-sound",
            "-uitest-seed-alarm-fired",
            "-uitest-playlist-unlock",
            "-uitest-force-light",
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            "-uitest-quiet-crop",
            "-uitest-disable-new-alarm"
        ]
        app.launch()

        importSecondSound()
        closeAddScreen()

        let title = findElement("playlistUnlock.title")
        XCTAssertTrue(
            title.waitForExistence(timeout: 15),
            "unlock sheet should appear after leaving the add screen: \(app.debugDescription)"
        )

        app.buttons["playlistUnlock.create"].tap()

        let applyRoot = findElement("playlistApply.root")
        XCTAssertTrue(
            applyRoot.waitForExistence(timeout: 15),
            "apply sheet should appear after create: \(app.debugDescription)"
        )

        let applyButton = app.buttons["playlistApply.apply"]
        XCTAssertTrue(applyButton.waitForExistence(timeout: 5))
        XCTAssertFalse(applyButton.isEnabled, "nothing is selected at first")

        selectFirstApplyAlarm()
        XCTAssertTrue(applyButton.isEnabled)
        applyButton.tap()
        waitForDisappearance(applyRoot)

        let row = app.switches.matching(identifier: "alarm.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(
            row.label.contains("マイプレイリスト"),
            "the alarm should use the created playlist: \(row.label)"
        )
    }

    /// 鳴った記録が無いうちは、2つ目の取り込みのカードを出さない（#324）。
    func testSecondImportDoesNotShowUnlockBeforeAnAlarmFires() {
        app.launchArguments = [
            "-uitest-seed-one-sound",
            "-uitest-clear-alarm-history",
            "-uitest-playlist-unlock",
            "-uitest-force-light",
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            "-uitest-quiet-crop",
            "-uitest-disable-new-alarm"
        ]
        app.launch()

        importSecondSound()
        closeAddScreen()

        XCTAssertFalse(
            findElement("playlistUnlock.title").waitForExistence(timeout: 5),
            "unlock should wait until an alarm has fired: \(app.debugDescription)"
        )
    }

    /// 待ちは起動をまたいで残り、鳴った記録ができた次の起動で出る（#324）。
    func testSecondImportUnlockWaitsAcrossRelaunches() {
        app.launchArguments = [
            "-uitest-seed-one-sound",
            "-uitest-clear-alarm-history",
            "-uitest-playlist-unlock",
            "-uitest-force-light",
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            "-uitest-quiet-crop",
            "-uitest-disable-new-alarm"
        ]
        app.launch()
        importSecondSound()
        closeAddScreen()
        XCTAssertFalse(
            findElement("playlistUnlock.title").waitForExistence(timeout: 3),
            "unlock should not appear before an alarm fires: \(app.debugDescription)"
        )

        app.terminate()
        app.launchArguments = ["-uitest-playlist-unlock", "-uitest-force-light"]
        app.launch()
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        XCTAssertFalse(
            findElement("playlistUnlock.title").waitForExistence(timeout: 3),
            "the pending card should still wait after a relaunch: \(app.debugDescription)"
        )

        app.terminate()
        app.launchArguments = [
            "-uitest-playlist-unlock",
            "-uitest-force-light",
            "-uitest-seed-alarm-fired"
        ]
        app.launch()
        XCTAssertTrue(
            findElement("playlistUnlock.title").waitForExistence(timeout: 15),
            "the pending card should appear after an alarm has fired: \(app.debugDescription)"
        )
    }

    private func importSecondSound() {
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))
        let crop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(crop.waitForExistence(timeout: 20), app.debugDescription)
        crop.tap()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))
        // 切り取りシートの閉じるアニメーション中はタップが吸われる
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func closeAddScreen() {
        app.buttons["addAlarm.save"].tap()
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            "add screen should close after save: \(app.debugDescription)"
        )
    }

    // MARK: - 既存の人への1回だけの提案 (#280 / #324)

    /// 2つ以上取り込んでいてプレイリストがない既存の人に、起動時に1回だけ出る。
    /// ［あとで］で閉じたら、同じ状態で再起動しても出ない。
    func testExistingUserUnlockShowsOnceThenNeverAgain() {
        app.launchArguments = existingUserArguments(seeding: ["-uitest-seed-existing-unlock"])
        app.launch()

        let title = findElement("playlistUnlock.title")
        XCTAssertTrue(
            title.waitForExistence(timeout: 15),
            "unlock sheet should appear for an existing user: \(app.debugDescription)"
        )

        app.buttons["playlistUnlock.later"].tap()
        waitForDisappearance(title)

        app.terminate()
        app.launchArguments = existingUserArguments(seeding: [])
        app.launch()

        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            "alarm list should appear on the second launch: \(app.debugDescription)"
        )
        XCTAssertFalse(
            title.waitForExistence(timeout: 3),
            "unlock should not appear again after later: \(app.debugDescription)"
        )
    }

    /// 既存の人も、作った後に「使うアラームを選ぶ」シートが出る。
    func testExistingUserUnlockCreateShowsPlaylistApply() {
        launchExistingUserWithAlarm()

        let title = findElement("playlistUnlock.title")
        XCTAssertTrue(title.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["playlistUnlock.create"].tap()

        XCTAssertTrue(
            findElement("playlistApply.root").waitForExistence(timeout: 15),
            "apply sheet should appear after create: \(app.debugDescription)"
        )
        XCTAssertFalse(
            app.buttons["playlistApply.apply"].isEnabled,
            "nothing is selected at first"
        )
    }

    /// 「あとで」で閉じたら、アラームの音は変わらない。
    func testExistingUserUnlockApplyLaterKeepsAlarmSound() {
        launchExistingUserWithAlarm()

        let title = findElement("playlistUnlock.title")
        XCTAssertTrue(title.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["playlistUnlock.create"].tap()

        let applyRoot = findElement("playlistApply.root")
        XCTAssertTrue(applyRoot.waitForExistence(timeout: 15), app.debugDescription)
        selectFirstApplyAlarm()
        app.buttons["playlistApply.later"].tap()
        waitForDisappearance(applyRoot)

        let row = app.switches.matching(identifier: "alarm.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(
            row.label.contains("First Sound"),
            "later should not change the alarm sound: \(row.label)"
        )
    }

    /// アラームが0本なら、シートではなく追加画面を開き、プレイリストが選ばれている。
    func testExistingUserUnlockWithNoAlarmsOpensAddScreen() {
        app.launchArguments = existingUserArguments(seeding: ["-uitest-seed-existing-unlock"])
        app.launch()

        let title = findElement("playlistUnlock.title")
        XCTAssertTrue(title.waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["playlistUnlock.create"].tap()

        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            "add screen should open when there are no alarms: \(app.debugDescription)"
        )
        let soundName = findElement("addAlarm.soundName")
        XCTAssertTrue(soundName.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(soundName.label, "マイプレイリスト")
    }

    func testExistingUserUnlockDoesNotShowForOneSound() {
        assertUnlockDoesNotAppear(seeding: "-uitest-seed-existing-unlock-one-sound")
    }

    func testExistingUserUnlockDoesNotShowWhenPlaylistExists() {
        assertUnlockDoesNotAppear(seeding: "-uitest-seed-existing-unlock-playlist")
    }

    func testExistingUserUnlockDoesNotShowWhenAlreadyShown() {
        assertUnlockDoesNotAppear(seeding: "-uitest-seed-existing-unlock-shown")
    }

    /// ライブラリの提案の1行から作ったときも、同じシートが出る。
    func testLibrarySuggestionCreateShowsPlaylistApply() {
        app.launchArguments = [
            "-uitest-playlist-unlock",
            "-uitest-force-light",
            "-uitest-open-library",
            "-uitest-seed-existing-unlock-shown",
            "-uitest-seed-existing-unlock-alarm"
        ]
        app.launch()

        let suggestion = findElement("library.playlistSuggestion")
        XCTAssertTrue(
            suggestion.waitForExistence(timeout: 15),
            "library suggestion should exist: \(app.debugDescription)"
        )
        suggestion.tap()

        XCTAssertTrue(
            findElement("playlistApply.root").waitForExistence(timeout: 15),
            "apply sheet should appear after the suggestion creates a playlist: \(app.debugDescription)"
        )
    }

    private func launchExistingUserWithAlarm() {
        app.launchArguments = existingUserArguments(seeding: [
            "-uitest-seed-existing-unlock",
            "-uitest-seed-existing-unlock-alarm"
        ])
        app.launch()
    }

    private func existingUserArguments(seeding: [String]) -> [String] {
        ["-uitest-playlist-unlock", "-uitest-force-light"] + seeding
    }

    private func selectFirstApplyAlarm() {
        let row = app.buttons.matching(identifier: "playlistApply.alarm").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
    }

    private func assertUnlockDoesNotAppear(seeding: String) {
        app.launchArguments = existingUserArguments(seeding: [seeding])
        app.launch()

        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            "alarm list should appear: \(app.debugDescription)"
        )
        XCTAssertFalse(
            findElement("playlistUnlock.title").waitForExistence(timeout: 5),
            "unlock should not appear for this state: \(app.debugDescription)"
        )
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: timeout),
            .completed,
            "element should disappear: \(element)"
        )
    }
}
