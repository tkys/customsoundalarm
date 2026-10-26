import Testing
import Foundation
@testable import CustomSoundAlarm

struct SoundSelectionAnalyticsTests {

    @Test
    func rankBuckets() {
        #expect(SoundSelectionAnalytics.rankBucket(position: 0) == "1")
        #expect(SoundSelectionAnalytics.rankBucket(position: 1) == "1")
        #expect(SoundSelectionAnalytics.rankBucket(position: 2) == "2-3")
        #expect(SoundSelectionAnalytics.rankBucket(position: 3) == "2-3")
        #expect(SoundSelectionAnalytics.rankBucket(position: 4) == "4-10")
        #expect(SoundSelectionAnalytics.rankBucket(position: 10) == "4-10")
        #expect(SoundSelectionAnalytics.rankBucket(position: 11) == "11+")
        #expect(SoundSelectionAnalytics.rankBucket(position: 99) == "11+")
    }

    @Test
    func kinds() {
        #expect(SoundSelectionKind.imported.rawValue == "imported")
        #expect(SoundSelectionKind.preset.rawValue == "preset")
        #expect(SoundSelectionKind.default.rawValue == "default")
    }
}
