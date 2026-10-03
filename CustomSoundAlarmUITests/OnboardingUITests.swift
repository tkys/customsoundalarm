import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-fresh-onboarding"]
        addUIInterruptionMonitor(withDescription: "System Dialog") { element -> Bool in
            if element.buttons["Allow"].exists { element.buttons["Allow"].tap(); return true }
            if element.buttons["許可"].exists { element.buttons["許可"].tap(); return true }
            if element.buttons["Allow Once"].exists { element.buttons["Allow Once"].tap(); return true }
            return false
        }
    }

    private func handlePermissionAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Allow"].waitForExistence(timeout: 1) {
            springboard.buttons["Allow"].tap()
            return
        }
        if springboard.buttons["許可"].waitForExistence(timeout: 1) {
            springboard.buttons["許可"].tap()
            return
        }
        if springboard.buttons["Allow Once"].waitForExistence(timeout: 1) {
            springboard.buttons["Allow Once"].tap()
            return
        }
        app.tap()
    }

    private func findElement(identifier: String) -> XCUIElement {
        return app.descendants(matching: .any)[identifier]
    }

    private func goToSourceList() {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continue"].tap()
        handlePermissionAlertIfPresent()
        XCTAssertTrue(app.buttons["onboarding.source.video"].waitForExistence(timeout: 5))
    }

    func testOnboardingVideoOpensImportDirectly() {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continue"].tap()
        handlePermissionAlertIfPresent()
        let videoButton = app.buttons["onboarding.source.video"]
        XCTAssertTrue(videoButton.waitForExistence(timeout: 5))
        videoButton.tap()

        let addRoot = app.collectionViews["addAlarm.root"]
        XCTAssertTrue(addRoot.waitForExistence(timeout: 8), "add screen should appear: \(app.debugDescription)")

        // 取り込み画面は開いた直後にソース選択ダイアログ（写真ライブラリ / ファイル）を出す。
        // このボタンは動画の取り込みにしか無いので、出ていれば直接開けている。
        // "Cancel" は追加画面のツールバーにもあるため判定に使わない（#101 偽陽性の原因）
        let photoButton = app.buttons["写真ライブラリ"]
        let photoButtonEn = app.buttons["Photo Library"]
        let videoExists = photoButtonEn.waitForExistence(timeout: 6) || photoButton.waitForExistence(timeout: 1)
        if !videoExists {
            print("DEBUG videoImport not found, hierarchy:\n\(app.debugDescription)")
        }
        XCTAssertTrue(videoExists, "video import should be presented directly on add screen")

        let empty = findElement(identifier: "empty.title")
        // Empty list is behind the sheets; check it is not hittable (visible) rather than not existing
        XCTAssertFalse(empty.isHittable && empty.waitForExistence(timeout: 1), "empty list should not be hittable when import is open")
    }

    func testOnboardingAudioOpensFileImporter() {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continue"].tap()
        handlePermissionAlertIfPresent()
        let audioButton = app.buttons["onboarding.source.audio"]
        XCTAssertTrue(audioButton.waitForExistence(timeout: 5))
        audioButton.tap()

        let addRoot = findElement(identifier: "addAlarm.root")
        XCTAssertTrue(addRoot.waitForExistence(timeout: 8))

        // ファイル選択（UIDocumentPicker）固有のナビゲーションバー。追加画面の "Cancel" では判定しない
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(picker.waitForExistence(timeout: 6), "file importer should be presented: \(app.debugDescription)")
    }

    func testOnboardingPresetPreselects() {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continue"].tap()
        handlePermissionAlertIfPresent()
        let presetButton = app.buttons["onboarding.source.preset"]
        XCTAssertTrue(presetButton.waitForExistence(timeout: 5))
        presetButton.tap()

        let addRoot = findElement(identifier: "addAlarm.root")
        XCTAssertTrue(addRoot.waitForExistence(timeout: 8))
        // サウンド行に「なし」以外（＝プリセット先頭）が入っていること。
        // 大文字小文字の違い（実表示は "None"）で常に真にならないよう、表示文字列と完全一致で比べる
        let soundName = app.staticTexts["addAlarm.soundName"]
        XCTAssertTrue(soundName.waitForExistence(timeout: 3))
        let label = soundName.label
        XCTAssertFalse(label.isEmpty || label == "None" || label == "なし", "preset should be preselected, found label: \(label)")
    }

    func testOnboardingLaterGoesToList() {
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 5))
        app.buttons["onboarding.continue"].tap()
        handlePermissionAlertIfPresent()
        let laterButton = app.buttons["onboarding.later"]
        XCTAssertTrue(laterButton.waitForExistence(timeout: 5))
        laterButton.tap()
        let empty = findElement(identifier: "empty.title")
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "empty list should be visible after Later")
    }
}
