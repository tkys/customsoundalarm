import Testing
import CoreGraphics
@testable import CustomSoundAlarm

/// 行のスポットライトでスクロールするかどうかの判定（#282）。
struct RowSpotlightLogicTests {

    private let viewport = CGRect(x: 0, y: 100, width: 390, height: 600)

    @Test
    func fullyVisibleRowDoesNotScroll() {
        let row = CGRect(x: 16, y: 200, width: 358, height: 86)
        #expect(RowSpotlightLogic.position(rowFrame: row, viewport: viewport) == .fullyVisible)
        #expect(RowSpotlightLogic.shouldScroll(rowFrame: row, viewport: viewport) == false)
    }

    @Test
    func rowAboveViewportScrolls() {
        let row = CGRect(x: 16, y: 40, width: 358, height: 86)
        #expect(RowSpotlightLogic.position(rowFrame: row, viewport: viewport) == .above)
        #expect(RowSpotlightLogic.shouldScroll(rowFrame: row, viewport: viewport))
    }

    @Test
    func rowBelowViewportScrolls() {
        let row = CGRect(x: 16, y: 660, width: 358, height: 86)
        #expect(RowSpotlightLogic.position(rowFrame: row, viewport: viewport) == .below)
        #expect(RowSpotlightLogic.shouldScroll(rowFrame: row, viewport: viewport))
    }

    @Test
    func rowPartlyOutsideScrolls() {
        let partlyAbove = CGRect(x: 16, y: 80, width: 358, height: 86)
        let partlyBelow = CGRect(x: 16, y: 680, width: 358, height: 86)
        #expect(RowSpotlightLogic.shouldScroll(rowFrame: partlyAbove, viewport: viewport))
        #expect(RowSpotlightLogic.shouldScroll(rowFrame: partlyBelow, viewport: viewport))
    }

    @Test
    func rowExactlyAtViewportEdgesIsFullyVisible() {
        let atTop = CGRect(x: 0, y: viewport.minY, width: 390, height: 86)
        let atBottom = CGRect(
            x: 0,
            y: viewport.maxY - 86,
            width: 390,
            height: 86
        )
        #expect(RowSpotlightLogic.position(rowFrame: atTop, viewport: viewport) == .fullyVisible)
        #expect(RowSpotlightLogic.position(rowFrame: atBottom, viewport: viewport) == .fullyVisible)
    }

    @Test
    func unmeasuredRowScrolls() {
        #expect(RowSpotlightLogic.position(rowFrame: nil, viewport: viewport) == .notMeasured)
        #expect(RowSpotlightLogic.position(rowFrame: .zero, viewport: viewport) == .notMeasured)
        #expect(RowSpotlightLogic.shouldScroll(rowFrame: nil, viewport: viewport))
    }

    @Test
    func riseStartsNearTheEndOfTheScroll() {
        #expect(
            RowSpotlightTiming.riseDelayWhenScrolling
                == RowSpotlightTiming.scroll * RowSpotlightTiming.riseDuringScroll
        )
        #expect(RowSpotlightTiming.riseDelayWhenScrolling > RowSpotlightTiming.scroll * 0.7)
        #expect(RowSpotlightTiming.riseDelayWhenScrolling < RowSpotlightTiming.scroll)
    }
}
