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
            // 端いっぱいの範囲では、つまみの矩形が画面の端とちょうど重なる。
            // CGRect.contains は接しているだけの矩形を「含まない」と判定するため、
            // 丸め誤差ぶん（0.5pt）だけ許す
            let screen = window.frame
            XCTAssertTrue(
                target.frame.minX >= screen.minX - 0.5
                    && target.frame.maxX <= screen.maxX + 0.5
                    && target.frame.minY >= screen.minY
                    && target.frame.maxY <= screen.maxY,
                "handle \(target.frame) should stay inside the screen \(screen)"
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

    // MARK: - #303 手直し

    /// 下の段をピンチで拡大したあとに上の段で終了の端を動かしても、
    /// 下の段の拡大がやり直しにならず、動かしている終了のつまみが下の段に出ている。
    ///
    /// 修正前は範囲が変わるたびに窓を選択範囲から作り直していた。選択範囲
    /// （120秒）が窓（最大60秒）より広いため、作り直した窓の左右どちらの端も
    /// 外へ出て、下の段のつまみが両方消えていた。
    func testTouchingOverviewAfterPinchKeepsZoomAndShowsEndHandle() {
        launchFullRange(extra: ["-uitest-long-crop"])

        let zoomBar = element("crop.zoomBar")
        XCTAssertTrue(zoomBar.waitForExistence(timeout: 10), app.debugDescription)
        let beforeSpacing = rulerSpacing()
        zoomBar.pinch(withScale: 1.4, velocity: 1.0)
        let zoomed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                abs(self.rulerSpacing() - beforeSpacing) > 4
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [zoomed], timeout: 5),
            .completed,
            "pinch should zoom the detailed waveform: \(app.debugDescription)"
        )
        let zoomedSpacing = rulerSpacing()

        // 上の段で終了の端を左へ動かす（範囲いっぱいの状態から）
        let window = app.windows.firstMatch
        let endHandle = element("crop.handle.end.overview")
        XCTAssertTrue(endHandle.waitForExistence(timeout: 5), app.debugDescription)
        drag(atX: window.frame.maxX - 20, y: endHandle.frame.midY, by: -120)

        let zoomEnd = element("crop.handle.end.zoom")
        XCTAssertTrue(
            zoomEnd.waitForExistence(timeout: 5),
            "the end handle being moved should appear in the detailed waveform: \(app.debugDescription)"
        )
        XCTAssertTrue(zoomEnd.isHittable, "the end handle should be hittable: \(zoomEnd)")
        XCTAssertEqual(
            rulerSpacing(),
            zoomedSpacing,
            accuracy: 2,
            "moving the range should not rebuild the zoom window (拡大率をやり直さない)"
        )
    }

    /// 下の段をピンチで拡大したあと、上の段の終了のつまみを右へ大きく動かして離すと、
    /// 下の段の窓が一度だけ寄って `crop.handle.end.zoom` が出ている（#303 2回目の手直し）。
    ///
    /// 修正前は上段のドラッグ中に窓を何度も寄せていたため、端がすぐ窓の外へ出て
    /// ずらし直しが連続していた。離したときだけ窓を寄せるようになったことを確かめる。
    func testReleasingOverviewEndHandleSlidesZoomWindowToShowEndHandle() {
        launchFullRange(extra: [
            "-uitest-long-crop",
            "-uitestCropStart", "30",
            "-uitestCropEnd", "60"
        ])

        let zoomBar = element("crop.zoomBar")
        XCTAssertTrue(zoomBar.waitForExistence(timeout: 10), app.debugDescription)
        let beforeSpacing = rulerSpacing()
        zoomBar.pinch(withScale: 1.4, velocity: 1.0)
        let zoomed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                abs(self.rulerSpacing() - beforeSpacing) > 4
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [zoomed], timeout: 5),
            .completed,
            "pinch should zoom the detailed waveform: \(app.debugDescription)"
        )
        let zoomedSpacing = rulerSpacing()

        // 上の段で終了の端を右へ大きく動かして離す
        let endHandle = element("crop.handle.end.overview")
        XCTAssertTrue(endHandle.waitForExistence(timeout: 5), app.debugDescription)
        drag(atX: endHandle.frame.midX, y: endHandle.frame.midY, by: 140)

        let zoomEnd = element("crop.handle.end.zoom")
        XCTAssertTrue(
            zoomEnd.waitForExistence(timeout: 5),
            "the end handle should appear in the detailed waveform after release: \(app.debugDescription)"
        )
        XCTAssertTrue(zoomEnd.isHittable, "the end handle should be hittable: \(zoomEnd)")
        XCTAssertEqual(
            rulerSpacing(),
            zoomedSpacing,
            accuracy: 2,
            "sliding the window should not change the zoom level"
        )
    }

    /// ▶ は選択範囲をくり返し鳴らし、終了のつまみを動かしても止まらない（#303）。
    func testPlaybackKeepsPlayingWhileDraggingEndHandle() {
        launchFullRange(extra: [
            "-uitest-long-crop",
            "-uitestCropStart", "1",
            "-uitestCropEnd", "4"
        ])

        let preview = app.buttons["audioCrop.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), app.debugDescription)
        let idleLabel = preview.label
        preview.tap()

        let started = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", idleLabel),
            object: preview
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [started], timeout: 5),
            .completed,
            "tapping play should start playback: \(app.debugDescription)"
        )
        let playingLabel = preview.label

        let handle = element("crop.handle.end.zoom")
        XCTAssertTrue(handle.waitForExistence(timeout: 5), app.debugDescription)
        drag(atX: handle.frame.maxX - 4, y: handle.frame.midY, by: -40)

        XCTAssertEqual(
            preview.label,
            playingLabel,
            "dragging a handle should keep playback running"
        )
    }

    // MARK: - Helpers

    private enum Edge {
        case start
        case end
    }

    private func launchFullRange(extra: [String] = []) {
        app.launchArguments = [
            "-uitest-open-add-alarm",
            "-uitest-open-waveform-crop",
            "-uitest-force-light",
            "-AppleLanguages", "(ja)",
            "-AppleLocale", "ja_JP"
        ] + extra
        app.launch()
        allowAlarmPermissionIfAsked()
        XCTAssertTrue(
            app.collectionViews["addAlarm.root"].waitForExistence(timeout: 15),
            app.debugDescription
        )
        XCTAssertTrue(
            element("crop.handle.start.overview").waitForExistence(timeout: 30),
            "crop screen should appear: \(app.debugDescription)"
        )
    }

    /// 指定の位置から横へドラッグする（掴んだ状態で動かす）
    private func drag(atX x: CGFloat, y: CGFloat, by dx: CGFloat) {
        let point = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: x, dy: y))
        point.press(forDuration: 0.15, thenDragTo: point.withOffset(CGVector(dx: dx, dy: 0)))
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

    /// 目盛りラベルの間隔（pt）。窓の幅（拡大率）が変わると刻みの間隔が変わる。
    private func rulerSpacing() -> CGFloat {
        let rulers = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "crop.ruler.")
        )
        let xs = (0..<rulers.count).map { rulers.element(boundBy: $0).frame.midX }.sorted()
        let gaps = zip(xs.dropFirst(), xs).map { $0 - $1 }.filter { $0 > 1 }
        guard !gaps.isEmpty else { return 0 }
        return gaps.sorted()[gaps.count / 2]
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
