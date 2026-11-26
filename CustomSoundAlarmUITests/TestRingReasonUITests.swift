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

    private func launchAdd(
        permissionFlag: String,
        language: String,
        locale: String,
        extraArguments: [String] = []
    ) {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            permissionFlag,
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ] + extraArguments
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

    /// #309: 追加画面から開いたガイドの一番下に「今すぐ鳴らす」があり、
    /// 押すとガイドが閉じて、追加画面の試し鳴らしが始まる。
    func testVolumeGuideFromEditorRingsNowAtBottomAndClosesToStartTestRing() {
        launchAdd(
            permissionFlag: "-uitest-test-ring-allowed",
            language: "en",
            locale: "en_US"
        )

        let form = app.collectionViews["addAlarm.root"]
        let link = findElement("addAlarm.volumeGuide")
        for _ in 0..<4 {
            if link.isHittable { break }
            form.swipeUp()
        }
        XCTAssertTrue(link.isHittable, "the volume guide link should be reachable")
        let editorRingLabel = findElement("addAlarm.testRing").label
        // 行の中央は空白で、押せるのは左の文字のところ（#150 の小さなリンク）。
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()

        let guide = findElement("volumeGuide.root")
        XCTAssertTrue(guide.waitForExistence(timeout: 10), app.debugDescription)

        let scroll = app.scrollViews.firstMatch
        let warning = findElement("volumeGuide.warning")
        let ringNow = findElement("volumeGuide.testRing")
        for _ in 0..<5 {
            if ringNow.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(ringNow.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(ringNow.isHittable, "the button should be at the bottom of the guide")
        XCTAssertEqual(
            ringNow.label,
            editorRingLabel,
            "the guide should use the same title as the editor's test ring"
        )
        XCTAssertTrue(ringNow.isEnabled, "allowed: the button should be tappable")
        XCTAssertGreaterThan(
            ringNow.frame.minY,
            warning.frame.maxY,
            "the button should come after the warning, at the bottom"
        )
        XCTAssertGreaterThan(
            ringNow.frame.width,
            guide.frame.width * 0.8,
            "the button should be full width"
        )

        ringNow.tap()

        // 結果の文は4秒で消えるため、ガイドの閉じ待ちより先に拾う（#297）。
        XCTAssertTrue(
            app.staticTexts["Trial ring is available on a real device only."]
                .waitForExistence(timeout: 5),
            "the editor's test ring should have run: \(app.debugDescription)"
        )
        XCTAssertTrue(
            guide.waitForNonExistence(timeout: 5),
            "the guide should close before the test ring starts"
        )
        XCTAssertTrue(form.waitForExistence(timeout: 5), app.debugDescription)
    }

    /// #309: アラームの許可がないときは、ガイドの「今すぐ鳴らす」を押せない。
    func testVolumeGuideRingNowDisabledWithoutPermission() {
        launchAdd(
            permissionFlag: "-uitest-test-ring-denied",
            language: "en",
            locale: "en_US"
        )

        let form = app.collectionViews["addAlarm.root"]
        let link = findElement("addAlarm.volumeGuide")
        for _ in 0..<4 {
            if link.isHittable { break }
            form.swipeUp()
        }
        XCTAssertTrue(link.isHittable, "the volume guide link should be reachable")
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()

        let guide = findElement("volumeGuide.root")
        XCTAssertTrue(guide.waitForExistence(timeout: 10), app.debugDescription)
        let ringNow = findElement("volumeGuide.testRing")
        for _ in 0..<5 {
            if ringNow.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(ringNow.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(ringNow.isEnabled, "denied: the button should not be tappable")
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

    // MARK: - 押した直後の状態（#310）

    /// 押した瞬間に「まもなく鳴ります」になり、押せなくなる。
    /// シミュレータでは鳴らせないため、失敗して待機に戻り理由が出るところまで。
    func testPressedShowsWaitingThenReturnsToIdleOnSimulatorFailure() {
        launchAdd(
            permissionFlag: "-uitest-test-ring-allowed",
            language: "ja",
            locale: "ja_JP",
            extraArguments: ["-uitest-test-ring-waiting-hold"]
        )
        XCTAssertTrue(scrollToTestRing(), "試しに鳴らすの行が出るはず")

        let button = findElement("addAlarm.testRing")
        XCTAssertEqual(button.label, "試しに鳴らす")
        XCTAssertTrue(button.isEnabled, "待機中は押せる")

        // 行の中央は空白。押せるのは左の文字のところ（#150）。
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()

        XCTAssertTrue(
            waitForLabel("まもなく鳴ります", on: button, timeout: 3),
            "押した瞬間から待機の文言になる: \(app.debugDescription)"
        )
        XCTAssertFalse(button.isEnabled, "鳴るまでの間は押せない")

        XCTAssertTrue(
            waitForLabel("試しに鳴らす", on: button, timeout: 10),
            "シミュレータでは失敗して待機へ戻る: \(app.debugDescription)"
        )
        XCTAssertTrue(button.isEnabled, "待機へ戻ったら押せる")
        XCTAssertTrue(
            app.staticTexts["試しに鳴らすは実機でのみ使えます。"]
                .waitForExistence(timeout: 5),
            "失敗の理由は残す: \(app.debugDescription)"
        )
    }

    /// 失敗したときは、理由を出して待機に戻る（#310）。
    func testSimulatorFailureReturnsToIdleAndShowsReason() {
        launchAdd(
            permissionFlag: "-uitest-test-ring-allowed",
            language: "en",
            locale: "en_US"
        )
        XCTAssertTrue(scrollToTestRing(), "test ring row should be reachable")

        let button = findElement("addAlarm.testRing")
        XCTAssertEqual(button.label, "Test Ring")
        // 行の中央は空白。押せるのは左の文字のところ（#150）。
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()

        XCTAssertTrue(
            app.staticTexts["Trial ring is available on a real device only."]
                .waitForExistence(timeout: 8),
            "the failure reason should appear: \(app.debugDescription)"
        )
        XCTAssertTrue(
            waitForLabel("Test Ring", on: button, timeout: 5),
            "failure should return the button to idle: \(app.debugDescription)"
        )
        XCTAssertTrue(button.isEnabled, "idle: the button should be tappable again")
    }

    /// 文字が変わっても行の高さが跳ねない（Dynamic Type の最大でも・#310）。
    func testWaitingKeepsRowHeightAtAccessibilitySize() {
        launchAdd(
            permissionFlag: "-uitest-test-ring-allowed",
            language: "ja",
            locale: "ja_JP",
            extraArguments: [
                "-uitest-test-ring-waiting-hold",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        )
        XCTAssertTrue(scrollToTestRing(), "試しに鳴らすの行が出るはず")

        let button = findElement("addAlarm.testRing")
        let idleHeight = button.frame.height

        button.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(
            waitForLabel("まもなく鳴ります", on: button, timeout: 3),
            "押した瞬間から待機の文言になる: \(app.debugDescription)"
        )

        XCTAssertEqual(
            button.frame.height,
            idleHeight,
            accuracy: 0.5,
            "「まもなく鳴ります」に変わっても行の高さを変えない"
        )
    }

    /// PR 用: 押した直後の「まもなく鳴ります」を1枚だけ撮る。
    /// `TEST_RUNNER_TEST_RING_SCREENSHOTS=1` のときだけ実行する。
    func testCaptureWaitingScreenshot() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TEST_RING_SCREENSHOTS"] == "1",
            "Test ring screenshots run only with TEST_RUNNER_TEST_RING_SCREENSHOTS=1"
        )
        launchAdd(
            permissionFlag: "-uitest-test-ring-allowed",
            language: "ja",
            locale: "ja_JP",
            extraArguments: ["-uitest-test-ring-waiting-hold"]
        )
        XCTAssertTrue(scrollToTestRing(), "試しに鳴らすの行が出るはず")

        let button = findElement("addAlarm.testRing")
        // 行の中央は空白。押せるのは左の文字のところ（#150）。
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(
            waitForLabel("まもなく鳴ります", on: button, timeout: 3),
            app.debugDescription
        )
        Thread.sleep(forTimeInterval: 0.5)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "test-ring-waiting"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForLabel(
        _ label: String,
        on element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.label == label { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return element.exists && element.label == label
    }
}
