import XCTest

/// PR 用の ja スクリーンショットを撮る（#160 PR-2）。
@MainActor
final class LibraryScreenshotUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + [
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()
        return app
    }

    private func allowAlarmPermissionIfNeeded(_ app: XCUIApplication) {
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

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureLibrary() {
        let app = launch(["-uitest-seed-library", "-uitest-open-library"])
        XCTAssertTrue(app.collectionViews["library.root"].waitForExistence(timeout: 15))
        allowAlarmPermissionIfNeeded(app)
        attach("ja-library", app)
    }

    func testCapturePlaylistDetail() {
        let app = launch(["-uitest-seed-library", "-uitest-open-library"])
        allowAlarmPermissionIfNeeded(app)
        let row = app.buttons["library.playlist.朝の支度"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()

        XCTAssertTrue(app.textFields["playlist.name"].waitForExistence(timeout: 10))
        attach("ja-playlist-detail", app)
    }

    func testCaptureSoundChoice() {
        let app = launch([
            "-uitest-seed-library",
            "-uitest-open-add-alarm"
        ])
        allowAlarmPermissionIfNeeded(app)
        let soundRow = app.buttons["addAlarm.soundRow"]
        XCTAssertTrue(soundRow.waitForExistence(timeout: 15))
        soundRow.tap()

        XCTAssertTrue(
            app.collectionViews["alarmSoundChoice.root"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["soundPicker.addVideo"].waitForExistence(timeout: 5))
        attach("ja-sound-choice", app)
    }
}
