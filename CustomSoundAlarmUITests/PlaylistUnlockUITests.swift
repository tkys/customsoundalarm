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
    /// 「作る」でプレイリストの詳細が開き、もう一度取り込んでも出ない。
    func testSecondImportUnlocksPlaylistAndCreatesIt() {
        app.launchArguments = [
            "-uitest-seed-one-sound",
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

        let name = findElement("playlist.name")
        XCTAssertTrue(
            name.waitForExistence(timeout: 15),
            "playlist detail should open after create: \(app.debugDescription)"
        )
        let tracks = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'playlist.trackPlay.'"))
        XCTAssertEqual(tracks.count, 2, "the suggested playlist should have two tracks")

        // 詳細を閉じて、もう一度取り込んでも解放は出ない
        app.navigationBars.buttons["キャンセル"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 15),
            "alarm list should be back: \(app.debugDescription)"
        )

        app.buttons["alarmList.add"].tap()
        importSecondSound()
        closeAddScreen()

        XCTAssertFalse(
            title.waitForExistence(timeout: 3),
            "unlock should not appear again: \(app.debugDescription)"
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
}
