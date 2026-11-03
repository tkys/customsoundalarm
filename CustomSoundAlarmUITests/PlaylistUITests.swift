import XCTest

/// #151: プレイリストの作成・曲追加・選択。
@MainActor
final class PlaylistUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCreatePlaylistAndSelectIt() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-open-playlist",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()

        XCTAssertTrue(
            app.buttons["playlist.add"].waitForExistence(timeout: 20),
            "playlist picker should open: \(app.debugDescription)"
        )
        app.buttons["playlist.add"].tap()

        let nameField = app.textFields["playlist.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("UITest")

        app.buttons["playlist.addTrack"].tap()
        let track = app.buttons["playlist.track.PresetMarimba.caf"]
        XCTAssertTrue(
            track.waitForExistence(timeout: 10),
            "track picker should show preset: \(app.debugDescription)"
        )
        track.tap()
        app.buttons["playlist.closeTrackPicker"].tap()
        app.buttons["playlist.save"].tap()

        let row = app.buttons.matching(
            NSPredicate(format: "identifier CONTAINS %@", "UITest")
        ).firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "created playlist should appear: \(app.debugDescription)"
        )
        row.tap()

        let playlistRow = app.buttons["addAlarm.playlistRow"]
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 10))
        XCTAssertTrue(
            playlistRow.label.contains("UITest"),
            "selected playlist should be shown on the alarm screen: \(playlistRow.label)"
        )
    }
}
