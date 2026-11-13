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

    /// 「曲を選ぶ」で自分の音が同梱の音より上に出る（#185）。
    func testTrackPickerShowsOwnSoundsAbovePresets() {
        let app = launch(["-uitest-seed-design-audit", "-uitest-open-library"])
        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 15),
            "library should open: \(app.debugDescription)"
        )

        let playlist = app.buttons["library.playlist.モーニング"]
        XCTAssertTrue(
            playlist.waitForExistence(timeout: 10),
            "seeded playlist should exist: \(app.debugDescription)"
        )
        playlist.tap()
        XCTAssertTrue(app.textFields["playlist.name"].waitForExistence(timeout: 10))

        let addTrack = app.buttons["playlist.addTrack"]
        var swipes = 0
        while !addTrack.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(addTrack.waitForExistence(timeout: 5))
        addTrack.tap()

        let custom = app.buttons["playlist.track.DesignAuditFavorite.caf"]
        let preset = app.buttons["playlist.track.PresetMarimba.caf"]
        XCTAssertTrue(
            custom.waitForExistence(timeout: 10),
            "own sound should exist: \(app.debugDescription)"
        )
        XCTAssertTrue(preset.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["自分の音"].exists)
        XCTAssertTrue(app.staticTexts["すぐ使える音"].exists)
        XCTAssertLessThan(
            custom.frame.minY,
            preset.frame.minY,
            "own sound should be above the bundled sounds"
        )
        XCTAssertTrue(
            app.staticTexts["0:28"].firstMatch.exists,
            "duration should remain visible"
        )

        custom.tap()
        XCTAssertTrue(
            custom.isSelected,
            "selected state should be exposed to VoiceOver"
        )
        XCTAssertTrue(
            app.images["playlist.trackSelected.DesignAuditFavorite.caf"].exists
        )
        custom.tap()
        XCTAssertFalse(custom.isSelected)
    }

    /// 自分の音が0件なら〔自分の音〕欄を出さない（#185）。
    func testTrackPickerHidesOwnSoundsSectionWhenEmpty() {
        let app = launch(["-uitest-seed-library", "-uitest-open-library"])
        XCTAssertTrue(app.collectionViews["library.root"].waitForExistence(timeout: 15))

        let playlist = app.buttons["library.playlist.朝の支度"]
        XCTAssertTrue(playlist.waitForExistence(timeout: 10))
        playlist.tap()
        XCTAssertTrue(app.textFields["playlist.name"].waitForExistence(timeout: 10))

        let addTrack = app.buttons["playlist.addTrack"]
        var swipes = 0
        while !addTrack.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(addTrack.waitForExistence(timeout: 5))
        addTrack.tap()

        XCTAssertTrue(
            app.buttons["playlist.track.PresetMarimba.caf"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(
            app.staticTexts["自分の音"].waitForExistence(timeout: 2),
            "own-sounds section should be hidden when there are none"
        )
    }

    func testPlaylistSuggestionCreatesPlaylist() {
        let app = launch(["-uitest-seed-suggestion", "-uitest-open-library"])
        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 15),
            "library should open: \(app.debugDescription)"
        )
        XCTAssertFalse(app.staticTexts["playlist.empty.explanation"].exists)
        XCTAssertFalse(app.buttons["library.addPlaylist"].exists)

        let suggestion = app.buttons["library.playlistSuggestion"]
        XCTAssertTrue(
            suggestion.waitForExistence(timeout: 10),
            "suggestion should appear: \(app.debugDescription)"
        )
        suggestion.tap()

        XCTAssertTrue(
            app.buttons["library.playlist.マイサウンド"].waitForExistence(timeout: 10),
            "created playlist should appear: \(app.debugDescription)"
        )
        XCTAssertFalse(app.buttons["library.playlistSuggestion"].exists)
    }

    func testPlaylistsShowRowsAndAddButton() {
        let app = launch(["-uitest-seed-library", "-uitest-open-library"])
        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 15),
            "library should open: \(app.debugDescription)"
        )
        XCTAssertFalse(app.staticTexts["playlist.empty.explanation"].exists)
        XCTAssertTrue(app.buttons["library.playlist.朝の支度"].exists)
        XCTAssertTrue(app.buttons["library.addPlaylist"].exists)
    }

    func testPlaylistSuggestionAtAccessibilitySize() {
        let app = launch([
            "-uitest-seed-suggestion",
            "-uitest-open-library",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 15),
            "library should open: \(app.debugDescription)"
        )
        let suggestion = app.buttons["library.playlistSuggestion"]
        var swipes = 0
        while (!suggestion.exists || !suggestion.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        XCTAssertFalse(
            suggestion.label.hasSuffix("…"),
            "AX5 suggestion should not be truncated: \(suggestion.label)"
        )
    }

    func testCreatePlaylistInLibraryAndSelectItForAlarm() {
        let app = launch([
            "-uitest-open-library",
            "-uitest-seed-library",
            "-uitest-save-alarm-disabled"
        ])

        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 15),
            "library should open: \(app.debugDescription)"
        )
        let addPlaylist = app.buttons["library.addPlaylist"]
        var swipes = 0
        while !addPlaylist.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(addPlaylist.waitForExistence(timeout: 10))
        addPlaylist.tap()

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
        let choiceRoot = app.collectionViews["alarmSoundChoice.root"]
        var choiceSwipes = 0
        while (!choice.exists || !choice.isHittable) && choiceSwipes < 8 {
            choiceRoot.swipeUp()
            choiceSwipes += 1
        }
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

    func testPlaylistDetailHasPreviewAndNativeDelete() {
        let app = launch(["-uitest-seed-library", "-uitest-open-library"])
        let playlistRow = app.buttons["library.playlist.朝の支度"]
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 15))
        playlistRow.tap()

        XCTAssertTrue(app.textFields["playlist.name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["playlist.preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["playlist.trackPlay.PresetMarimba.caf"]
                .waitForExistence(timeout: 5)
        )
        let reorderHandles = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "並べ替え")
        )
        XCTAssertGreaterThan(
            reorderHandles.count,
            0,
            "always-visible reorder handle should exist: \(app.debugDescription)"
        )

        let trackCell = app.cells.containing(
            .staticText,
            identifier: "マリンバ"
        ).firstMatch
        XCTAssertTrue(trackCell.waitForExistence(timeout: 5))

        // 常時 editMode なので、行頭の赤い − ボタンで削除する。
        let minus = app.descendants(matching: .any)
            .matching(identifier: "minus.circle.fill")
            .firstMatch
        XCTAssertTrue(
            minus.waitForExistence(timeout: 5),
            "minus button should exist: \(app.debugDescription)"
        )
        minus.tap()

        let confirm = app.buttons["削除"].firstMatch
        if confirm.waitForExistence(timeout: 3) {
            confirm.tap()
        } else {
            let deleteElements = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "削除")
            )
            XCTAssertGreaterThan(
                deleteElements.count,
                0,
                "delete confirmation should exist: \(app.debugDescription)"
            )
            deleteElements.element(boundBy: deleteElements.count - 1).tap()
        }
        XCTAssertFalse(app.staticTexts["マリンバ"].waitForExistence(timeout: 3))
    }

    func testPlaylistTrackCanBeReorderedByDragHandle() {
        let app = launch(["-uitest-seed-library", "-uitest-open-library"])
        let playlistRow = app.buttons["library.playlist.朝の支度"]
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 15))
        playlistRow.tap()

        let handles = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "並べ替え")
        )
        XCTAssertGreaterThanOrEqual(
            handles.count,
            3,
            "reorder handles should exist: \(app.debugDescription)"
        )
        let source = handles.element(boundBy: 0)
        let target = handles.element(boundBy: 2)
        source.press(forDuration: 0.8, thenDragTo: target)
        Thread.sleep(forTimeInterval: 1.0)

        let marimba = app.staticTexts["マリンバ"]
        let musicBox = app.staticTexts["オルゴール"]
        XCTAssertTrue(marimba.waitForExistence(timeout: 5))
        XCTAssertTrue(musicBox.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            marimba.frame.origin.y,
            musicBox.frame.origin.y,
            "Marimba should move below Music Box after drag"
        )
    }

    func testDebugSyncLogOpens() {
        let app = launch(["-uitest-open-library", "-uitest-seed-library"])
        XCTAssertTrue(app.collectionViews["library.root"].waitForExistence(timeout: 15))

        let row = app.buttons["library.syncLog"]
        for _ in 0..<6 where !row.exists {
            app.collectionViews["library.root"].swipeUp()
        }
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "DEBUG の同期ログ行が見つからない: \(app.debugDescription)"
        )
        row.tap()
        XCTAssertTrue(
            app.collectionViews["syncLog.root"].waitForExistence(timeout: 5),
            "同期ログ画面が開かない: \(app.debugDescription)"
        )
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
