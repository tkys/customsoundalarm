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

        let backupTestRing = findElement("addAlarm.backupTestRing")
        var swipes = 0
        while (!backupTestRing.exists || !backupTestRing.isHittable) && swipes < 6 {
            app.collectionViews["addAlarm.root"].swipeUp()
            swipes += 1
        }
        XCTAssertTrue(backupTestRing.waitForExistence(timeout: 3))
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

        // 旧画面の切り替えの文言（ja/en とも完全一致）
        XCTAssertFalse(app.staticTexts["アラームをオン"].exists)
        XCTAssertFalse(app.staticTexts["Alarm Enabled"].exists)
        // フォーム内でラベルを持つ切り替えは寝過ごし防止だけ
        // （SwiftUI は同じ切り替えをラベル無しの要素でも出すので、ラベル無しは数えない）
        let form = app.collectionViews["addAlarm.root"]
        for _ in 0..<4 {
            let labeled = form.switches.allElementsBoundByIndex.filter {
                !$0.label.isEmpty && $0.identifier != "addAlarm.backupToggle"
            }
            XCTAssertTrue(labeled.isEmpty, "edit screen has another switch: \(labeled.map(\.label))")
            form.swipeUp()
        }
    }

    func testAccessibilitySizeKeepsAllRows() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        XCTAssertTrue(app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15))

        let identifiers = [
            "addAlarm.repeatRow",
            "addAlarm.labelRow",
            "addAlarm.soundRow",
            "addAlarm.fadeIn",
            "addAlarm.snoozeRow",
            "addAlarm.testRing",
            "addAlarm.backupToggle"
        ]

        for identifier in identifiers {
            let element = findElement(identifier)
            var swipes = 0
            while !element.isHittable && swipes < 12 {
                app.collectionViews["addAlarm.root"].swipeUp()
                swipes += 1
            }
            XCTAssertTrue(
                element.waitForExistence(timeout: 5),
                "AX5: missing \(identifier)"
            )
        }
    }

    func testSectionOrder() {
        launchAdd()
        app.swipeUp()

        let identifiers = [
            "addAlarm.repeatRow",
            "addAlarm.labelRow",
            "addAlarm.soundRow",
            "addAlarm.fadeIn",
            "addAlarm.snoozeRow",
            "addAlarm.testRing",
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
