import Testing
import Foundation
@testable import CustomSoundAlarm

/// `AnalyticsBuckets` の区分変換を境界値込みで検証する。
struct AnalyticsBucketsTests {

    // MARK: - durationBucket（滞在時間）

    @Test
    func durationBucket_under1min_justBelowBoundary() {
        // 1分未満 → under_1min
        #expect(AnalyticsBuckets.durationBucket(seconds: 0) == "under_1min")
        #expect(AnalyticsBuckets.durationBucket(seconds: 59.999) == "under_1min")
    }

    @Test
    func durationBucket_1to5min_boundaryInclusive() {
        // ちょうど1分 → 1_5min（下側は含む）
        #expect(AnalyticsBuckets.durationBucket(seconds: 60) == "1_5min")
        #expect(AnalyticsBuckets.durationBucket(seconds: 299.999) == "1_5min")
    }

    @Test
    func durationBucket_5to30min_boundary() {
        // ちょうど5分 → 5_30min
        #expect(AnalyticsBuckets.durationBucket(seconds: 300) == "5_30min")
        #expect(AnalyticsBuckets.durationBucket(seconds: 1799.999) == "5_30min")
    }

    @Test
    func durationBucket_30minTo2h_boundary() {
        // ちょうど30分 → 30min_2h
        #expect(AnalyticsBuckets.durationBucket(seconds: 1800) == "30min_2h")
        #expect(AnalyticsBuckets.durationBucket(seconds: 7199.999) == "30min_2h")
    }

    @Test
    func durationBucket_over2h() {
        // ちょうど2時間 → over_2h（上側は含む）
        #expect(AnalyticsBuckets.durationBucket(seconds: 7200) == "over_2h")
        #expect(AnalyticsBuckets.durationBucket(seconds: 86_400) == "over_2h")
        // 「朝まで置いた」相当（8時間）
        #expect(AnalyticsBuckets.durationBucket(seconds: 8 * 3600) == "over_2h")
    }

    @Test
    func durationBucket_allRawValuesAreStable() {
        let values = Set([60.0, 300.0, 1800.0, 7200.0].map { AnalyticsBuckets.durationBucket(seconds: $0) })
        #expect(values == ["1_5min", "5_30min", "30min_2h", "over_2h"])
    }

    // MARK: - secondsBucket（音源の長さ）

    @Test
    func secondsBucket_under1min_justBelowBoundary() {
        #expect(AnalyticsBuckets.secondsBucket(seconds: 0) == "under_1min")
        #expect(AnalyticsBuckets.secondsBucket(seconds: 59.999) == "under_1min")
    }

    @Test
    func secondsBucket_1to5min_boundaryInclusive() {
        // ちょうど1分 → 1_5min（Pro の制限値候補の境界）
        #expect(AnalyticsBuckets.secondsBucket(seconds: 60) == "1_5min")
        #expect(AnalyticsBuckets.secondsBucket(seconds: 299.999) == "1_5min")
    }

    @Test
    func secondsBucket_5to15min_boundaryInclusive() {
        // ちょうど5分 → 5_15min（Pro の制限値候補の境界）
        #expect(AnalyticsBuckets.secondsBucket(seconds: 300) == "5_15min")
        #expect(AnalyticsBuckets.secondsBucket(seconds: 899.999) == "5_15min")
    }

    @Test
    func secondsBucket_over15min() {
        #expect(AnalyticsBuckets.secondsBucket(seconds: 900) == "over_15min")
        #expect(AnalyticsBuckets.secondsBucket(seconds: 3600) == "over_15min")
    }

    @Test
    func secondsBucket_commonLengths() {
        // 実在しうる長さ: 30秒 / 3分 / 10分
        #expect(AnalyticsBuckets.secondsBucket(seconds: 30) == "under_1min")
        #expect(AnalyticsBuckets.secondsBucket(seconds: 180) == "1_5min")
        #expect(AnalyticsBuckets.secondsBucket(seconds: 600) == "5_15min")
    }
}