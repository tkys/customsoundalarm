import XCTest

@MainActor
final class ShareImportUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func findElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// 共有された音は起動時に切り取り画面が開く。
    /// 自分で × を押して閉じた分も保存した分も staging から消え、次回は開かない（#222）。
    func testSharedAudioOpensCropAndIsClearedAfterCloseOrSave() {
        // × で閉じる → 次回は開かない
        launch(seed: true)
        var crop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(
            crop.waitForExistence(timeout: 20),
            "crop should open for a shared audio: \(app.debugDescription)"
        )

        cancelCrop()
        waitUntilGone(crop)
        app.terminate()

        launch(seed: false)
        XCTAssertFalse(
            findElement("audioCrop.cropAndSave").waitForExistence(timeout: 4),
            "closed share should not open again: \(app.debugDescription)"
        )

        // 別の共有を保存 → 次回は開かない
        app.terminate()
        launch(seed: true)
        crop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(
            crop.waitForExistence(timeout: 20),
            "crop should open for a newly shared audio: \(app.debugDescription)"
        )
        crop.tap()
        waitUntilGone(crop)
        app.terminate()

        launch(seed: false)
        XCTAssertFalse(
            findElement("audioCrop.cropAndSave").waitForExistence(timeout: 4),
            "saved share should not open again: \(app.debugDescription)"
        )
    }

    private func launch(seed: Bool) {
        app.launchArguments = seed
            ? [
                "-uitest-seed-share-import-audio",
                "-uitest-force-light"
            ]
            : [
                "-uitest-keep-share-import",
                "-uitest-force-light"
            ]
        // 前のテストの共有シート・プロセスを残さない（#270）
        app.terminate()
        app.launch()
    }

    private func cancelCrop() {
        let close = app.buttons["audioCrop.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        close.tap()
        let discard = app.buttons.matching(
            NSPredicate(format: "label == '破棄' OR label == 'Discard'")
        ).firstMatch
        if discard.waitForExistence(timeout: 2) {
            discard.tap()
        }
    }

    private func waitUntilGone(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 20), .completed)
    }

    /// アラームが無いときは、保存後に追加画面で取り込んだ音が選ばれている（#246）。
    func testSharedImportWithNoAlarmsLandsOnAddAlarm() {
        app.launchArguments = [
            "-uitest-seed-share-import-audio",
            "-uitest-clear-alarms",
            "-uitest-reset-sounds",
            "-uitest-force-light"
        ]
        app.launch()

        let crop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(crop.waitForExistence(timeout: 20), app.debugDescription)
        crop.tap()

        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 20),
            "add alarm should open after saving the shared sound: \(app.debugDescription)"
        )
        let sound = findElement("addAlarm.soundName")
        XCTAssertTrue(sound.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(
            sound.label.contains("Shared Sound"),
            "shared sound should be selected: \(sound.label)"
        )
    }

    /// アラームがあるときは、保存後にライブラリで取り込んだ音が見える（#246）。
    func testSharedImportWithAlarmsLandsInLibrary() {
        app.launchArguments = [
            "-uitest-seed-share-import-audio",
            "-uitest-seed-alarms",
            "-uitest-reset-sounds",
            "-uitest-force-light"
        ]
        app.launch()

        let crop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(crop.waitForExistence(timeout: 20), app.debugDescription)
        crop.tap()

        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 20),
            "library should open after saving the shared sound: \(app.debugDescription)"
        )
        XCTAssertTrue(
            app.buttons["Shared Sound"].firstMatch.waitForExistence(timeout: 10),
            "shared sound row should be visible: \(app.debugDescription)"
        )
    }

    /// ライブラリから取り込んだときも、アラームが無ければ追加画面に着地する（#246）。
    func testLibraryImportWithNoAlarmsLandsOnAddAlarm() {
        app.launchArguments = [
            "-uitest-seed-suggestion",
            "-uitest-clear-alarms",
            "-uitest-open-library",
            "-uitest-library-import-landing",
            "-uitest-force-light"
        ]
        app.launch()

        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 20),
            "add alarm should open after a library import: \(app.debugDescription)"
        )
        let sound = findElement("addAlarm.soundName")
        XCTAssertTrue(sound.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(
            sound.label.contains("Suggestion Bell") || sound.label.contains("Suggestion Marimba"),
            "imported sound should be selected: \(sound.label)"
        )
    }

    /// アラームがあるライブラリ取り込みは、ライブラリのまま（#246）。
    func testLibraryImportWithAlarmsStaysInLibrary() {
        app.launchArguments = [
            "-uitest-seed-suggestion",
            "-uitest-seed-alarms",
            "-uitest-open-library",
            "-uitest-library-import-landing",
            "-uitest-force-light"
        ]
        app.launch()

        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 20),
            app.debugDescription
        )
        XCTAssertTrue(
            app.buttons["Suggestion Bell"].waitForExistence(timeout: 10),
            app.debugDescription
        )
    }

    /// 小さい音を取り込んだ直後、音量の一言は音の行の中に出す（#253）。
    func testLibraryImportShowsVolumeNoticeInTheSameRow() {
        app.launchArguments = [
            "-uitest-seed-suggestion",
            "-uitest-seed-alarms",
            "-uitest-open-library",
            "-uitest-library-import-landing",
            "-uitest-quiet-crop",
            "-uitest-force-light"
        ]
        app.launch()

        XCTAssertTrue(
            app.collectionViews["library.root"].waitForExistence(timeout: 20),
            app.debugDescription
        )

        let notice = findElement("library.volumeNotice")
        XCTAssertTrue(
            notice.waitForExistence(timeout: 10),
            "quiet import should show the volume notice: \(app.debugDescription)"
        )

        let sound = app.buttons["library.sound.SuggestionBell.caf"]
        XCTAssertTrue(
            sound.waitForExistence(timeout: 5),
            "imported sound should be visible: \(app.debugDescription)"
        )

        let row = app.cells.containing(
            .button,
            identifier: "library.sound.SuggestionBell.caf"
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(
            row.descendants(matching: .any)
                .matching(identifier: "library.volumeNotice")
                .firstMatch
                .exists,
            "the notice should be inside the sound row: \(app.debugDescription)"
        )
        XCTAssertTrue(
            row.frame.insetBy(dx: -1, dy: -1).contains(notice.frame),
            "the notice should stay inside one row (row \(row.frame), notice \(notice.frame))"
        )
        XCTAssertEqual(
            app.cells.containing(
                .button,
                identifier: "library.sound.SuggestionBell.caf"
            ).count,
            1,
            "one sound should stay one row"
        )
        XCTAssertTrue(
            notice.frame.minY >= sound.frame.maxY,
            "the notice should sit below the sound name (sound \(sound.frame), notice \(notice.frame))"
        )
    }
}
