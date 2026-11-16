import XCTest

/// App Store のスクリーンショット素材（#1 取り込みの波形・#3 プレイリスト）を撮る。
/// 手動実行用。STORE_SHOT_DIR（xcodebuild では TEST_RUNNER_STORE_SHOT_DIR）が無ければ何もしない。
/// 波形用の音声は STORE_SHOT_DIR/song.m4a を使う。
@MainActor
final class StoreScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!
    private var shotDir: String? { ProcessInfo.processInfo.environment["STORE_SHOT_DIR"] }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureJapanese() throws {
        try capture(language: "ja", locale: "ja_JP", cropName: "朝の一曲")
    }

    func testCaptureEnglish() throws {
        try capture(language: "en", locale: "en_US", cropName: "Morning Song")
    }

    private func capture(language: String, locale: String, cropName: String) throws {
        guard let dir = shotDir else { throw XCTSkip("STORE_SHOT_DIR が無い") }

        // #3 プレイリスト
        launch(language: language, locale: locale, arguments: ["-uitest-seed-store", "-uitest-open-library"])
        let name = language == "ja" ? "マイプレイリスト" : "My Playlist"
        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        Thread.sleep(forTimeInterval: 1)
        save(dir, "\(language)-library")
        row.tap()
        Thread.sleep(forTimeInterval: 2)
        save(dir, "\(language)-playlist-top")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1.5)
        save(dir, "\(language)-playlist-order")
        // 曲の一覧の下半分と再生方法が両方見える位置
        app.swipeDown()
        Thread.sleep(forTimeInterval: 1)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.47))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
        Thread.sleep(forTimeInterval: 1.5)
        save(dir, "\(language)-playlist-mid")

        // #1 波形の切り取り
        let source = URL(fileURLWithPath: dir).appendingPathComponent("song2.m4a")
        let copy = URL(fileURLWithPath: dir).appendingPathComponent("crop2-\(language).m4a")
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: source, to: copy)
        launch(language: language, locale: locale, arguments: [
            "-uitest-seed-store", "-uitest-open-add-alarm", "-uitest-open-waveform-crop",
            "-uitestCropPath", copy.path, "-uitestCropName", cropName,
            "-uitestCropStart", "42", "-uitestCropEnd", "72"
        ])
        let crop = app.descendants(matching: .any)["audioCrop.cropAndSave"]
        XCTAssertTrue(crop.waitForExistence(timeout: 25), app.debugDescription)
        Thread.sleep(forTimeInterval: 10)
        save(dir, "\(language)-crop")
    }

    private func launch(language: String, locale: String, arguments: [String]) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale] + arguments
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            for label in ["許可", "Allow", "OK"] where springboard.buttons[label].exists {
                springboard.buttons[label].tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func save(_ dir: String, _ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
