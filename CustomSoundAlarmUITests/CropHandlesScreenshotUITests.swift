import XCTest

/// #292 の確認用スクリーンショットと操作の録画。
///
/// 通常のテスト実行では動かさない。撮るときだけ
/// `TEST_RUNNER_CROP_HANDLES_SCREENSHOTS=1 xcodebuild test ...` で有効にする。
@MainActor
final class CropHandlesScreenshotUITests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CROP_HANDLES_SCREENSHOTS"] == "1",
            "Crop handle screenshots run only with TEST_RUNNER_CROP_HANDLES_SCREENSHOTS=1"
        )
        continueAfterFailure = true
    }

    func testLight() {
        captureAll(appearance: "light", appearanceArgument: "-uitest-force-light")
    }

    func testDark() {
        captureAll(appearance: "dark", appearanceArgument: "-uitest-force-dark")
    }

    /// `xcrun simctl io ... recordVideo` を外から回して撮るための操作。
    func testInteractionRecording() {
        let app = launch(appearanceArgument: "-uitest-force-light", extra: [])
        XCTAssertTrue(
            app.descendants(matching: .any)["crop.handle.start.overview"]
                .waitForExistence(timeout: 20),
            app.debugDescription
        )
        settle(5)

        dragHandle(in: app, edge: .start, distance: 80)
        settle(1)
        dragHandle(in: app, edge: .end, distance: -60)
        settle(1)
        pinchZoom(in: app)
        settle(3)
    }

    // MARK: - Capture

    private func captureAll(appearance: String, appearanceArgument: String) {
        // 範囲いっぱい
        var app = launch(appearanceArgument: appearanceArgument, extra: [])
        XCTAssertTrue(
            app.descendants(matching: .any)["crop.handle.start.overview"]
                .waitForExistence(timeout: 20),
            app.debugDescription
        )
        settle(7)
        capture(app, name: "crop-handles-full-\(appearance)")

        // 短い範囲
        app.terminate()
        app = launch(
            appearanceArgument: appearanceArgument,
            extra: ["-uitestCropStart", "1.5", "-uitestCropEnd", "4.5"]
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["crop.handle.start.overview"]
                .waitForExistence(timeout: 20),
            app.debugDescription
        )
        settle(5)
        capture(app, name: "crop-handles-short-\(appearance)")

        // ピンチで拡大中（短い範囲のまま拡大する）
        pinchZoom(in: app)
        settle(2)
        capture(app, name: "crop-handles-pinch-\(appearance)")
    }

    private func launch(
        appearanceArgument: String,
        extra: [String]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            appearanceArgument,
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ] + extra
        app.launch()
        allowAlarmPermissionIfAsked()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            "add screen should appear: \(app.debugDescription)"
        )
        return app
    }

    private enum Edge {
        case start
        case end
    }

    private func dragHandle(in app: XCUIApplication, edge: Edge, distance: CGFloat) {
        let identifier = edge == .start
            ? "crop.handle.start.overview"
            : "crop.handle.end.overview"
        let handle = app.descendants(matching: .any)[identifier]
        guard handle.exists else { return }
        let window = app.windows.firstMatch
        let edgeX = edge == .start ? window.frame.minX : window.frame.maxX
        let offset: CGFloat = edge == .start ? 20 : -20
        let point = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: edgeX + offset, dy: handle.frame.midY))
        point.press(
            forDuration: 0.2,
            thenDragTo: point.withOffset(CGVector(dx: distance, dy: 0))
        )
    }

    private func pinchZoom(in app: XCUIApplication) {
        let zoomBar = app.descendants(matching: .any)["crop.zoomBar"]
        guard zoomBar.waitForExistence(timeout: 5) else { return }
        zoomBar.pinch(withScale: 1.4, velocity: 1.0)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func allowAlarmPermissionIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["許可", "Allow"] {
            if springboard.buttons[label].waitForExistence(timeout: 2) {
                springboard.buttons[label].tap()
                return
            }
        }
    }
}
