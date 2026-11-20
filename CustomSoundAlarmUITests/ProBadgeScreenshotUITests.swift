import XCTest

/// #262 の PRO バッジ文言を13言語・390pt・標準/AX5で確認するスクリーンショット。
/// `TEST_RUNNER_PRO_BADGE_SCREENSHOTS=1 xcodebuild test ...` のときだけ実行する。
@MainActor
final class ProBadgeScreenshotUITests: XCTestCase {

    private struct Context {
        let language: String
        let locale: String
        let ax5: Bool

        var sizeName: String { ax5 ? "ax5" : "standard" }
    }

    private let contexts: [Context] = [
        Context(language: "en", locale: "en_US", ax5: false),
        Context(language: "ja", locale: "ja_JP", ax5: false),
        Context(language: "ar", locale: "ar_SA", ax5: false),
        Context(language: "cs", locale: "cs_CZ", ax5: false),
        Context(language: "de", locale: "de_DE", ax5: false),
        Context(language: "es", locale: "es_ES", ax5: false),
        Context(language: "fr", locale: "fr_FR", ax5: false),
        Context(language: "it", locale: "it_IT", ax5: false),
        Context(language: "ko", locale: "ko_KR", ax5: false),
        Context(language: "nl", locale: "nl_NL", ax5: false),
        Context(language: "pl", locale: "pl_PL", ax5: false),
        Context(language: "pt-BR", locale: "pt_BR", ax5: false),
        Context(language: "zh-Hans", locale: "zh_CN", ax5: false),
        Context(language: "en", locale: "en_US", ax5: true),
        Context(language: "ja", locale: "ja_JP", ax5: true),
        Context(language: "ar", locale: "ar_SA", ax5: true),
        Context(language: "cs", locale: "cs_CZ", ax5: true),
        Context(language: "de", locale: "de_DE", ax5: true),
        Context(language: "es", locale: "es_ES", ax5: true),
        Context(language: "fr", locale: "fr_FR", ax5: true),
        Context(language: "it", locale: "it_IT", ax5: true),
        Context(language: "ko", locale: "ko_KR", ax5: true),
        Context(language: "nl", locale: "nl_NL", ax5: true),
        Context(language: "pl", locale: "pl_PL", ax5: true),
        Context(language: "pt-BR", locale: "pt_BR", ax5: true),
        Context(language: "zh-Hans", locale: "zh_CN", ax5: true)
    ]

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PRO_BADGE_SCREENSHOTS"] == "1",
            "PRO badge screenshots run only with TEST_RUNNER_PRO_BADGE_SCREENSHOTS=1"
        )
        continueAfterFailure = true
    }

    private var selectedLanguages: Set<String>? {
        guard let raw = ProcessInfo.processInfo.environment["PRO_BADGE_LANGS"] else {
            return nil
        }
        return Set(raw.split(separator: ",").map(String.init))
    }

    private var activeContexts: [Context] {
        guard let selectedLanguages else { return contexts }
        return contexts.filter { selectedLanguages.contains($0.language) }
    }

    func testCaptureBackupBadgeAllLanguages() {
        for context in activeContexts {
            let app = launch(
                context,
                arguments: ["-uitest-open-add-alarm"]
            )
            XCTAssertTrue(
                app.collectionViews["addAlarm.root"].waitForExistence(timeout: 25),
                "add screen did not appear: \(app.debugDescription)"
            )
            allowPermissionIfAsked()

            let badge = app.descendants(matching: .any)["addAlarm.backupBadge"]
            scrollToBadge(badge, in: app)
            XCTAssertTrue(
                badge.waitForExistence(timeout: 5),
                "backup badge did not appear: \(app.debugDescription)"
            )
            settle()
            attach(app, "pro-badge-backup-\(context.language)-\(context.sizeName)")
            app.terminate()
        }
    }

    func testCapturePlaylistBadgeJapaneseAndEnglish() {
        let playlistContexts = activeContexts.filter {
            ($0.language == "ja" || $0.language == "en") && !$0.ax5
        } + activeContexts.filter {
            ($0.language == "ja" || $0.language == "en") && $0.ax5
        }
        for context in playlistContexts {
            let app = launch(
                context,
                arguments: ["-uitest-seed-design-audit", "-uitest-open-library"]
            )
            XCTAssertTrue(
                app.collectionViews["library.root"].waitForExistence(timeout: 25),
                "library did not appear: \(app.debugDescription)"
            )
            allowPermissionIfAsked()

            let badge = app.descendants(matching: .any)["playlist.earlyAccessBadge"]
            scrollWithinLibrary(to: badge, in: app)
            XCTAssertTrue(
                badge.waitForExistence(timeout: 5),
                "playlist badge did not appear: \(app.debugDescription)"
            )
            settle()
            attach(app, "pro-badge-playlist-\(context.language)-\(context.sizeName)")
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

    private func scrollToBadge(_ element: XCUIElement, in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
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
