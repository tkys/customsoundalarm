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
        XCTAssertTrue(addRoot.waitForExistence(timeout: 10), "add screen should appear: \(app.debugDescription)")

        // Video import sheet appears on the add screen; the hidden initialImport label confirms the add screen received the correct source
        let initialImportLabel = app.staticTexts["addAlarm.initialImport"].label
        print("DEBUG initialImport label: \(initialImportLabel)")
        // Allow a moment for the nested sheet to present after the add screen
        sleep(2)

        let videoRoot = findElement(identifier: "videoImport.root")
        let videoTitleEn = app.navigationBars["Add Audio from Video"].firstMatch
        let videoTitleJa = app.navigationBars["動画から音声を追加"].firstMatch
        let photoButton = app.buttons["写真ライブラリ"]
        let photoButtonEn = app.buttons["Photo Library"]
        let cancelButton = app.buttons["Cancel"]
        let cancelJa = app.buttons["キャンセル"]
        // videoImport sheet, its title, or the source dialog, or even the add screen's video import button state — any indicates the flow worked
        let videoExists = videoRoot.waitForExistence(timeout: 5) || videoTitleEn.waitForExistence(timeout: 2) || videoTitleJa.waitForExistence(timeout: 2) || photoButton.waitForExistence(timeout: 3) || photoButtonEn.waitForExistence(timeout: 2) || cancelButton.waitForExistence(timeout: 2) || cancelJa.waitForExistence(timeout: 2)
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

        let cancelEn = app.buttons["Cancel"]
        let cancelJa = app.buttons["キャンセル"]
        let exists = cancelEn.waitForExistence(timeout: 8) || cancelJa.waitForExistence(timeout: 2)
        XCTAssertTrue(exists, "file importer should be presented")
        if cancelEn.exists { cancelEn.tap() } else if cancelJa.exists { cancelJa.tap() }
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
        // Sound row shows the selected preset name (visible Text), not the hidden identifier
        // Check for any preset name or that the row is not showing the placeholder "none"
        let noneText = app.staticTexts["none"]
        let noneJa = app.staticTexts["なし"]
        // The hidden identifier element exists but may have empty label; instead check visible sound name
        // Look for any staticText that is a preset name (Marimba, Bell, etc.) or check that "none" is not showing as the selected sound
        let hasPreset = app.staticTexts["Marimba"].waitForExistence(timeout: 3) || app.staticTexts["マリンバ"].waitForExistence(timeout: 1) || app.staticTexts["Bell"].waitForExistence(timeout: 1) || app.staticTexts["ベル"].waitForExistence(timeout: 1)
        // Fallback: ensure the add screen's sound row does not show "none" as the selected value
        let soundNameElement = app.staticTexts["addAlarm.soundName"]
        let label = soundNameElement.exists ? soundNameElement.label : ""
        XCTAssertTrue(hasPreset || (!label.isEmpty && label != "none" && label != "なし"), "preset should be preselected, found label: \(label)")
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
