import XCTest

final class UpdateGateUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testRequiredPromptHasNoLaterButton() {
        app.launchArguments = ["-uitest-update-required"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["updatePrompt.required"].waitForExistence(timeout: 10),
            "Required update prompt should appear"
        )
        XCTAssertTrue(app.buttons["updatePrompt.updateButton"].exists)
        XCTAssertFalse(app.buttons["updatePrompt.laterButton"].exists, "Required prompt must not be dismissible")
    }

    func testRecommendedPromptCanBeDismissedWithLater() {
        app.launchArguments = ["-uitest-update-recommended"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["updatePrompt.recommended"].waitForExistence(timeout: 10),
            "Recommended update prompt should appear"
        )
        let later = app.buttons["updatePrompt.laterButton"]
        XCTAssertTrue(later.waitForExistence(timeout: 2))
        later.tap()

        XCTAssertFalse(
            app.staticTexts["updatePrompt.recommended"].waitForExistence(timeout: 2),
            "Recommended prompt should be dismissed"
        )
    }
}
