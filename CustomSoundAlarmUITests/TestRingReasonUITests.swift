import XCTest

/// 「今すぐ鳴らす」が鳴らせない理由をその場で表示する（#150）。
/// 許可が無いときは理由の文と『許可する』、拒否済みのときは
/// 短い状態 +『設定を開く』を出すことを検証する（#290）。
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

        // #290: 理由の長い文は出さず、短い状態 +『設定を開く』にする。
        // 理由は VoiceOver のラベルに残す。
        XCTAssertFalse(
            findElement("addAlarm.testRingReason").exists,
            "拒否済みでも理由の長い文は画面に出さない: \(app.debugDescription)"
        )

        let status = findElement("addAlarm.testRingStatus")
        var swipes = 0
        while !status.exists && swipes < 3 {
            app.collectionViews["addAlarm.root"].swipeUp()
            swipes += 1
        }
        XCTAssertTrue(status.waitForExistence(timeout: 3), "何が困っているかの一言を出す")
        XCTAssertEqual(status.label, "アラームが鳴りません")

        let settings = findElement("addAlarm.openSettings")
        swipes = 0
        while !settings.exists && swipes < 3 {
            app.collectionViews["addAlarm.root"].swipeUp()
            swipes += 1
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 3), "直し方に『設定を開く』が出るはず")
        XCTAssertEqual(
            settings.label,
            "アラームの許可がオフのため、アラームは鳴りません。設定を開いて「アラーム」をオンにしてください。",
            "VoiceOver には理由を伝える"
        )

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

        // #290: the long sentence is replaced by a short status + 'Open Settings'.
        // VoiceOver keeps the reason.
        XCTAssertFalse(
            findElement("addAlarm.testRingReason").exists,
            "denied: the long sentence should not be shown: \(app.debugDescription)"
        )

        let status = findElement("addAlarm.testRingStatus")
        var swipes = 0
        while !status.exists && swipes < 3 {
            app.collectionViews["addAlarm.root"].swipeUp()
            swipes += 1
        }
        XCTAssertTrue(status.waitForExistence(timeout: 3), "the short status should appear")
        XCTAssertEqual(status.label, "Alarms won't ring")

        let settings = findElement("addAlarm.openSettings")
        swipes = 0
        while !settings.exists && swipes < 3 {
            app.collectionViews["addAlarm.root"].swipeUp()
            swipes += 1
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 3), "'Open Settings' should appear")
        XCTAssertEqual(
            settings.label,
            "Alarms are turned off for My Sound Alarm, so they won't ring. Open Settings and turn on Alarms.",
            "VoiceOver should still hear why alarms are off"
        )
    }

    func testNotDeterminedShowsReasonAndAllowButtonJapanese() {
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
        XCTAssertEqual(reason.label, "アラームがまだ許可されていません。許可するまで、アラームは鳴りません。")
        let allow = findElement("addAlarm.allowAlarms")
        XCTAssertTrue(allow.waitForExistence(timeout: 3), "許可がまだならその場で『許可する』を出す")
        XCTAssertEqual(allow.label, "許可する")
        XCTAssertFalse(findElement("addAlarm.openSettings").exists, "許可がまだなら設定へは送らない")
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
