import Testing
import Foundation
@testable import CustomSoundAlarm

/// オンボーディングの表示判定（#98 Phase 1）を検証する。
struct OnboardingLogicTests {

    // MARK: - 表示判定（testShowsOnlyForFreshInstall）

    @Test
    func shouldShow_freshInstall_true() {
        // 未完了 × アラーム0件 × 取り込み音源0件 のときだけ表示
        #expect(OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 0, importedSoundCount: 0) == true)
    }

    @Test
    func shouldShow_completed_false() {
        #expect(OnboardingLogic.shouldShow(hasCompleted: true, alarmCount: 0, importedSoundCount: 0) == false)
    }

    @Test
    func shouldShow_hasAlarms_false() {
        #expect(OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 1, importedSoundCount: 0) == false)
        #expect(OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 5, importedSoundCount: 0) == false)
    }

    @Test
    func shouldShow_hasImportedSounds_false() {
        #expect(OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 0, importedSoundCount: 1) == false)
        #expect(OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 0, importedSoundCount: 3) == false)
    }

    // MARK: - 既存ユーザー（testExistingUserNeverSeesOnboarding）

    @Test
    func existingUser_isMarkedCompleted() {
        // アラームか取り込み音源が1件でもあれば表示せず、完了フラグが立つ
        let showsWithAlarm = OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 1, importedSoundCount: 0)
        #expect(showsWithAlarm == false)
        #expect(OnboardingLogic.shouldMarkCompleted(hasCompleted: false, shouldShowOnboarding: showsWithAlarm) == true)

