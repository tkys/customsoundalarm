import XCTest

/// #292: 切り取り範囲がいっぱいのとき、左右のつまみが画面内で掴めること。
///
/// つまみの当たり判定（44pt）は枠の内側へ広げてある。以前は見た目の中央に
/// 18pt だけ置いていたため、範囲の端では画面外の半分しか押せなかった。
@MainActor
final class CropHandlesUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// 範囲いっぱいのとき、左右のつまみの触れる範囲が画面内にあり、
    /// 端から 20pt 内側を押してドラッグすると、その端だけが動く。
    func testFullRangeHandlesAreInsideScreenAndDragEdges() {
        launchFullRange()

        let startHandle = element("crop.handle.start.overview")
        let endHandle = element("crop.handle.end.overview")
        let window = app.windows.firstMatch

        for target in [startHandle, endHandle] {
            XCTAssertTrue(target.waitForExistence(timeout: 20), app.debugDescription)
            XCTAssertTrue(target.isHittable, "handle should be hittable: \(target)")
            XCTAssertEqual(target.frame.width, 44, accuracy: 1, "touch target should be 44pt")
            XCTAssertTrue(
                window.frame.contains(target.frame),
                "handle \(target.frame) should stay inside the screen \(window.frame)"
            )
        }

        assertDragChangesOnly(
            edge: .start,
            handle: startHandle,
            window: window
        )

        // 右端も、範囲いっぱいの状態から確かめる
        app.terminate()
        launchFullRange()
        let freshEnd = element("crop.handle.end.overview")
        XCTAssertTrue(freshEnd.waitForExistence(timeout: 20), app.debugDescription)
        assertDragChangesOnly(
            edge: .end,
            handle: freshEnd,
            window: app.windows.firstMatch
        )
    }

    /// 2本指のピンチで拡大・縮小でき、選択範囲（開始・終了）は動かない。
    func testPinchZoomsWithoutMovingSelection() {
        launchFullRange()

        let startLabel = element("crop.time.start")
        let endLabel = element("crop.time.end")
        XCTAssertTrue(startLabel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(endLabel.waitForExistence(timeout: 5), app.debugDescription)
        let beforeStart = startLabel.label
        let beforeEnd = endLabel.label
        let beforeRulers = rulerIdentifiers()

        let zoomBar = element("crop.zoomBar")
        XCTAssertTrue(zoomBar.waitForExistence(timeout: 10), app.debugDescription)
        zoomBar.pinch(withScale: 1.4, velocity: 1.0)

        let zoomed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                self.rulerIdentifiers() != beforeRulers
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [zoomed], timeout: 5),
            .completed,
            "pinch should zoom the detailed waveform: \(app.debugDescription)"
        )
        XCTAssertEqual(startLabel.label, beforeStart, "pinch should not move the range start")
        XCTAssertEqual(endLabel.label, beforeEnd, "pinch should not move the range end")
    }

    // MARK: - Helpers

    private enum Edge {
        case start
        case end
    }

    private func launchFullRange() {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            "-uitest-force-light",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ]
        app.launch()
        allowAlarmPermissionIfAsked()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        XCTAssertTrue(
            element("crop.handle.start.overview").waitForExistence(timeout: 20),
            "crop screen should appear: \(app.debugDescription)"
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertDragChangesOnly(
        edge: Edge,
        handle: XCUIElement,
        window: XCUIElement
    ) {
        let startLabel = element("crop.time.start")
        let endLabel = element("crop.time.end")
        XCTAssertTrue(startLabel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(endLabel.waitForExistence(timeout: 5), app.debugDescription)
        let beforeStart = startLabel.label
        let beforeEnd = endLabel.label

        // 範囲の端から 20pt 内側。旧実装（18pt を端の中央）では触れない位置。
        let edgeX = edge == .start ? window.frame.minX : window.frame.maxX
        let offset: CGFloat = edge == .start ? 20 : -20
        let point = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: edgeX + offset, dy: handle.frame.midY))
        let target = point.withOffset(CGVector(dx: edge == .start ? 70 : -70, dy: 0))
        point.press(forDuration: 0.15, thenDragTo: target)

        let moved = edge == .start ? startLabel : endLabel
        let unchanged = edge == .start ? endLabel : startLabel
        let beforeMoved = edge == .start ? beforeStart : beforeEnd
        let beforeUnchanged = edge == .start ? beforeEnd : beforeStart

        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", beforeMoved),
            object: moved
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [changed], timeout: 5),
            .completed,
            "dragging the \(edge) handle should move that edge: \(app.debugDescription)"
        )
        XCTAssertEqual(
            unchanged.label,
            beforeUnchanged,
            "dragging one handle should not move the whole range"
        )
    }

    private func rulerIdentifiers() -> [String] {
        let rulers = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "crop.ruler.")
        )
        return (0..<rulers.count)
            .map { rulers.element(boundBy: $0).identifier }
            .sorted()
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
