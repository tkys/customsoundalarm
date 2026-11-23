import XCTest

/// #262: PRO の印と先行公開の説明を画面から外したことを確認するスクリーンショット。
/// `TEST_RUNNER_PRO_MARK_REMOVAL_SCREENSHOTS=1 xcodebuild test ...` のときだけ実行する。
@MainActor
final class ProMarkRemovalScreenshotUITests: XCTestCase {

    private struct Context {
        let language: String
        let locale: String
        let ax5: Bool

        var sizeName: String { ax5 ? "ax5" : "standard" }
    }

    private let contexts: [Context] = [
        Context(language: "ja", locale: "ja_JP", ax5: false),
        Context(language: "en", locale: "en_US", ax5: false),
        Context(language: "ja", locale: "ja_JP", ax5: true),
        Context(language: "en", locale: "en_US", ax5: true)
    ]

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PRO_MARK_REMOVAL_SCREENSHOTS"] == "1",
            "PRO mark removal screenshots run only with TEST_RUNNER_PRO_MARK_REMOVAL_SCREENSHOTS=1"
        )
        continueAfterFailure = true
    }

    func testCaptureOversleepRow() {
        for context in contexts {
            let app = launch(context, arguments: ["-uitest-open-add-alarm"])
            XCTAssertTrue(
                app.collectionViews["addAlarm.root"].waitForExistence(timeout: 25),
                "add screen did not appear: \(app.debugDescription)"
            )
            allowPermissionIfAsked()

            let toggle = app.descendants(matching: .any)["addAlarm.backupToggle"]
            scrollTo(toggle, in: app, startY: 0.8, endY: 0.55)
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(
                app.descendants(matching: .any)["addAlarm.backupBadge"].exists,
                "PRO badge must be removed from the oversleep row"
            )
            settle()
            attach(app, "pro-mark-removed-backup-\(context.language)-\(context.sizeName)")
            app.terminate()
        }
    }

    func testCapturePlaylistHeader() {
        for context in contexts {
            let app = launch(
                context,
                arguments: ["-uitest-seed-design-audit", "-uitest-open-library"]
            )
            XCTAssertTrue(
                app.collectionViews["library.root"].waitForExistence(timeout: 25),
                "library did not appear: \(app.debugDescription)"
            )
            allowPermissionIfAsked()

            let title = app.staticTexts[context.language == "ja" ? "プレイリスト" : "Playlists"]
            scrollWithinLibrary(to: title, in: app)
            XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(
                app.descendants(matching: .any)["playlist.earlyAccessBadge"].exists,
                "PRO badge must be removed from the playlist header"
            )
            settle()
            attach(app, "pro-mark-removed-playlist-\(context.language)-\(context.sizeName)")
            app.terminate()
        }
    }

    // MARK: - Helpers

    private func launch(_ context: Context, arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(context.language))",
            "-AppleLocale", context.locale,
            "-uitest-force-light"
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

    private func scrollTo(
        _ element: XCUIElement,
        in app: XCUIApplication,
        startY: CGFloat,
        endY: CGFloat
    ) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < 30 {
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

    private func scrollWithinLibrary(to element: XCUIElement, in app: XCUIApplication) {
        let list = app.collectionViews["library.root"]
        var swipes = 0
        while (!element.exists || !element.isHittable) && swipes < 10 {
            list.swipeUp()
            swipes += 1
        }
    }

    private func settle() {
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
