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
    /// キャンセルしたら次回も開き、保存したら staging から消える（#222）。
    func testSharedAudioOpensCropAndKeepsUntilSaved() {
        launch(seed: true)
        var crop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(
            crop.waitForExistence(timeout: 20),
            "crop should open for a shared audio: \(app.debugDescription)"
        )

        // キャンセルしても staging は残る
        cancelCrop()
        waitUntilGone(crop)
        app.terminate()

        launch(seed: false)
        crop = findElement("audioCrop.cropAndSave")
        XCTAssertTrue(
            crop.waitForExistence(timeout: 20),
            "cancelled share should open again: \(app.debugDescription)"
        )

        // 保存すると staging から消え、次回は開かない
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
}
