import XCTest

/// 設定画面と、そこからのナイトモード（#204）。
final class SettingsUITests: XCTestCase {

    func testGearOpensSettingsAndNightMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-seed-design-audit"]
        app.launch()

        let gear = app.buttons["alarmList.settings"]
        XCTAssertTrue(
            gear.waitForExistence(timeout: 15),
            "settings gear should appear: \(app.debugDescription)"
        )
        gear.tap()

        let settings = app.descendants(matching: .any)["settings.root"]
        XCTAssertTrue(
            settings.waitForExistence(timeout: 10),
            "settings should open: \(app.debugDescription)"
        )
        for identifier in [
            "settings.bedside",
            "settings.contact",
            "settings.review",
            "settings.howto",
            "settings.privacy",
            "settings.version",
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].exists,
                "missing \(identifier): \(app.debugDescription)"
            )
        }

        app.buttons["settings.bedside"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["bedside.root"].waitForExistence(timeout: 15),
            "night mode should open: \(app.debugDescription)"
        )
    }
}
