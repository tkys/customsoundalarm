import Testing
import Foundation
@testable import CustomSoundAlarm

/// 変換後 CAF サイズの見積り純粋関数のテスト（#79-8）。
/// PCM 16bit/44.1kHz/モノラル = 88,200 bytes/秒。
/// 目安: 10分 ≈ 53MB、30分 ≈ 159MB。
struct AudioSizeEstimateTests {

    private func approx(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.0001
    }

    // MARK: - バイト数見積り

    @Test
    func estimatedBytes_perSecond() {
        #expect(approx(AudioSizeEstimate.estimatedFileSize(seconds: 1), 88_200))
    }

    @Test
    func estimatedBytes_tenMinutes() {
        // 10分 = 600秒 → 52,920,000 bytes ≈ 53MB
        #expect(approx(AudioSizeEstimate.estimatedFileSize(seconds: 600), 52_920_000))
    }

    @Test
    func estimatedBytes_thirtyMinutes() {
        // 30分 = 1800秒 → 158,760,000 bytes ≈ 159MB
        #expect(approx(AudioSizeEstimate.estimatedFileSize(seconds: 1800), 158_760_000))
    }

    @Test
    func estimatedBytes_oneHour() {
        // 1時間 = 3600秒 → 約317MB（Issue #79 の記載値）
        #expect(approx(AudioSizeEstimate.estimatedFileSize(seconds: 3600), 317_520_000))
    }

    @Test
    func estimatedBytes_negativeSeconds_isZero() {
        #expect(AudioSizeEstimate.estimatedFileSize(seconds: -10) == 0)
    }

    // MARK: - 表示フォーマット

    @Test
    func formattedSize_under100MB_oneDecimal() {
        #expect(AudioSizeEstimate.formattedSize(bytes: 52_920_000) == "52.9 MB")
        #expect(AudioSizeEstimate.formattedSize(bytes: 4_410_000) == "4.4 MB")
    }

    @Test
    func formattedSize_over100MB_noDecimal() {
        #expect(AudioSizeEstimate.formattedSize(bytes: 158_760_000) == "159 MB")
        #expect(AudioSizeEstimate.formattedSize(bytes: 317_520_000) == "318 MB")
    }

    @Test
    func formattedSize_zeroAndNegative() {
        #expect(AudioSizeEstimate.formattedSize(bytes: 0) == "0.0 MB")
        #expect(AudioSizeEstimate.formattedSize(bytes: -5) == "0.0 MB")
    }

    // MARK: - 容量注意のしきい値（20MB・#123）

    @Test
    func warning_atTwentyMegabytes() {
        #expect(AudioSizeEstimate.shouldShowWarning(bytes: 20_000_000))
        #expect(AudioSizeEstimate.shouldShowWarning(bytes: 20_000_001))
        #expect(AudioSizeEstimate.shouldShowWarning(seconds: 600))
    }

    @Test
    func noWarning_belowTwentyMegabytes() {
        #expect(!AudioSizeEstimate.shouldShowWarning(bytes: 19_999_999))
        #expect(!AudioSizeEstimate.shouldShowWarning(bytes: 0))
        #expect(!AudioSizeEstimate.shouldShowWarning(seconds: 226)) // 19,933,200 bytes
    }

    @Test
    func warning_justOverThreshold() {
        #expect(AudioSizeEstimate.shouldShowWarning(seconds: 227)) // 20,021,400 bytes
    }
}