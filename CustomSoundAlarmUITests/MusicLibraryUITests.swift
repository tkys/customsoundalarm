import XCTest

/// ミュージックライブラリからの取り込み（#245）。
final class MusicLibraryUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-uitest-skip-alarm-sync",
            "-uitest-force-light"
        ] + arguments
        app.launch()
    }

    private func find(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func openSoundPicker() {
        launch(["-uitest-open-add-alarm"])
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        let soundRow = find("addAlarm.soundRow")
        XCTAssertTrue(soundRow.waitForExistence(timeout: 10), app.debugDescription)
        soundRow.tap()
        XCTAssertTrue(
            app.collectionViews["alarmSoundChoice.root"].waitForExistence(timeout: 10),
            app.debugDescription
        )
    }

    func testSoundPickerShowsMusicRow() {
        openSoundPicker()
        XCTAssertTrue(
            app.buttons["soundPicker.addMusic"].waitForExistence(timeout: 10),
            app.debugDescription
        )
        XCTAssertEqual(app.buttons.matching(identifier: "soundPicker.addMusic").count, 1)
    }

    /// シミュレータにはミュージックライブラリが無いので、書き出し後の流れだけ起動引数で通す。
    func testMusicCropOpensWithSongTitle() {
        launch([
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            "-uitest-music-crop"
        ])
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        XCTAssertTrue(
            find("audioCrop.cropAndSave").waitForExistence(timeout: 20),
            app.debugDescription
        )
        let name = find("audioCrop.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(name.value as? String, "Test Song")
    }

    func testMusicUnavailableShowsOneShortLine() {
        launch(["-uitest-open-add-alarm", "-uitest-music-unavailable"])
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        find("addAlarm.soundRow").tap()
        XCTAssertTrue(
            app.collectionViews["alarmSoundChoice.root"].waitForExistence(timeout: 10),
            app.debugDescription
        )
        let message = find("soundPicker.musicMessage")
        XCTAssertTrue(message.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(message.label, "This song can't be imported.")
    }

    /// 許可がないときの1行は、押すと設定アプリを開く（#245 レビュー）。
    func testPermissionDeniedLineOpensSettings() {
        launch(["-uitest-open-add-alarm", "-uitest-music-permission-denied"])
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        find("addAlarm.soundRow").tap()
        XCTAssertTrue(
            app.collectionViews["alarmSoundChoice.root"].waitForExistence(timeout: 10),
            app.debugDescription
        )
        let message = find("soundPicker.musicMessage")
        XCTAssertTrue(message.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(
            message.label,
            "Allow access to Music in Settings."
        )
        XCTAssertTrue(message.isHittable)
        message.tap()

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(
            settings.wait(for: .runningForeground, timeout: 10),
            "Tapping the permission line should open the Settings app"
        )
        settings.terminate()
    }

    // MARK: - PR 用スクリーンショット（#245）

    /// 撮るときだけ `TEST_RUNNER_MUSIC_SCREENSHOTS=1 xcodebuild test ...` で有効にする。
    private func skipUnlessScreenshotRun() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MUSIC_SCREENSHOTS"] == "1",
            "Music library screenshots run only with TEST_RUNNER_MUSIC_SCREENSHOTS=1"
        )
    }

    private func launchForScreenshot(language: String, locale: String, ax5: Bool) {
        app?.terminate()
        app = XCUIApplication()
        var arguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-uitest-skip-alarm-sync",
            "-uitest-force-light",
            "-uitest-open-add-alarm"
        ]
        if ax5 {
            arguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        }
        app.launchArguments = arguments
        app.launch()
        allowAlarmPermissionIfNeeded()
    }

    private func allowAlarmPermissionIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            for label in ["許可", "Allow"] {
                if springboard.buttons[label].exists {
                    springboard.buttons[label].tap()
                    return
                }
                if app.buttons[label].exists {
                    app.buttons[label].tap()
                    return
                }
            }
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    private func openSoundPickerForScreenshot() {
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        let soundRow = find("addAlarm.soundRow")
        XCTAssertTrue(soundRow.waitForExistence(timeout: 10), app.debugDescription)
        // AX サイズでは音の行が画面外に出るので、見えるまでスクロールする
        var swipes = 0
        while !soundRow.isHittable && swipes < 8 {
            app.collectionViews["addAlarm.root"].swipeUp()
            swipes += 1
        }
        soundRow.tap()
        XCTAssertTrue(
            app.collectionViews["alarmSoundChoice.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        XCTAssertTrue(
            app.buttons["soundPicker.addMusic"].waitForExistence(timeout: 10),
            app.debugDescription
        )
        // 行のアイコンや文字が描画されるまで少し待つ
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testScreenshotJapaneseStandard() throws {
        try skipUnlessScreenshotRun()
        launchForScreenshot(language: "ja", locale: "ja_JP", ax5: false)
        openSoundPickerForScreenshot()
        snap("ja-music-import-standard")
    }

    func testScreenshotEnglishStandard() throws {
        try skipUnlessScreenshotRun()
        launchForScreenshot(language: "en", locale: "en_US", ax5: false)
        openSoundPickerForScreenshot()
        snap("en-music-import-standard")
    }

    func testScreenshotJapaneseAX5() throws {
        try skipUnlessScreenshotRun()
        launchForScreenshot(language: "ja", locale: "ja_JP", ax5: true)
        openSoundPickerForScreenshot()
        snap("ja-music-import-ax5")
    }

    func testScreenshotEnglishAX5() throws {
        try skipUnlessScreenshotRun()
        launchForScreenshot(language: "en", locale: "en_US", ax5: true)
        openSoundPickerForScreenshot()
        snap("en-music-import-ax5")
    }

    /// 取り込めない1行（#245）。理由の長い説明は出さない。
    func testScreenshotUnavailableLine() throws {
        try skipUnlessScreenshotRun()
        launchJapaneseWithNotice("-uitest-music-unavailable")
        snap("ja-music-unavailable")
    }

    /// 許可がないときの1行（#245 レビュー）。押すと設定アプリを開く。
    func testScreenshotPermissionDeniedLine() throws {
        try skipUnlessScreenshotRun()
        launchJapaneseWithNotice("-uitest-music-permission-denied")
        snap("ja-music-permission-denied")
    }

    private func launchJapaneseWithNotice(_ flag: String) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP",
            "-uitest-skip-alarm-sync",
            "-uitest-force-light",
            "-uitest-open-add-alarm",
            flag
        ]
        app.launch()
        allowAlarmPermissionIfNeeded()
        openSoundPickerForScreenshot()
        XCTAssertTrue(
            find("soundPicker.musicMessage").waitForExistence(timeout: 5),
            app.debugDescription
        )
        Thread.sleep(forTimeInterval: 0.5)
    }
}
