import XCTest

/// #160 PR-1: アラームの音の行からプレイリストを作成・選択する。
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
            "-uitest-seed-library",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()

        let soundRow = app.buttons["addAlarm.soundRow"]
        XCTAssertTrue(
            soundRow.waitForExistence(timeout: 20),
            "sound row should exist: \(app.debugDescription)"
        )
        soundRow.tap()

        let addPlaylist = app.buttons["alarmSoundChoice.addPlaylist"]
        var swipes = 0
        while !addPlaylist.isHittable && swipes < 8 {
            app.collectionViews["alarmSoundChoice.root"].swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            addPlaylist.waitForExistence(timeout: 10),
            "sound choice should open: \(app.debugDescription)"
        )
        addPlaylist.tap()

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

        let playlistRow = app.buttons.matching(
            NSPredicate(format: "identifier CONTAINS %@", "UITest")
        ).firstMatch
        let choiceRoot = app.collectionViews["alarmSoundChoice.root"]
        var rowSwipes = 0
        while (!playlistRow.exists || !playlistRow.isHittable) && rowSwipes < 8 {
            choiceRoot.swipeUp()
            rowSwipes += 1
        }
        XCTAssertTrue(
            playlistRow.waitForExistence(timeout: 10),
            "created playlist should appear: \(app.debugDescription)"
        )
        playlistRow.tap()

        XCTAssertTrue(soundRow.waitForExistence(timeout: 10))
        XCTAssertTrue(
            soundRow.label.contains("UITest"),
            "selected playlist should be shown on the alarm screen: \(soundRow.label)"
        )
    }
}
