import XCTest

@MainActor
final class AddAlarmRedesignUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func findElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launchAdd() {
        app.launchArguments = ["-uitest-open-add-alarm"]
        app.launch()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10),
            "add screen should appear: \(app.debugDescription)"
        )
    }

    private func openSoundChoice() -> XCUIElement {
        let soundRow = findElement("addAlarm.soundRow")
        var swipes = 0
        while (!soundRow.exists || !soundRow.isHittable) && swipes < 16 {
            app.collectionViews["addAlarm.root"].swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            soundRow.waitForExistence(timeout: 5),
            "sound row should exist: \(app.debugDescription)"
        )
        soundRow.tap()

        let choice = app.collectionViews["alarmSoundChoice.root"]
        XCTAssertTrue(
            choice.waitForExistence(timeout: 15),
            "sound choice should open: \(app.debugDescription)"
        )
        return choice
    }

    /// 追加画面 → サウンド → 動画から音声を追加 で、取り込み画面が開いたまま残ること。
    /// 1.8.1 では取り込みのシートが各セクションに複製され、開いた直後に
    /// アラームの追加画面ごと閉じて一覧に戻っていた（実機で再現）。
    func testAddVideoFromSoundChoiceKeepsImportOpen() {
        launchAdd()
        _ = openSoundChoice()

        let addVideo = app.buttons["soundPicker.addVideo"]
        XCTAssertTrue(addVideo.waitForExistence(timeout: 10))
        addVideo.tap()

        let importRoot = findElement("videoImport.root")
        XCTAssertTrue(
            importRoot.waitForExistence(timeout: 10),
            "video import should open: \(app.debugDescription)"
        )
        // 開いた直後に閉じないこと（不具合は1秒以内に起きていた）
        Thread.sleep(forTimeInterval: 3.0)
        XCTAssertTrue(importRoot.exists, "video import should stay open: \(app.debugDescription)")
    }

    /// #196: 音を選ぶ画面で行をタップすると、選ばれて再生中になる。
    /// 同じ行をもう一度タップすると止まり、選択は残る。
    func testSoundRowTapSelectsAndPreviews() {
        launchAdd()
        let choice = openSoundChoice()
        let standard = app.buttons["library.standardSounds"]
        scrollTo(standard, in: choice)
        standard.tap()

        let row = app.buttons["library.preset.PresetMarimba.caf"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "standard row should appear")
        let preview = app.buttons["soundPicker.preview.PresetMarimba.caf"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "play button should exist")
        XCTAssertFalse(row.isSelected, "not selected before tap")
        XCTAssertTrue(waitForPreviewLabel(preview, playing: false), "preview should be idle")

        row.tap()
        XCTAssertTrue(row.isSelected, "tapping a row should select it: \(app.debugDescription)")
        XCTAssertTrue(waitForPreviewLabel(preview, playing: true), "preview should start")

        // 同じ行の再タップで止める（選択はそのまま）
        row.tap()
        XCTAssertTrue(row.isSelected, "selection should stay after stop")
        XCTAssertTrue(waitForPreviewLabel(preview, playing: false), "preview should stop")
    }

    /// #196 レビュー: プレイリストを選んだあと、音の行をタップすると音に切り替わる。
    func testTappingSoundRowSwitchesFromPlaylistToSound() {
        app.launchArguments = ["-uitest-open-add-alarm", "-uitest-seed-design-audit"]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        let soundRow = findElement("addAlarm.soundRow")
        _ = openSoundChoice()

        let playlist = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "alarmSoundChoice.playlist.")
        ).firstMatch
        XCTAssertTrue(
            playlist.waitForExistence(timeout: 10),
            "playlist should exist: \(app.debugDescription)"
        )
        let playlistName = ["モーニング", "Morning mix"].first {
            playlist.label.contains($0)
        } ?? playlist.label
        playlist.tap()

        XCTAssertTrue(soundRow.waitForExistence(timeout: 10), "should return to add screen")
        XCTAssertTrue(
            soundRow.label.contains(playlistName),
            "playlist should be selected: \(soundRow.label)"
        )

        let choice = openSoundChoice()
        let standard = app.buttons["library.standardSounds"]
        scrollTo(standard, in: choice)
        standard.tap()
        let sound = app.buttons["library.preset.PresetMarimba.caf"]
        XCTAssertTrue(sound.waitForExistence(timeout: 10))
        let soundName = sound.label
        sound.tap()
        closeStandardSoundsSheet()

        // 選んでも閉じない（#196）。戻って追加画面の表示を確認する
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(soundRow.waitForExistence(timeout: 10))
        XCTAssertTrue(
            soundRow.label.contains(soundName),
            "sound should replace the playlist: \(soundRow.label)"
        )
        XCTAssertFalse(
            soundRow.label.contains(playlistName),
            "playlist name should be gone: \(soundRow.label)"
        )
    }

    private func scrollTo(_ element: XCUIElement, in container: XCUIElement) {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < 10 {
            container.swipeUp()
            swipes += 1
        }
    }

    private func closeStandardSoundsSheet() {
        for label in ["Close", "閉じる"] {
            if app.buttons[label].waitForExistence(timeout: 2) {
                app.buttons[label].tap()
                return
            }
        }
    }

    /// 再生中は再生ボタンのラベルが「停止 / Stop」に変わる（#196）。
    private func waitForPreviewLabel(_ element: XCUIElement, playing: Bool) -> Bool {
        let labels = playing ? ["停止", "Stop"] : ["試聴", "Preview"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label IN %@", labels),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    /// #200: 動画の取り込み元は、吹き出しのダイアログではなく画面内の2行で出す。
    func testVideoImportShowsTwoSourceRowsWithoutDialog() {
        launchAdd()
        _ = openSoundChoice()

        let addVideo = app.buttons["soundPicker.addVideo"]
        XCTAssertTrue(addVideo.waitForExistence(timeout: 10))
        addVideo.tap()

        XCTAssertTrue(
            app.buttons["videoImport.source.photo"].waitForExistence(timeout: 10),
            "photo library row should appear: \(app.debugDescription)"
        )
        XCTAssertTrue(app.buttons["videoImport.source.file"].exists, "files row should appear")
        // 標準のダイアログ（吹き出し）のタイトルは出さない
        XCTAssertFalse(app.staticTexts["Select Video Source"].exists)
        XCTAssertFalse(app.staticTexts["動画の選択元"].exists)
    }

    /// #200 レビュー: 写真の行からピッカーを閉じても、もう一度開ける。
    func testPhotoSourceRowCanReopenPicker() {
        launchAdd()
        _ = openSoundChoice()
        let addVideo = app.buttons["soundPicker.addVideo"]
        XCTAssertTrue(addVideo.waitForExistence(timeout: 10))
        addVideo.tap()

        let photo = app.buttons["videoImport.source.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(
            cancel.waitForExistence(timeout: 10),
            "photo picker should open: \(app.debugDescription)"
        )
        cancel.tap()

        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()
        XCTAssertTrue(
            cancel.waitForExistence(timeout: 10),
            "photo picker should open again: \(app.debugDescription)"
        )
        cancel.tap()
    }

    func testSoundChoicePlaylistSuggestionCreatesAndSelects() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-seed-suggestion"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        let soundRow = findElement("addAlarm.soundRow")
        let choice = openSoundChoice()
        XCTAssertFalse(app.staticTexts["playlist.empty.explanation"].exists)
        XCTAssertFalse(app.buttons["alarmSoundChoice.addPlaylist"].exists)

        let suggestion = app.buttons["alarmSoundChoice.playlistSuggestion"]
        scrollTo(suggestion, in: choice)
        XCTAssertTrue(
            suggestion.waitForExistence(timeout: 10),
            "suggestion should appear: \(app.debugDescription)"
        )
        suggestion.tap()

        XCTAssertTrue(soundRow.waitForExistence(timeout: 10), "should return to add screen")
        XCTAssertTrue(
            soundRow.label.contains("My Playlist") || soundRow.label.contains("マイプレイリスト"),
            "created playlist should be selected: \(soundRow.label)"
        )

        _ = openSoundChoice()
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "alarmSoundChoice.playlist.")
            ).firstMatch.waitForExistence(timeout: 10),
            "created playlist row should replace the suggestion"
        )
        XCTAssertFalse(app.buttons["alarmSoundChoice.playlistSuggestion"].exists)
    }

    func testSoundChoicePlaylistsShowRowsAndAddButton() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-seed-design-audit"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        _ = openSoundChoice()
        XCTAssertFalse(app.staticTexts["playlist.empty.explanation"].exists)
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "alarmSoundChoice.playlist.")
            ).firstMatch.waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["alarmSoundChoice.addPlaylist"].exists)
        XCTAssertTrue(app.buttons["library.standardSounds"].exists)
    }

    func testSoundChoicePlaylistSuggestionAtAccessibilitySize() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-seed-suggestion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        let choice = openSoundChoice()
        let suggestion = app.buttons["alarmSoundChoice.playlistSuggestion"]
        scrollTo(suggestion, in: choice)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        XCTAssertFalse(
            suggestion.label.hasSuffix("…"),
            "AX5 suggestion should not be truncated: \(suggestion.label)"
        )
    }

    func testStandardSoundsRowOpensAndSelects() {
        launchAdd()
        _ = openSoundChoice()
        let standard = app.buttons["library.standardSounds"]
        XCTAssertTrue(
            standard.waitForExistence(timeout: 10),
            "standard row should appear: \(app.debugDescription)"
        )
        standard.tap()

        let row = app.buttons["library.preset.PresetMarimba.caf"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "standard list should open")
        row.tap()
        XCTAssertTrue(row.isSelected, "tapping a standard sound should select it")
        closeStandardSoundsSheet()

        XCTAssertTrue(standard.waitForExistence(timeout: 10))
        XCTAssertTrue(
            standard.label.contains("Marimba") || standard.label.contains("マリンバ"),
            "selected standard name should appear on the row: \(standard.label)"
        )
    }

    func testOversleepDetailsAppearOnlyWhenOn() {
        launchAdd()

        app.swipeUp()
        let toggle = findElement("addAlarm.backupToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "backup toggle should exist")
        XCTAssertFalse(findElement("addAlarm.backupMinutes").exists, "off: minutes must be hidden")
        XCTAssertFalse(findElement("addAlarm.backupTestRing").exists, "off: trial must be hidden")

        toggle.tap()

        XCTAssertTrue(findElement("addAlarm.backupMinutes").waitForExistence(timeout: 3))

        let backupTestRing = findElement("addAlarm.backupTestRing")
        var swipes = 0
        while (!backupTestRing.exists || !backupTestRing.isHittable) && swipes < 6 {
            app.collectionViews["addAlarm.root"].swipeUp()
            swipes += 1
        }
        XCTAssertTrue(backupTestRing.waitForExistence(timeout: 3))
    }

    func testOnlyOneTestRingButton() {
        launchAdd()
        XCTAssertEqual(
            app.buttons.matching(identifier: "addAlarm.testRing").count,
            1,
            "今すぐ鳴らすは1つだけ"
        )
    }

    func testEditScreenHasNoEnabledToggle() {
        app.launchArguments = ["-uitest-open-edit-alarm"]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10))

        // 旧画面の切り替えの文言（ja/en とも完全一致）
        XCTAssertFalse(app.staticTexts["アラームをオン"].exists)
        XCTAssertFalse(app.staticTexts["Alarm Enabled"].exists)
        // フォーム内でラベルを持つ切り替えは寝過ごし防止だけ
        // （SwiftUI は同じ切り替えをラベル無しの要素でも出すので、ラベル無しは数えない）
        let form = app.collectionViews["addAlarm.root"]
        for _ in 0..<4 {
            let labeled = form.switches.allElementsBoundByIndex.filter {
                !$0.label.isEmpty && $0.identifier != "addAlarm.backupToggle"
            }
            XCTAssertTrue(labeled.isEmpty, "edit screen has another switch: \(labeled.map(\.label))")
            form.swipeUp()
        }
    }

    func testAccessibilitySizeKeepsAllRows() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-seed-design-audit",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        let identifiers = [
            "addAlarm.repeatRow",
            "addAlarm.labelRow",
            "addAlarm.soundRow",
            "addAlarm.fadeIn",
            "addAlarm.snoozeRow",
            "addAlarm.testRing",
            "addAlarm.backupToggle"
        ]

        // 上から下まで少しずつスクロールし、見つかった識別子を記録する。
        // 1回のスクロールを画面の半分に抑え、LazyVStack のセルを
        // 通り過ぎて消してしまわないようにする（#174 PR-2 レビュー）。
        let start = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)
        )
        let end = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)
        )

        var found = Set<String>()
        for _ in 0..<20 {
            for identifier in identifiers where findElement(identifier).exists {
                found.insert(identifier)
            }
            if found.count == identifiers.count { break }

            start.press(
                forDuration: 0.1,
                thenDragTo: end,
                withVelocity: .slow,
                thenHoldForDuration: 0.1
            )
            Thread.sleep(forTimeInterval: 0.3)
        }

        for identifier in identifiers where findElement(identifier).exists {
            found.insert(identifier)
        }
        for identifier in identifiers {
            XCTAssertTrue(
                found.contains(identifier),
                "AX5: missing \(identifier)"
            )
        }
    }

    func testSectionOrder() {
        launchAdd()
        app.swipeUp()

        let identifiers = [
            "addAlarm.repeatRow",
            "addAlarm.labelRow",
            "addAlarm.soundRow",
            "addAlarm.fadeIn",
            "addAlarm.snoozeRow",
            "addAlarm.testRing",
            "addAlarm.backupToggle"
        ]

        var positions: [CGFloat] = []
        for identifier in identifiers {
            let element = findElement(identifier)
            XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(identifier)")
            positions.append(element.frame.origin.y)
        }

        for index in 1..<positions.count {
            XCTAssertLessThan(
                positions[index - 1],
                positions[index],
                "\(identifiers[index - 1]) should be above \(identifiers[index])"
            )
        }
    }

    /// #206: 時刻の候補を押すと、その時刻で保存される。
    func testTimeSuggestionSetsSavedTime() {
        app.launchArguments = [
            "-uitest-seed-enabled-alarms",
            "-uitest-open-add-alarm",
            "-uitest-disable-new-alarm"
        ]
        app.launch()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )

        let suggestion = findElement("addAlarm.timeSuggestion.6_35")
        XCTAssertTrue(
            suggestion.waitForExistence(timeout: 10),
            "time suggestion should appear: \(app.debugDescription)"
        )
        XCTAssertTrue(
            findElement("addAlarm.timeSuggestion.6_40").exists,
            "both suggestions should appear: \(app.debugDescription)"
        )

        suggestion.tap()
        app.buttons["addAlarm.save"].tap()

        XCTAssertTrue(
            app.staticTexts["06:35"].waitForExistence(timeout: 15),
            "saved alarm should use the suggested time: \(app.debugDescription)"
        )
    }

    /// #224: 小さい音声を取り込んだときだけ、音量を上げた1行を出す。
    func testVolumeNoticeOnlyForQuietImport() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            "-uitest-quiet-crop"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        let crop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(crop.waitForExistence(timeout: 20), app.debugDescription)
        crop.tap()

        let notice = findElement("addAlarm.volumeNotice")
        XCTAssertTrue(
            notice.waitForExistence(timeout: 15),
            "quiet import should show the volume notice: \(app.debugDescription)"
        )

        // 別の音を選ぶと、その音の話ではないので1行は消える（#224 レビュー）
        _ = openSoundChoice()
        let standard = app.buttons["library.standardSounds"]
        XCTAssertTrue(standard.waitForExistence(timeout: 10))
        standard.tap()
        let preset = app.buttons["library.preset.PresetMarimba.caf"]
        XCTAssertTrue(preset.waitForExistence(timeout: 10))
        preset.tap()
        closeStandardSoundsSheet()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            findElement("addAlarm.volumeNotice").waitForExistence(timeout: 3),
            "notice should disappear when another sound is selected"
        )

        app.terminate()
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))
        let normalCrop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(normalCrop.waitForExistence(timeout: 20), app.debugDescription)
        normalCrop.tap()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))
        XCTAssertFalse(
            findElement("addAlarm.volumeNotice").waitForExistence(timeout: 3),
            "normal import should not show the volume notice"
        )
    }

    /// #256: 無音の音は保存せず、切り取り画面の中で知らせる。
    func testSilentCropShowsNoticeAndDoesNotSave() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            "-uitest-silent-crop",
            "-uitest-force-light"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        let crop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(crop.waitForExistence(timeout: 20), app.debugDescription)
        crop.tap()

        let notice = findElement("silentSound.message")
        XCTAssertTrue(
            notice.waitForExistence(timeout: 15),
            "silent notice should appear: \(app.debugDescription)"
        )
        // ファイル全体が無音なので、範囲を選び直すボタンは出さない（#256 レビュー）
        XCTAssertFalse(findElement("silentSound.reselect").exists)
        XCTAssertTrue(findElement("silentSound.other").exists)
        XCTAssertFalse(findElement("silentSound.useAnyway").exists)

        findElement("silentSound.other").tap()
        XCTAssertFalse(
            crop.waitForExistence(timeout: 3),
            "choosing another sound should close the crop screen"
        )
    }

    /// #256 レビュー: 一部だけ無音のときは範囲の選び直しと別の音の両方を出す。
    func testPartialSilentCropShowsReselectAndOtherSound() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            "-uitest-partial-silent-crop",
            "-uitestCropStart", "1.5",
            "-uitestCropEnd", "3.0",
            "-uitest-force-light"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        let crop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(crop.waitForExistence(timeout: 20), app.debugDescription)
        crop.tap()

        let notice = findElement("silentSound.message")
        XCTAssertTrue(
            notice.waitForExistence(timeout: 15),
            "partial silent notice should appear: \(app.debugDescription)"
        )
        XCTAssertTrue(findElement("silentSound.reselect").exists)
        XCTAssertTrue(findElement("silentSound.other").exists)
        XCTAssertFalse(findElement("silentSound.useAnyway").exists)

        findElement("silentSound.reselect").tap()
        XCTAssertFalse(notice.waitForExistence(timeout: 3))
        XCTAssertTrue(crop.waitForExistence(timeout: 5))
    }

    /// #256: 既存の無音アラームは一覧で気づけ、押すと音を選べる。
    func testExistingSilentAlarmShowsWarningAndOpensSoundPicker() {
        app.launchArguments = [
            "-uitest-seed-silent-alarm",
            "-uitest-skip-alarm-sync",
            "-uitest-force-light"
        ]
        app.launch()

        let warning = findElement("alarm.silentSoundWarning")
        XCTAssertTrue(
            warning.waitForExistence(timeout: 15),
            "silent alarm warning should appear: \(app.debugDescription)"
        )
        findElement("alarm.row").tap()
        XCTAssertTrue(
            app.collectionViews["alarmSoundChoice.root"].waitForExistence(timeout: 10),
            "sound picker should open: \(app.debugDescription)"
        )
    }

    /// #237: 最大の文字サイズでも、時間の目盛りと開始・終了の行が重ならない。
    func testCropTimeRulerDoesNotOverlapLabelsAtAccessibilitySize() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            "-uitest-force-light",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        let start = findElement("crop.time.start")
        XCTAssertTrue(start.waitForExistence(timeout: 30), app.debugDescription)

        let rulers = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "crop.ruler.")
        )
        XCTAssertGreaterThan(rulers.count, 0, app.debugDescription)
        for index in 0..<rulers.count {
            let ruler = rulers.element(boundBy: index)
            XCTAssertFalse(
                ruler.frame.intersects(start.frame),
                "ruler \(ruler.identifier) must not overlap the time labels: \(app.debugDescription)"
            )
        }
    }
}
