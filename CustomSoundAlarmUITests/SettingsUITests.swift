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

    /// #255: メールが使えない端末では共有シートに診断ファイルを渡す。
    func testContactOpensShareSheetWhenMailUnavailable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uitest-seed-design-audit",
            "-uitest-contact-no-mail",
            "-uitest-force-light",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let gear = app.buttons["alarmList.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 15), app.debugDescription)
        gear.tap()

        let contact = app.descendants(matching: .any)["settings.contact"]
        XCTAssertTrue(contact.waitForExistence(timeout: 10), app.debugDescription)
        contact.tap()

        let shareSheet = app.descendants(matching: .any)["settings.shareSheet"]
        XCTAssertTrue(
            shareSheet.waitForExistence(timeout: 30),
            "share sheet should open: \(app.debugDescription)"
        )
        // 診断ファイルが共有項目として渡っている
        let attachment = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "diagnostics")
        ).firstMatch
        XCTAssertTrue(
            attachment.waitForExistence(timeout: 10),
            "diagnostics file should be attached: \(app.debugDescription)"
        )

        // 次のテストに共有シートを残さない（#270）
        app.terminate()
    }
}
