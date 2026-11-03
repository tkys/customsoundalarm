import XCTest

/// #160 PR-2: ライブラリタブの作成・選択・削除確認。
@MainActor
final class LibraryUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(
        _ arguments: [String],
        language: String = "(ja)",
        locale: String = "ja_JP"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + [
            "-AppleLanguages", language,
            "-AppleLocale", locale
        ]
        app.launch()
        return app
    }

    func testCreatePlaylistInLibraryAndSelectItForAlarm() {
        let app = launch([
            "-uitest-open-library",
            "-uitest-reset-playlists",
            "-uitest-save-alarm-disabled"
        ])

        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 15),
            "library should open: \(app.debugDescription)"
        )
        app.buttons["library.addPlaylist"].tap()

        let nameField = app.textFields["playlist.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        if let current = nameField.value as? String, !current.isEmpty {
            nameField.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
            )
        }
        nameField.typeText("LibUITest")

        app.buttons["playlist.addTrack"].tap()
        let track = app.buttons["playlist.track.PresetMarimba.caf"]
        XCTAssertTrue(track.waitForExistence(timeout: 10))
        // シートの表示アニメーションが終わってから選ぶ
        Thread.sleep(forTimeInterval: 1.0)
        track.tap()
        XCTAssertTrue(
            app.images["playlist.trackSelected.PresetMarimba.caf"]
                .waitForExistence(timeout: 5),
            "track should be selected: \(app.debugDescription)"
        )
        let closeTrackPicker = app.buttons["playlist.closeTrackPicker"]
        closeTrackPicker.tap()
        XCTAssertFalse(
            closeTrackPicker.waitForExistence(timeout: 5),
            "track picker should dismiss before saving"
        )
        XCTAssertEqual(nameField.value as? String, "LibUITest")
        let savePlaylist = app.buttons["playlist.save"]
        XCTAssertTrue(savePlaylist.waitForExistence(timeout: 5))
        XCTAssertTrue(
            savePlaylist.isEnabled,
            "1曲入れたので保存できるはず: \(app.debugDescription)"
        )
        savePlaylist.tap()

        let playlistRow = app.buttons["library.playlist.LibUITest"]
        XCTAssertTrue(
            playlistRow.waitForExistence(timeout: 10),
            "created playlist should appear in library: \(app.debugDescription)"
        )

        // タブを切り替えて、アラームの音として選ぶ
        app.tabBars.buttons["アラーム"].tap()
        app.buttons["alarmList.add"].tap()

        let soundRow = app.buttons["addAlarm.soundRow"]
        XCTAssertTrue(soundRow.waitForExistence(timeout: 10))
        soundRow.tap()

        let choice = app.buttons["alarmSoundChoice.playlist.LibUITest"]
        XCTAssertTrue(
            choice.waitForExistence(timeout: 10),
            "library playlist should appear in sound choice: \(app.debugDescription)"
        )
        choice.tap()

        XCTAssertTrue(soundRow.waitForExistence(timeout: 10))
        XCTAssertTrue(
            soundRow.label.contains("LibUITest"),
            "selected playlist should be shown on the alarm screen: \(soundRow.label)"
        )
        XCTAssertTrue(
            soundRow.label.contains("順番") || soundRow.label.contains("シャッフル"),
            "play order summary should be shown: \(soundRow.label)"
        )

        // 保存して一覧にもプレイリスト名が出ること
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["LibUITest"].waitForExistence(timeout: 10))
    }

    func testPlaylistDeleteShowsAffectedAlarmCount() {
        let app = launch([
            "-uitest-seed-library",
            "-uitest-open-library"
        ])

        let row = app.buttons["library.playlist.朝の支度"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "seeded playlist should appear")
        row.swipeLeft()

        let swipeDelete = app.buttons["削除"]
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 5))
        swipeDelete.tap()

        let countMessage = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "1件")
        ).firstMatch
        XCTAssertTrue(
            countMessage.waitForExistence(timeout: 5),
            "confirmation should show the alarm count: \(app.debugDescription)"
        )

        let confirmDelete = app.sheets.buttons["削除"].firstMatch
        if confirmDelete.waitForExistence(timeout: 3) {
            confirmDelete.tap()
        } else {
            app.buttons["削除"].tap()
        }

        XCTAssertFalse(row.waitForExistence(timeout: 5))
    }

    func testPlaylistDeleteConfirmationUsesSingularInEnglish() {
        let app = launch(
            ["-uitest-seed-library", "-uitest-open-library"],
            language: "(en)",
            locale: "en_US"
        )

        let row = app.buttons["library.playlist.朝の支度"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.swipeLeft()
        let swipeDelete = app.buttons["Delete"]
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 5))
        swipeDelete.tap()

        let message = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "1 alarm uses this playlist")
        ).firstMatch
        XCTAssertTrue(
            message.waitForExistence(timeout: 5),
            "singular message should be used: \(app.debugDescription)"
        )
    }

    func testPlaylistDeleteConfirmationUsesPluralInEnglish() {
        let app = launch(
            ["-uitest-seed-library", "-uitest-open-library"],
            language: "(en)",
            locale: "en_US"
        )

        let row = app.buttons["library.playlist.週末のカフェ"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.swipeLeft()
        let swipeDelete = app.buttons["Delete"]
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 5))
        swipeDelete.tap()

        let message = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "2 alarms use this playlist")
        ).firstMatch
        XCTAssertTrue(
            message.waitForExistence(timeout: 5),
            "plural message should be used: \(app.debugDescription)"
        )
    }
}
