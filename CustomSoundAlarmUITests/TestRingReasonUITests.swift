import XCTest

/// 「今すぐ鳴らす」が鳴らせない理由をその場で表示する（#150）。
/// 許可が無い／拒否済みの状態で、行の下に理由と『設定を開く』が出ることを
/// 表示文字列・識別子の完全一致で検証する。
@MainActor
final class TestRingReasonUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func findElement(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launchAdd(permissionFlag: String, language: String, locale: String) {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            permissionFlag,
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        app.launch()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10),
            "add screen should appear: \(app.debugDescription)"
        )
    }

    /// 「今すぐ鳴らす」の行が見えるまでスクロールする
    @discardableResult
    private func scrollToTestRing() -> Bool {
        let form = app.collectionViews["addAlarm.root"]
        for _ in 0..<4 {
            if findElement("addAlarm.testRing").isHittable { return true }
            form.swipeUp()
        }
        return findElement("addAlarm.testRing").exists
    }

    func testDeniedShowsReasonAndOpenSettingsJapanese() {
        launchAdd(
            permissionFlag: "-uitest-test-ring-denied",
            language: "ja",
            locale: "ja_JP"
        )
        XCTAssertTrue(scrollToTestRing(), "今すぐ鳴らすの行が出るはず")

        let reason = findElement("addAlarm.testRingReason")
        XCTAssertTrue(
            reason.waitForExistence(timeout: 5),
            "拒否済みなら『今すぐ鳴らす』の下に理由が出るはず: \(app.debugDescription)"
        )
        XCTAssertEqual(reason.label, "アラームの許可が拒否されています。設定を開いて「アラーム」を許可してください。")

        let settings = findElement("addAlarm.openSettings")
        XCTAssertTrue(settings.waitForExistence(timeout: 3), "直し方に『設定を開く』が出るはず")
        XCTAssertEqual(settings.label, "設定を開く")

        // 無効化したボタンだけを見せない（#150）
        XCTAssertTrue(findElement("addAlarm.testRing").isEnabled, "ボタンは無効化しっぱなしにしない")
    }

    func testDeniedShowsReasonAndOpenSettingsEnglish() {
        launchAdd(
            permissionFlag: "-uitest-test-ring-denied",
            language: "en",
            locale: "en_US"
        )
        XCTAssertTrue(scrollToTestRing(), "test ring row should be reachable")

        let reason = findElement("addAlarm.testRingReason")
        XCTAssertTrue(
            reason.waitForExistence(timeout: 5),
            "denied: the reason should appear below 'Ring now': \(app.debugDescription)"
        )
        XCTAssertEqual(reason.label, "Alarm access is blocked. Open Settings and allow alarms.")

        let settings = findElement("addAlarm.openSettings")
        XCTAssertTrue(settings.waitForExistence(timeout: 3), "'Open Settings' should appear")
        XCTAssertEqual(settings.label, "Open Settings")
    }

    func testNotDeterminedShowsReasonAndOpenSettingsJapanese() {
        launchAdd(
            permissionFlag: "-uitest-test-ring-not-determined",
            language: "ja",
            locale: "ja_JP"
        )
        XCTAssertTrue(scrollToTestRing(), "今すぐ鳴らすの行が出るはず")

        let reason = findElement("addAlarm.testRingReason")
        XCTAssertTrue(
            reason.waitForExistence(timeout: 5),
            "許可がまだなら『今すぐ鳴らす』の下に理由が出るはず: \(app.debugDescription)"
        )
        XCTAssertEqual(reason.label, "まだ許可が下りていないため鳴らせません。設定を開いて「アラーム」を許可してください。")
        XCTAssertTrue(findElement("addAlarm.openSettings").waitForExistence(timeout: 3))
    }

    /// 「音が小さいときは」はメインのボタンと同じ行の右端ではなく、行の下（#150）。
    func testVolumeGuideLinkIsBelowTestRingRow() {
        launchAdd(
            permissionFlag: "-uitest-test-ring-denied",
            language: "ja",
            locale: "ja_JP"
        )
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 10),
            "add screen should appear: \(app.debugDescription)"
        )

        let form = app.collectionViews["addAlarm.root"]
        let button = findElement("addAlarm.testRing")
        let link = findElement("addAlarm.volumeGuide")
        for _ in 0..<4 {
            if link.isHittable && button.exists { break }
            form.swipeUp()
        }
        XCTAssertTrue(link.isHittable, "『音が小さいときは』リンクは常に出るはず: \(app.debugDescription)")
        XCTAssertTrue(button.exists, "『今すぐ鳴らす』の行が出るはず")

        XCTAssertGreaterThan(
            link.frame.minY,
            button.frame.maxY,
            "『音が小さいときは』は『今すぐ鳴らす』と同じ行の右端ではなく行の下にあるべき"
        )
    }
}