        let showsWithSound = OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 0, importedSoundCount: 2)
        #expect(showsWithSound == false)
        #expect(OnboardingLogic.shouldMarkCompleted(hasCompleted: false, shouldShowOnboarding: showsWithSound) == true)
    }

    @Test
    func freshUser_isNotMarkedCompleted() {
        // 新規ユーザー（表示する）にはフラグを立てない → オンボ完了時に立てる
        let shows = OnboardingLogic.shouldShow(hasCompleted: false, alarmCount: 0, importedSoundCount: 0)
        #expect(shows == true)
        #expect(OnboardingLogic.shouldMarkCompleted(hasCompleted: false, shouldShowOnboarding: shows) == false)
    }

    @Test
    func completedUser_isNotMarkedAgain() {
        #expect(OnboardingLogic.shouldMarkCompleted(hasCompleted: true, shouldShowOnboarding: false) == false)
    }

    // MARK: - 許可要求の移動（testAuthorizationDeferredWhenOnboarding）

    @Test
    func authorization_deferredWhenOnboardingShows() {
        // オンボ表示時は起動時に許可要求しない（場面3で聞く）
        #expect(OnboardingLogic.shouldRequestAuthorizationAtLaunch(shouldShowOnboarding: true) == false)
    }

    @Test
    func authorization_requestedAtLaunchWithoutOnboarding() {
        // オンボを出さない人は従来どおり起動時に要求
        #expect(OnboardingLogic.shouldRequestAuthorizationAtLaunch(shouldShowOnboarding: false) == true)
    }

    // MARK: - OnboardingSource

    @Test
    func source_rawValues_matchAnalyticsIdentifiers() {
        #expect(OnboardingSource.video.rawValue == "video")
        #expect(OnboardingSource.audio.rawValue == "audio")
        #expect(OnboardingSource.preset.rawValue == "preset")
        #expect(OnboardingSource.later.rawValue == "later")
    }

    @Test
    func source_opensAddScreen_exceptLater() {
        #expect(OnboardingSource.video.opensAddScreen == true)
        #expect(OnboardingSource.audio.opensAddScreen == true)
        #expect(OnboardingSource.preset.opensAddScreen == true)
        // 「あとで」は一覧へ戻るだけ
        #expect(OnboardingSource.later.opensAddScreen == false)
    }

    // MARK: - 選択 → 初期動作の写像（testSourceMapsToInitialImport）

    @Test
    func initialImportAction_mapsEachSource() {
        #expect(OnboardingLogic.initialImportAction(for: .video) == .openVideoImport)
        #expect(OnboardingLogic.initialImportAction(for: .audio) == .openFileImporter)
        #expect(OnboardingLogic.initialImportAction(for: .preset) == .preselectPreset)
    }

    @Test
    func initialImportAction_laterAndNil_doNothing() {
        #expect(OnboardingLogic.initialImportAction(for: .later) == .none)
        #expect(OnboardingLogic.initialImportAction(for: nil) == .none)
    }

    // MARK: - 文言の存在と行数同数（testOnboardingKeysExistJaEn）

    @Test
    func onboardingKeys_existInBothLocalesAndLineCountsMatch() throws {
        let onboardingKeys = [
            "onb.hero.title", "onb.loop.title", "onb.silent.title",
            "onb.next", "onb.continue",
            "onb.source.title", "onb.source.video", "onb.source.audio", "onb.source.preset",
            "onb.later"
        ]

        guard let jaPath = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "ja"),
              let enPath = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") else {
            Issue.record("Localizable.strings not found in bundle")
            return
        }

        let jaDict = NSDictionary(contentsOfFile: jaPath) as? [String: String]
        let enDict = NSDictionary(contentsOfFile: enPath) as? [String: String]
        #expect(jaDict != nil, "ja Localizable.strings should parse")
        #expect(enDict != nil, "en Localizable.strings should parse")

        for key in onboardingKeys {
            #expect(jaDict?[key] != nil, "ja missing key: \(key)")
            #expect(enDict?[key] != nil, "en missing key: \(key)")
            #expect(jaDict?[key]?.isEmpty == false, "ja empty value for: \(key)")
            #expect(enDict?[key]?.isEmpty == false, "en empty value for: \(key)")
        }

        // 行数同数: ソースファイル（テキスト）を直接読む。
        // Bundle 内のコンパイル済み .strings はバイナリ plist のため String(encoding:.utf8) では読めない
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let jaSourcePath = projectRoot.appendingPathComponent("CustomSoundAlarm/Resources/ja.lproj/Localizable.strings").path
        let enSourcePath = projectRoot.appendingPathComponent("CustomSoundAlarm/Resources/en.lproj/Localizable.strings").path
        let jaContent = try String(contentsOfFile: jaSourcePath, encoding: .utf8)
        let enContent = try String(contentsOfFile: enSourcePath, encoding: .utf8)
        // ベタ書き禁止・行数同数維持: 非空行の行数は ja/en で一致すること
        let jaLines = jaContent.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let enLines = enContent.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        #expect(jaLines == enLines, "ja (\(jaLines) lines) and en (\(enLines) lines) should have equal non-empty line counts")
    }

    // MARK: - 計測（Phase 5）

    @Test
    func analytics_onboardingEvents_haveExpectedNames() {
        #expect(AnalyticsEvent.onboardingStepViewed(step: .intro).name == "onboarding_step_viewed")
        #expect(AnalyticsEvent.onboardingSourceSelected(source: .video).name == "onboarding_source_selected")
        #expect(AnalyticsEvent.onboardingCompleted(source: .preset, permissionGranted: true).name == "onboarding_completed")
    }

    @Test
    func analytics_onboardingEvents_haveExpectedProperties() {
        let stepProps = AnalyticsEvent.onboardingStepViewed(step: .permission).properties
        #expect(stepProps["step"] as? String == "permission")

        let sourceProps = AnalyticsEvent.onboardingSourceSelected(source: .later).properties
        #expect(sourceProps["source"] as? String == "later")

        let completedProps = AnalyticsEvent.onboardingCompleted(source: .audio, permissionGranted: true).properties
        #expect(completedProps["source"] as? String == "audio")
        #expect(completedProps["permission_granted"] as? Bool == true)
    }
}
