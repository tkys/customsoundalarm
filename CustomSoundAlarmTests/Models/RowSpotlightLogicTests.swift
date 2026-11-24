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
    func scrollDurationUsesDistanceAndClamps() {
        #expect(RowSpotlightTiming.scrollDuration(for: 0) == 0.5)
        #expect(abs(RowSpotlightTiming.scrollDuration(for: 140) - 0.55) < 0.0001)
        #expect(RowSpotlightTiming.scrollDuration(for: 770) == 1.0)
        #expect(RowSpotlightTiming.scrollDuration(for: 2000) == 1.0)
    }

    @Test
    func scrollDistanceTargetsTheMiddle() {
        // target = 100 + 600 * 0.45 = 370
        let row = CGRect(x: 16, y: 400, width: 358, height: 86)
        #expect(RowSpotlightLogic.scrollDistance(rowFrame: row, viewport: viewport) == 30)
    }


    @Test
    func bezierStartsAndEndsAtTheEndpoints() {
        let start = SpotlightBezier.value(x: 0, x1: 0.33, y1: 0, x2: 0.15, y2: 1)
        let end = SpotlightBezier.value(x: 1, x1: 0.33, y1: 0, x2: 0.15, y2: 1)
        #expect(abs(start - 0) < 0.0001)
        #expect(abs(end - 1) < 0.0001)
    }

    @Test
    func bezierSlowsAtTheStartAndTheEnd() {
        let early = SpotlightBezier.value(x: 0.1, x1: 0.33, y1: 0, x2: 0.15, y2: 1)
        let late = SpotlightBezier.value(x: 0.9, x1: 0.33, y1: 0, x2: 0.15, y2: 1)
        #expect(early < 0.1)
        #expect(1 - late < 0.1)
    }

    @Test
    func newAlarmAlwaysSpotlights() {
        #expect(AlarmSpotlightLogic.shouldSpotlight(
            isNew: true,
            oldHour: nil,
            oldMinute: nil,
            newHour: 11,
            newMinute: 0
        ))
    }

    @Test
    func editingTheSameTimeDoesNotSpotlight() {
        #expect(!AlarmSpotlightLogic.shouldSpotlight(
            isNew: false,
            oldHour: 6,
            oldMinute: 24,
            newHour: 6,
            newMinute: 24
        ))
    }

    @Test
    func editingTheTimeSpotlights() {
        #expect(AlarmSpotlightLogic.shouldSpotlight(
            isNew: false,
            oldHour: 6,
            oldMinute: 24,
            newHour: 7,
            newMinute: 24
        ))
        #expect(AlarmSpotlightLogic.shouldSpotlight(
            isNew: false,
            oldHour: 6,
            oldMinute: 24,
            newHour: 6,
            newMinute: 25
        ))
    }
}
