import Testing
import Foundation
@testable import CustomSoundAlarm

struct AlarmListOrderingTests {

    @Test
    func testSortsByTimeOfDay() {
        let a = AlarmEntry(hour: 23, minute: 44)
        let b = AlarmEntry(hour: 6, minute: 24)
        let c = AlarmEntry(hour: 18, minute: 0)
        let sorted = AlarmListOrdering.sortedForDisplay([a, b, c])
        #expect(sorted.map { $0.timeString } == ["06:24", "18:00", "23:44"])
    }

    @Test
    func testStableForSameTime() {
        let a1 = AlarmEntry(hour: 7, minute: 30)
        let a2 = AlarmEntry(hour: 7, minute: 30)
        let a3 = AlarmEntry(hour: 7, minute: 30)
        // Duplicate should be at end of group - stable sort preserves creation order
        let sorted = AlarmListOrdering.sortedForDisplay([a1, a2, a3])
        #expect(sorted[0].id == a1.id)
        #expect(sorted[1].id == a2.id)
        #expect(sorted[2].id == a3.id)
    }

    @Test
    func testStableForSameTimeWithDifferentTimes() {
        let a = AlarmEntry(hour: 7, minute: 30)
        let b = AlarmEntry(hour: 7, minute: 30)
        let c = AlarmEntry(hour: 6, minute: 0)
        let d = AlarmEntry(hour: 7, minute: 30)
        let sorted = AlarmListOrdering.sortedForDisplay([a, b, c, d])
        // 06:00 first, then 07:30 group in creation order a,b,d
        #expect(sorted[0].id == c.id)
        #expect(sorted[1].id == a.id)
        #expect(sorted[2].id == b.id)
        #expect(sorted[3].id == d.id)
    }

    @Test
    func testDisabledKeepsPosition() {
        var a = AlarmEntry(hour: 6, minute: 24)
        a.isEnabled = false
        let b = AlarmEntry(hour: 18, minute: 0)
        let c = AlarmEntry(hour: 23, minute: 44)
        let sorted = AlarmListOrdering.sortedForDisplay([c, a, b])
        #expect(sorted.map { $0.timeString } == ["06:24", "18:00", "23:44"])
        #expect(sorted[0].id == a.id)
    }

    @Test
    func testMidnightBoundary() {
        let a = AlarmEntry(hour: 0, minute: 0)
        let b = AlarmEntry(hour: 23, minute: 59)
        let c = AlarmEntry(hour: 12, minute: 0)
        let sorted = AlarmListOrdering.sortedForDisplay([b, c, a])
        #expect(sorted.map { $0.timeString } == ["00:00", "12:00", "23:59"])
    }

    @Test
    func testDoesNotMutateOriginalOrder() {
        let a = AlarmEntry(hour: 23, minute: 44)
        let b = AlarmEntry(hour: 6, minute: 24)
        let original = [a, b]
        let sorted = AlarmListOrdering.sortedForDisplay(original)
        #expect(original.map { $0.timeString } == ["23:44", "06:24"])
        #expect(sorted.map { $0.timeString } == ["06:24", "23:44"])
    }
}
