import Testing
import Foundation
@testable import CustomSoundAlarm

struct SoundKindAnalysisTests {

    private func window(
        _ start: Double,
        _ labels: [(String, Double)]
    ) -> SoundKindWindow {
        SoundKindWindow(
            startSeconds: start,
            top: labels.map {
                SoundKindLabelConfidence(label: $0.0, confidence: $0.1)
            }
        )
    }

    // MARK: - 区分の決め方

    @Test
    func musicFirstWithSingingInTopThree_becomesSinging() {
        var windows = (0..<10).map {
            window(Double($0) * 1.5, [("music", 0.8)])
        }
        // 3割の窓で、2位に歌声が自信0.3以上で入る。
        for index in [0, 3, 6] {
            windows[index] = window(Double(index) * 1.5, [
                ("music", 0.8),
                ("singing", 0.35)
            ])
        }

        let result = SoundKindDecision.decide(windows: windows)
        #expect(result.contentKind == .singing)
        #expect(result.vocalStartSeconds == 0)
    }

    @Test
    func singingInOnlyTenPercent_staysInstrumental() {
        var windows = (0..<10).map {
            window(Double($0) * 1.5, [("music", 0.8)])
        }
        windows[0] = window(0, [("music", 0.8), ("singing", 0.4)])

        #expect(SoundKindDecision.decide(windows: windows).contentKind == .instrumental)
    }

    @Test
    func laughterAndSpeechBecomeVoice() {
        let windows = [
            window(0, [("laughter", 0.8)]),
            window(1, [("speech", 0.7)]),
            window(2, [("baby_laughter", 0.6)])
        ]

        #expect(SoundKindDecision.decide(windows: windows).contentKind == .voice)
    }

    @Test
    func catMeowMajorityBecomesCat() {
        let windows = [
            window(0, [("cat_meow", 0.9)]),
            window(1, [("cat_meow", 0.7)]),
            window(2, [("music", 0.8)])
        ]

        #expect(SoundKindDecision.decide(windows: windows).contentKind == .cat)
    }

    @Test
    func lowConfidenceWindowsBecomeUnknown() {
        let windows = [
            window(0, [("cat_meow", 0.29)]),
            window(1, [("music", 0.2)]),
            window(2, [("speech", 0.1)])
        ]

        #expect(SoundKindDecision.decide(windows: windows).contentKind == .unknown)
    }

    @Test
    func otherOnlyBecomesUnknownLikeRunPy() {
        let windows = [
            window(0, [("alarm_clock", 0.9)]),
            window(1, [("siren", 0.8)])
        ]

        // run.py の decide は other を順位から外す。
        #expect(SoundKindDecision.decide(windows: windows).contentKind == .unknown)
    }

    @Test
    func vocalStartUsesTheEarliestVocalWindow() {
        let windows = [
            window(0, [("music", 0.8)]),
            window(1.5, [("music", 0.8), ("rapping", 0.4)]),
            window(3.0, [("music", 0.8), ("singing", 0.5)])
        ]

        let result = SoundKindDecision.decide(windows: windows)
        #expect(result.contentKind == .singing)
        #expect(result.vocalStartSeconds == 1.5)
    }

    // MARK: - 対応表

    @Test
    func singingLabelsMapToSinging() {
        for label in ["singing", "choir_singing", "rapping", "humming", "yodeling"] {
            #expect(SoundKindLabelMap.kind(for: label) == .singing, "\(label)")
        }
    }

    @Test
    func allCatAndDogLabelsMapToTheirKinds() {
        let cats = ["cat", "cat_meow", "cat_purr"]
        let dogs = [
            "dog", "dog_bark", "dog_bow_wow", "dog_growl", "dog_howl", "dog_whimper"
        ]
        for label in cats {
            #expect(SoundKindLabelMap.kind(for: label) == .cat, "\(label)")
        }
        for label in dogs {
            #expect(SoundKindLabelMap.kind(for: label) == .dog, "\(label)")
        }
    }

    @Test
    func babyLaughterIsVoiceAndAlarmClockIsOther() {
        #expect(SoundKindLabelMap.kind(for: "baby_laughter") == .voice)
        #expect(SoundKindLabelMap.kind(for: "speech") == .voice)
        #expect(SoundKindLabelMap.kind(for: "alarm_clock") == .other)
        #expect(SoundKindLabelMap.kind(for: "siren") == .other)
        #expect(SoundKindLabelMap.kind(for: "not_a_real_label") == .other)
    }

    // MARK: - SoundAnalysis（シミュレータでの統合確認）

    @Test
    func classifierAnalyzesBundledPreset() async throws {
        let url = try #require(
            Bundle.main.url(forResource: "PresetMarimba", withExtension: "caf")
        )
        let result = await SoundKindClassifier.analyze(
            fileURL: url,
            skipSilentCheck: false
        )
        #expect(result.contentKind == .instrumental)
        #expect(result.analysisVersion == SoundKindAnalysisResult.currentVersion)
    }

    /// CC0 の確認用音を App Group に置いたときだけ走る診断（リポジトリには入れない）。
    @Test
    func classifierAnalyzesExternalSmokeFilesIfPresent() async {
        let directory = AppGroup.containerURL
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        let urls = files
            .filter { $0.lastPathComponent.hasPrefix("soundkind-smoke-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else { return }
        for url in urls {
            let result = await SoundKindClassifier.analyze(
                fileURL: url,
                skipSilentCheck: true
            )
            print(
                "SOUNDKIND_SMOKE \(url.lastPathComponent) "
                    + "\(result.contentKind.rawValue) bpm=\(result.bpm ?? -1)"
            )
            #expect(result.analysisVersion == SoundKindAnalysisResult.currentVersion)
        }
    }

    // MARK: - BPM

    @Test
    func bpmEstimatorFindsSyntheticClicks() throws {        for expected in [90, 120, 150] {
            let samples = clickTrack(bpm: expected)
            let estimated = try #require(
                BPMEstimator.estimate(samples: samples, sampleRate: 44_100),
                "no BPM for \(expected)"
            )
            #expect(
                abs(estimated - expected) <= 3,
                "expected \(expected), got \(estimated)"
            )
        }
    }

    private func clickTrack(bpm: Int, seconds: Double = 12) -> [Float] {
        let sampleRate = 44_100.0
        var samples = [Float](repeating: 0, count: Int(sampleRate * seconds))
        let interval = 60.0 / Double(bpm)
        let clickLength = Int(sampleRate * 0.012)
        var beat = 0.0
        while beat < seconds {
            let start = Int(beat * sampleRate)
            for offset in 0..<clickLength where start + offset < samples.count {
                let time = Double(offset) / sampleRate
                let envelope = exp(-time * 80)
                samples[start + offset] += Float(
                    sin(2 * .pi * 1_000 * time) * envelope * 0.8
                )
            }
            beat += interval
        }
        return samples
    }
}
