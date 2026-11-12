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

        let row = app.buttons["library.preset.PresetMarimba.caf"]
        scrollToRow(row, in: choice)
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

        _ = openSoundChoice()
        let sound = app.buttons["library.preset.PresetMarimba.caf"]
        scrollToRow(sound, in: app.collectionViews["alarmSoundChoice.root"])
        let soundName = sound.label
        sound.tap()

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

    private func scrollToRow(_ row: XCUIElement, in choice: XCUIElement) {
        var swipes = 0
        while (!row.exists || !row.isHittable) && swipes < 12 {
            choice.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "row should be reachable: \(app.debugDescription)"
        )
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

    func testSoundChoicePlaylistEmptyStateExplainsAndOffersCreate() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-reset-playlists",
            "-uitest-reset-sounds"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        _ = openSoundChoice()
        let explanation = app.staticTexts["playlist.empty.explanation"]
        XCTAssertTrue(
            explanation.waitForExistence(timeout: 10),
            "empty explanation should appear: \(app.debugDescription)"
        )
        XCTAssertTrue(
            app.staticTexts["playlist.empty.importHint"].exists,
            "import hint should appear when there are no own sounds"
        )
        let create = app.buttons["alarmSoundChoice.addPlaylist"]
        XCTAssertTrue(create.exists)
        XCTAssertLessThan(
            explanation.frame.minY,
            create.frame.minY,
            "explanation should be read before the create button"
        )
    }

    func testSoundChoicePlaylistEmptyStateHiddenWhenPlaylistsExist() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-seed-design-audit"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        _ = openSoundChoice()
        XCTAssertFalse(
            app.staticTexts["playlist.empty.explanation"]
                .waitForExistence(timeout: 2),
            "empty explanation should not appear when playlists exist"
        )
        XCTAssertTrue(app.buttons["alarmSoundChoice.addPlaylist"].exists)
    }

    func testSoundChoicePlaylistEmptyStateAtAccessibilitySize() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-reset-playlists",
            "-uitest-reset-sounds",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        _ = openSoundChoice()
        let explanation = app.staticTexts["playlist.empty.explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 10))
        XCTAssertFalse(
            explanation.label.hasSuffix("…"),
            "AX5 explanation should not be truncated: \(explanation.label)"
        )
        XCTAssertTrue(app.buttons["alarmSoundChoice.addPlaylist"].exists)
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
            "-uitest-force-light",
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
}
