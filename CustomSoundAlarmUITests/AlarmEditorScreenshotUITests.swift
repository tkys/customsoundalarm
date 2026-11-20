import XCTest

/// #211 の PR 用スクリーンショット（新規作成・編集＋寝過ごし防止オン・その他の中）。
/// `TEST_RUNNER_EDITOR_SCREENSHOTS=1 xcodebuild test ...` のときだけ実行する。
@MainActor
final class AlarmEditorScreenshotUITests: XCTestCase {

    private struct Context {
        let language: String
        let locale: String
        let dark: Bool
        let ax5: Bool

        var name: String {
            "\(language)-\(dark ? "dark" : "light")-\(ax5 ? "ax5" : "standard")"
        }
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["EDITOR_SCREENSHOTS"] == "1",
            "Editor screenshots run only with TEST_RUNNER_EDITOR_SCREENSHOTS=1"
        )
        continueAfterFailure = true
    }

    func testCaptureAll() {
        let contexts: [Context] = [
            Context(language: "ja", locale: "ja_JP", dark: false, ax5: false),
            Context(language: "ja", locale: "ja_JP", dark: true, ax5: false),
            Context(language: "ja", locale: "ja_JP", dark: false, ax5: true),
            Context(language: "ja", locale: "ja_JP", dark: true, ax5: true),
            Context(language: "en", locale: "en_US", dark: false, ax5: false),
            Context(language: "en", locale: "en_US", dark: true, ax5: false),
            Context(language: "en", locale: "en_US", dark: false, ax5: true),
            Context(language: "en", locale: "en_US", dark: true, ax5: true)
        ]
        for context in contexts {
            captureAdd(context)
            captureEditBackup(context)
            captureEditBackupWarning(context)
        }
    }

    // MARK: - New alarm

    private func captureAdd(_ context: Context) {
        let app = launch(
            context,
            arguments: ["-uitest-seed-design-audit", "-uitest-open-add-alarm"]
        )
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 25),
            "add screen did not appear: \(app.debugDescription)"
        )
        allowPermissionIfAsked()
        settle()
        attach(app, "alarm-editor-add-\(context.name)")

        // 行の並び（サウンド→繰り返し→寝過ごし防止→今すぐ鳴らす→その他）が見える位置。
        // 標準サイズでは「その他」が画面のすぐ下にあり isHittable が真になるため、
        // 1回だけ確実にスクロールしてから撮る。
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        start.press(
            forDuration: 0.1,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
        Thread.sleep(forTimeInterval: 0.4)

        let more = app.descendants(matching: .any)["addAlarm.moreRow"]
        scrollTo(more, in: app)
        XCTAssertTrue(
            more.waitForExistence(timeout: 5),
            "more row did not appear: \(app.debugDescription)"
        )
        settle()
        attach(app, "alarm-editor-add-lower-\(context.name)")

        // 「その他」の中
        more.tap()
        XCTAssertTrue(
            app.collectionViews["addAlarm.more.root"].waitForExistence(timeout: 15),
            "more screen did not appear: \(app.debugDescription)"
        )
        settle()
        attach(app, "alarm-editor-more-\(context.name)")
        app.terminate()
    }

    // MARK: - Edit with oversleep guard on

    private func captureEditBackup(_ context: Context) {
        let app = launch(
            context,
            arguments: ["-uitest-seed-design-audit", "-uitest-open-edit-alarm"]
        )
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 25),
            "edit screen did not appear: \(app.debugDescription)"
        )
        allowPermissionIfAsked()

        let toggle = app.descendants(matching: .any)["addAlarm.backupToggle"]
        scrollTo(toggle, in: app)
        toggle.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["addAlarm.backupDescription"]
                .waitForExistence(timeout: 5),
            "backup description did not appear: \(app.debugDescription)"
        )
        // 標準サイズはトグル＋実時刻＋分＋試すが1画面に収まる。
        // AX5 はスクロールするとトグルが画面外へ出るので、トグルが見えている位置で撮る。
        if !context.ax5 {
            scrollTo(
                app.descendants(matching: .any)["addAlarm.backupTestRing"],
                in: app
            )
        }
        settle()
        attach(app, "alarm-editor-edit-backup-\(context.name)")
        app.terminate()
    }

    // MARK: - Edit with oversleep warning

    private func captureEditBackupWarning(_ context: Context) {
        let app = launch(
            context,
            arguments: ["-uitest-seed-backup-warning", "-uitest-open-edit-alarm"]
        )
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 25),
            "edit screen did not appear: \(app.debugDescription)"
        )
        allowPermissionIfAsked()

        let warning = app.descendants(matching: .any)["addAlarm.backupBeforeSnooze"]
        scrollTo(warning, in: app)
        XCTAssertTrue(
            warning.waitForExistence(timeout: 5),
            "backup warning did not appear: \(app.debugDescription)"
        )
        settle()
        attach(app, "alarm-editor-edit-backup-warning-\(context.name)")
        app.terminate()
    }

    // MARK: - Helpers
    private func launch(_ context: Context, arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(context.language))",
            "-AppleLocale", context.locale,
            context.dark ? "-uitest-force-dark" : "-uitest-force-light"
        ] + arguments
        if context.ax5 {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        }
        app.launch()
        return app
    }

    private func allowPermissionIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 {
            for label in ["許可", "Allow"] {
                if springboard.buttons[label].exists {
                    springboard.buttons[label].tap()
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        // AX5 では swipeUp が1回で大きく飛び、行を通り過ぎることがある。
        // 編集画面のテストと同じゆっくりしたドラッグで探す。
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < 20 {
            start.press(
                forDuration: 0.1,
                thenDragTo: end,
                withVelocity: .slow,
                thenHoldForDuration: 0.1
            )
            Thread.sleep(forTimeInterval: 0.2)
            swipes += 1
        }
    }

    private func settle() {
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
