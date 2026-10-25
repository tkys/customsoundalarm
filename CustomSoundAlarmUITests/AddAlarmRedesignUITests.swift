import XCTest

@MainActor
final class AddAlarmRedesignUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func findElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launchAdd() {
        app.launchArguments = ["-uitest-open-add-alarm"]
        app.launch()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10),
            "add screen should appear: \(app.debugDescription)"
        )
    }

    func testOversleepDetailsAppearOnlyWhenOn() {
        launchAdd()

        app.swipeUp()
        let toggle = findElement("addAlarm.backupToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "backup toggle should exist")
        XCTAssertFalse(findElement("addAlarm.backupMinutes").exists, "off: minutes must be hidden")
        XCTAssertFalse(findElement("addAlarm.backupTestRing").exists, "off: trial must be hidden")

        toggle.tap()

        XCTAssertTrue(findElement("addAlarm.backupMinutes").waitForExistence(timeout: 3))
        XCTAssertTrue(findElement("addAlarm.backupTestRing").waitForExistence(timeout: 3))
    }

    func testOnlyOneTestRingButton() {
        launchAdd()
        XCTAssertEqual(
            app.buttons.matching(identifier: "addAlarm.testRing").count,
            1,
            "今すぐ鳴らすは1つだけ"
        )
    }

    func testEditScreenHasNoEnabledToggle() {
        app.launchArguments = ["-uitest-open-edit-alarm"]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10))

        XCTAssertFalse(app.staticTexts["アラームを有効"].exists)
        XCTAssertFalse(app.staticTexts["Alarm Enabled"].exists)
        XCTAssertFalse(findElement("addAlarm.enabledToggle").exists)
        XCTAssertTrue(findElement("addAlarm.testRing").exists)
    }

    func testSectionOrder() {
        launchAdd()
        app.swipeUp()

        let identifiers = [
            "addAlarm.repeatRow",
            "addAlarm.labelRow",
            "addAlarm.soundRow",
            "addAlarm.testRing",
            "addAlarm.snoozeRow",
            "addAlarm.backupToggle"
        ]

        var positions: [CGFloat] = []
        for identifier in identifiers {
            let element = findElement(identifier)
            XCTAssertTrue(element.waitForExistence(timeout: 5), "missing \(identifier)")
            positions.append(element.frame.origin.y)
        }

        for index in 1..<positions.count {
            XCTAssertLessThan(
                positions[index - 1],
                positions[index],
                "\(identifiers[index - 1]) should be above \(identifiers[index])"
            )
        }
    }
}
