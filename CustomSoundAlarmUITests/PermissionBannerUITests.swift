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
            "-uitest-alarm-permission-denied"
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

        let alarmTime = app.staticTexts["23:44"]
        XCTAssertTrue(alarmTime.waitForExistence(timeout: 10))
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
            "-uitest-alarm-permission-authorized"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["23:44"].waitForExistence(timeout: 15))
        XCTAssertFalse(
            app.staticTexts["alarmList.permissionBanner"].waitForExistence(timeout: 3),
            "banner should be hidden when authorized: \(app.debugDescription)"
        )
    }
}
