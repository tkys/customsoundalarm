import XCTest

/// UI 見直し用のスクリーンショットを再現可能に撮る（#173）。
///
/// - 固定シード: `-uitest-seed-design-audit`
/// - ライト／ダーク × ja／en
/// - アラーム一覧と追加・編集は ja ライトの AX5 も
///
/// 画像は XCTest attachment として保存し、`scripts/export-design-audit-screenshots.sh`
/// で `design-audit-output/<日付>/` に書き出す。
@MainActor
final class DesignAuditScreenshotUITests: XCTestCase {

    private struct Context {
        let language: String
        let locale: String
        let appearance: XCUIDevice.Appearance
        let size: String
        let contentSize: String?

        var appearanceName: String {
            appearance == .dark ? "dark" : "light"
        }
    }

    /// 撮影に時間がかかるため、通常のテスト実行では動かさない。
    /// 撮るときだけ `TEST_RUNNER_DESIGN_AUDIT=1 xcodebuild test ...` で有効にする
    /// （xcodebuild は TEST_RUNNER_ 接頭辞の環境変数をテストに渡す）。
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DESIGN_AUDIT"] == "1",
            "Design audit screenshots run only with TEST_RUNNER_DESIGN_AUDIT=1"
        )
        continueAfterFailure = true
    }

    override func tearDown() {
        super.tearDown()
    }

    func testLightJapanese() {
        let context = Context(
            language: "ja",
            locale: "ja_JP",
            appearance: .light,
            size: "default",
            contentSize: nil
        )
        captureCampaign(context)
        captureAX5()
    }

    func testDarkJapanese() {
        captureCampaign(Context(
            language: "ja",
            locale: "ja_JP",
            appearance: .dark,
            size: "default",
            contentSize: nil
        ))
    }

    func testLightEnglish() {
        captureCampaign(Context(
            language: "en",
            locale: "en_US",
            appearance: .light,
            size: "default",
            contentSize: nil
        ))
    }

    func testDarkEnglish() {
        captureCampaign(Context(
            language: "en",
            locale: "en_US",
            appearance: .dark,
            size: "default",
            contentSize: nil
        ))
    }

    /// プレイリストの「曲を選ぶ」（#185）。自分の音あり、ja ライト／ダークと AX5。
    func testPlaylistTrackPicker() {
        let contexts = [
            Context(
                language: "ja",
                locale: "ja_JP",
                appearance: .light,
                size: "default",
                contentSize: nil
            ),
            Context(
                language: "ja",
                locale: "ja_JP",
                appearance: .dark,
                size: "default",
                contentSize: nil
            ),
            Context(
                language: "ja",
                locale: "ja_JP",
                appearance: .light,
                size: "ax5",
                contentSize: "UICTContentSizeCategoryAccessibilityXXXL"
            )
        ]
        for context in contexts {
            capturePlaylistTrackPicker(context)
        }
    }

    private func capturePlaylistTrackPicker(_ context: Context) {
        let app = launch(
            context,
            arguments: ["-uitest-seed-design-audit", "-uitest-open-library"]
        )
        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 25),
            "library did not appear: \(app.debugDescription)"
        )

        let playlist = app.buttons["library.playlist.モーニング"]
        var swipes = 0
        while (!playlist.exists || !playlist.isHittable) && swipes < 8 {
            app.collectionViews["library.root"].swipeUp()
            swipes += 1
        }
        XCTAssertTrue(playlist.waitForExistence(timeout: 10))
        playlist.tap()
        XCTAssertTrue(app.textFields["playlist.name"].waitForExistence(timeout: 15))

        let addTrack = app.buttons["playlist.addTrack"]
        swipes = 0
        while (!addTrack.exists || !addTrack.isHittable) && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(addTrack.waitForExistence(timeout: 10))
        addTrack.tap()

        let custom = app.buttons["playlist.track.DesignAuditFavorite.caf"]
        XCTAssertTrue(custom.waitForExistence(timeout: 15))
        custom.tap()
        settle()
        capture(
            app,
            screen: "playlist-track-picker",
            context: context
        )
    }

    /// プレイリスト空状態（#183）。ja ライト／ダークと AX5。
    func testPlaylistEmptyStates() {
        let contexts = [
            Context(
                language: "ja",
                locale: "ja_JP",
                appearance: .light,
                size: "default",
                contentSize: nil
            ),
            Context(
                language: "ja",
                locale: "ja_JP",
                appearance: .dark,
                size: "default",
                contentSize: nil
            ),
            Context(
                language: "ja",
                locale: "ja_JP",
                appearance: .light,
                size: "ax5",
                contentSize: "UICTContentSizeCategoryAccessibilityXXXL"
            )
        ]
        for context in contexts {
            capturePlaylistEmptyStates(context)
        }
    }

    private func capturePlaylistEmptyStates(_ context: Context) {
        let emptyArguments = [
            "-uitest-reset-playlists",
            "-uitest-reset-sounds"
        ]

        let libraryApp = launch(
            context,
            arguments: emptyArguments + ["-uitest-open-library"],
            allowAlarmPermission: false
        )
        XCTAssertTrue(
            libraryApp.collectionViews["library.root"].waitForExistence(timeout: 25),
            "library did not appear: \(libraryApp.debugDescription)"
        )
        XCTAssertTrue(
            libraryApp.staticTexts["playlist.empty.explanation"]
                .waitForExistence(timeout: 10)
        )
        settle()
        capture(
            libraryApp,
            screen: "playlist-empty-library",
            context: context
        )
        if context.size == "ax5" {
            libraryApp.collectionViews["library.root"].swipeUp()
            settle()
            capture(
                libraryApp,
                screen: "playlist-empty-library-lower",
                context: context
            )
        }

        let soundApp = launch(
            context,
            arguments: emptyArguments + ["-uitest-open-add-alarm"],
            allowAlarmPermission: false
        )
        XCTAssertTrue(
            soundApp.collectionViews["addAlarm.root"].waitForExistence(timeout: 25)
        )
        _ = openSoundChoice(soundApp)
        XCTAssertTrue(
            soundApp.staticTexts["playlist.empty.explanation"]
                .waitForExistence(timeout: 10)
        )
        settle()
        capture(
            soundApp,
            screen: "playlist-empty-sound-choice",
            context: context
        )
        if context.size == "ax5" {
            soundApp.collectionViews["alarmSoundChoice.root"].swipeUp()
            settle()
            capture(
                soundApp,
                screen: "playlist-empty-sound-choice-lower",
                context: context
            )
        }
    }

    // MARK: - Conditions

    private func captureCampaign(_ context: Context) {
        captureMain(context, includeLibraryAndBedside: true, captureSoundChoice: true)
        captureAddDenied(context)
        captureImportCrop(context)
        captureOnboarding(context)
    }

    private func captureAX5() {
        let context = Context(
            language: "ja",
            locale: "ja_JP",
            appearance: .light,
            size: "ax5",
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        captureMain(context, includeLibraryAndBedside: false, captureSoundChoice: false)
        captureAddDenied(context)
        captureAddLowerAX5(context)
    }

    /// AX5 の追加画面は1画面に収まらないため、下のまとまりも撮る（#174 PR-2）。
    private func captureAddLowerAX5(_ context: Context) {
        let app = launch(
            context,
            arguments: seedArguments + ["-uitest-open-add-alarm"]
        )
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 25)
        )
        for _ in 0..<3 {
            app.collectionViews["addAlarm.root"].swipeUp()
        }
        settle()
        capture(app, screen: "alarm-add-lower", context: context)
    }

    // MARK: - Main session

    private func captureMain(
        _ context: Context,
        includeLibraryAndBedside: Bool,
        captureSoundChoice: Bool
    ) {
        let app = launch(context, arguments: seedArguments)
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 25),
            "alarm list did not appear: \(app.debugDescription)"
        )
        settle()
        capture(app, screen: "alarm-list", context: context)

        app.buttons["alarmList.add"].tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 25)
        )

        // 音の選択画面
        let choice = openSoundChoice(app)
        if captureSoundChoice {
            settle()
            capture(app, screen: "sound-selection", context: context)
        }

        // 1つの音（#196: 選んでも画面は閉じないので、戻ってから撮る）
        let preset = app.buttons["library.preset.PresetMarimba.caf"]
        scrollWithin(preset, in: choice)
        preset.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10)
        )
        settle()
        capture(app, screen: "alarm-add-single", context: context)

        // プレイリスト
        let playlistChoice = openSoundChoice(app)
        let playlist = app.buttons[
            "alarmSoundChoice.playlist.\(playlistName(context))"
        ].firstMatch
        scrollWithin(playlist, in: playlistChoice, maxSwipes: 6)
        playlist.tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10)
        )
        settle()
        capture(app, screen: "alarm-add-playlist", context: context)

        // 寝過ごし防止オン
        let toggle = app.descendants(matching: .any)["addAlarm.backupToggle"]
        scrollTo(toggle, in: app)
        toggle.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["addAlarm.backupMinutes"]
                .waitForExistence(timeout: 5)
        )
        settle()
        capture(app, screen: "alarm-add-backup", context: context)

        cancelModal(app, context: context)

        // 編集（1つの音）
        let time = app.staticTexts["07:00"]
        XCTAssertTrue(time.waitForExistence(timeout: 10))
        time.tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15)
        )
        settle()
        capture(app, screen: "alarm-edit-single", context: context)
        cancelModal(app, context: context)

        guard includeLibraryAndBedside else { return }

        // ライブラリ
        app.tabBars.buttons[libraryTab(context)].tap()
        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 15)
        )
        settle()
        capture(app, screen: "library", context: context)

        // プレイリスト詳細
        let libraryPlaylist = app.buttons[
            "library.playlist.\(playlistName(context))"
        ]
        XCTAssertTrue(libraryPlaylist.waitForExistence(timeout: 10))
        libraryPlaylist.tap()
        XCTAssertTrue(
            app.textFields["playlist.name"].waitForExistence(timeout: 10)
        )
        settle()
        capture(app, screen: "playlist-detail", context: context)

        // ナイトモード
        app.tabBars.buttons[alarmTab(context)].tap()
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 10)
        )
        app.buttons["alarmList.bedside"].tap()
        settle(5.5)
        capture(app, screen: "bedside", context: context)
    }

    // MARK: - Separate launches

    private func captureAddDenied(_ context: Context) {
        let app = launch(
            context,
            arguments: seedArguments + [
                "-uitest-open-add-alarm",
                "-uitest-test-ring-denied"
            ]
        )
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 25)
        )
        let reason = app.descendants(matching: .any)["addAlarm.testRingReason"]
        scrollTo(reason, in: app)
        settle()
        capture(app, screen: "alarm-add-denied", context: context)
    }

    private func captureImportCrop(_ context: Context) {
        let app = launch(
            context,
            arguments: [
                "-uitest-open-add-alarm",
                "-uitest-open-waveform-crop"
            ]
        )
        let crop = app.descendants(matching: .any)["audioCrop.cropAndSave"]
        XCTAssertTrue(crop.waitForExistence(timeout: 25))
        // 波形サンプルの生成を待つ（シードを使わない通常起動）。
        settle(10)
        capture(app, screen: "import-crop", context: context)
    }

    private func captureOnboarding(_ context: Context) {
        let app = launch(
            context,
            arguments: ["-uitest-fresh-onboarding"],
            allowAlarmPermission: false
        )
        XCTAssertTrue(
            app.buttons["onboarding.next"].waitForExistence(timeout: 20)
        )
        settle()
        capture(app, screen: "onboarding-1-intro", context: context)

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(
            app.buttons["onboarding.next"].waitForExistence(timeout: 10)
        )
        settle()
        capture(app, screen: "onboarding-2-loop", context: context)

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(
            app.buttons["onboarding.continue"].waitForExistence(timeout: 10)
        )
        settle()
        capture(app, screen: "onboarding-3-permission", context: context)

        app.buttons["onboarding.continue"].tap()
        allowPermissionIfAsked()
        XCTAssertTrue(
            app.buttons["onboarding.source.video"].waitForExistence(timeout: 15)
        )
        settle()
        capture(app, screen: "onboarding-4-source", context: context)
    }

    // MARK: - Helpers

    private var seedArguments: [String] {
        ["-uitest-seed-design-audit"]
    }

    private func playlistName(_ context: Context) -> String {
        context.language == "ja" ? "モーニング" : "Morning mix"
    }

    private func libraryTab(_ context: Context) -> String {
        context.language == "ja" ? "ライブラリ" : "Library"
    }

    private func alarmTab(_ context: Context) -> String {
        context.language == "ja" ? "アラーム" : "Alarms"
    }

    private func launch(
        _ context: Context,
        arguments: [String],
        allowAlarmPermission: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(context.language))",
            "-AppleLocale", context.locale,
            context.appearance == .dark
                ? "-uitest-force-dark"
                : "-uitest-force-light"
        ] + arguments
        if let contentSize = context.contentSize {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                contentSize
            ]
        }
        app.launch()
        if allowAlarmPermission {
            allowPermissionIfAsked()
        }
        return app
    }

    private func openSoundChoice(_ app: XCUIApplication) -> XCUIElement {
        let soundRow = app.descendants(matching: .any)["addAlarm.soundRow"]
        scrollTo(soundRow, in: app)
        soundRow.tap()
        let choice = app.collectionViews["alarmSoundChoice.root"]
        XCTAssertTrue(
            choice.waitForExistence(timeout: 15),
            "sound choice did not open: \(app.debugDescription)"
        )
        return choice
    }

    private func cancelModal(
        _ app: XCUIApplication,
        context: Context
    ) {
        let label = context.language == "ja" ? "キャンセル" : "Cancel"
        let cancel = app.buttons[label]
        if cancel.exists {
            cancel.tap()
        }
        XCTAssertTrue(
            app.buttons["alarmList.add"].waitForExistence(timeout: 10)
        )
    }

    private func capture(
        _ app: XCUIApplication,
        screen: String,
        context: Context
    ) {
        let name = "\(screen)_\(context.appearanceName)_\(context.language)_\(context.size)"
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollTo(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 16
    ) {
        scrollWithin(element, in: app.collectionViews["addAlarm.root"], maxSwipes: maxSwipes)
    }

    private func scrollWithin(
        _ element: XCUIElement,
        in list: XCUIElement,
        maxSwipes: Int = 12
    ) {
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < maxSwipes {
            list.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            element.waitForExistence(timeout: 5),
            "element not found after scrolling: \(element)"
        )
        XCTAssertTrue(element.isHittable, "element is not hittable: \(element)")
    }

    private func settle(_ seconds: TimeInterval = 1.0) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func allowPermissionIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["許可", "Allow"] {
            if springboard.buttons[label].waitForExistence(timeout: 1) {
                springboard.buttons[label].tap()
                return
            }
        }
    }
}
