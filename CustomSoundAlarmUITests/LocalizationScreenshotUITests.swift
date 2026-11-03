import XCTest

/// #149: ar / de / zh-Hans の主要画面（オンボーディング・一覧・追加・取り込み）を
/// スクリーンショットに残す。文字切れ・はみ出し・RTL の確認用。
/// 添付は xcresult から書き出す（PR 用）。
///
/// プリセット音の名前は初回起動時にその言語で保存されるため、言語ごとに
/// アプリのデータを消してから 1 言語ずつ実行する。
@MainActor
final class LocalizationScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(language: String, locale: String, arguments: [String]) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale] + arguments
        app.launch()
        // 新規インストール直後はアラームの許可ダイアログが出るので、写り込む前に閉じる。
        allowPermissionIfAsked()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func allowPermissionIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // ダイアログの文言はシステム言語（このシミュレータは日本語）で出る。
        let labels = [
            "許可", "Allow", "允许", "允許", "السماح", "Erlauben",
            "Autoriser", "Consenti", "Toestaan", "허용", "Zezwól", "Povolit", "OK"
        ]
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            for label in labels {
                let button = springboard.buttons[label]
                if button.exists {
                    button.tap()
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func capture(language: String, locale: String) {
        // 1. オンボーディング（ヒーロー・ループ・取り込み元）
        launch(language: language, locale: locale, arguments: ["-uitest-fresh-onboarding"])
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 15))
        snap("\(language)-onboarding-1-hero")

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        snap("\(language)-onboarding-2-loop")

        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continue"].tap()
        allowPermissionIfAsked()
        XCTAssertTrue(app.buttons["onboarding.source.video"].waitForExistence(timeout: 8))
        snap("\(language)-onboarding-3-source")
        app.buttons["onboarding.later"].tap()

        // 2. 一覧（3件のサンプル）
        launch(language: language, locale: locale, arguments: ["-uitest-seed-alarms"])
        XCTAssertTrue(app.buttons["alarmList.add"].waitForExistence(timeout: 15))
        snap("\(language)-list")

        // 3. 追加（時刻ホイール）
        launch(
            language: language,
            locale: locale,
            arguments: ["-uitest-open-add-alarm", "-uitest-reset-playlists"]
        )
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))
        snap("\(language)-add")

        // 4. 取り込み（サウンド選択と取り込み元）
        let soundRow = app.descendants(matching: .any)["addAlarm.soundRow"]
        if !soundRow.exists {
            app.collectionViews["addAlarm.root"].swipeUp()
        }
        XCTAssertTrue(soundRow.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.0)
        soundRow.tap()
        XCTAssertTrue(
            app.collectionViews["alarmSoundChoice.root"].waitForExistence(timeout: 10)
        )
        let singleSound = app.buttons["alarmSoundChoice.single"]
        XCTAssertTrue(singleSound.waitForExistence(timeout: 5))
        singleSound.tap()
        XCTAssertTrue(app.buttons["soundPicker.addVideo"].waitForExistence(timeout: 10))
        snap("\(language)-import-sounds")

        app.buttons["soundPicker.addVideo"].tap()
        snap("\(language)-import-source")
    }

    func testCaptureArabic() {
        capture(language: "ar", locale: "ar_SA")
    }

    func testCaptureGerman() {
        capture(language: "de", locale: "de_DE")
    }

    func testCaptureSimplifiedChinese() {
        capture(language: "zh-Hans", locale: "zh_CN")
    }

    /// RTL（ar）で波形と選択範囲が左→右のままか確認する。
    /// 同梱のプリセット音をクロップ画面に渡す（DEBUG 限定の起動引数）。
    func testCaptureWaveformArabic() {
        launch(
            language: "ar",
            locale: "ar_SA",
            arguments: ["-uitest-open-add-alarm", "-uitest-open-waveform-crop"]
        )
        let cropButton = app.descendants(matching: .any)["audioCrop.cropAndSave"]
        XCTAssertTrue(
            cropButton.waitForExistence(timeout: 20),
            "波形クロップ画面が出ない: \(app.debugDescription)"
        )
        // 波形サンプルの生成を待ってから撮る。
        Thread.sleep(forTimeInterval: 10)
        snap("ar-waveform-crop")
    }
}
