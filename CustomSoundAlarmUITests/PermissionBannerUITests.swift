import XCTest

@MainActor
final class PermissionBannerUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// 拒否済みでオンのアラームがあるとき、一覧の一番上に1行出る。
    func testDeniedShowsBannerAtTop() {
        app.launchArguments = [
            "-uitest-seed-enabled-alarms",
            "-uitest-alarm-permission-denied",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        app.launch()

        let banner = app.staticTexts["alarmList.permissionBanner"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: 15),
            "permission banner should appear: \(app.debugDescription)"
        )
        XCTAssertTrue(
            app.buttons["alarmList.permissionAllow"].exists,
            "allow button should appear: \(app.debugDescription)"
        )

        let alarmTime = app.staticTexts["6:24"]
        XCTAssertTrue(
            alarmTime.waitForExistence(timeout: 10),
            app.debugDescription
        )
        XCTAssertLessThan(
            banner.frame.origin.y,
            alarmTime.frame.origin.y,
            "banner should be above the alarm row"
        )
    }

    /// 許可済みなら出さない。
    func testAuthorizedHidesBanner() {
        app.launchArguments = [
            "-uitest-seed-enabled-alarms",
            "-uitest-alarm-permission-authorized",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["6:24"].waitForExistence(timeout: 15))
        XCTAssertFalse(
            app.staticTexts["alarmList.permissionBanner"].waitForExistence(timeout: 3),
            "banner should be hidden when authorized: \(app.debugDescription)"
        )
    }

    /// denied のときは、設定アプリの前にシートを1枚はさむ（#239）。
    func testDeniedShowsSettingsSheetBeforeOpeningSettings() {
        app.launchArguments = [
            "-uitest-seed-enabled-alarms",
            "-uitest-alarm-permission-denied"
        ]
        app.launch()

        let allow = app.buttons["alarmList.permissionAllow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 15), app.debugDescription)
        allow.tap()

        XCTAssertTrue(
            app.staticTexts["permissionSettings.hint"].waitForExistence(timeout: 10),
            "settings sheet should appear: \(app.debugDescription)"
        )
        XCTAssertTrue(app.buttons["permissionSettings.open"].exists)
    }
}
