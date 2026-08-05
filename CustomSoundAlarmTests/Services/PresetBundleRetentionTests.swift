import Testing
import Foundation
@testable import CustomSoundAlarm

/// 既存ユーザーの永続データが参照するプリセットファイルが
/// バンドルから削除されていないことを検証する（#47 review・サイレント故障防止）。
struct PresetBundleRetentionTests {

    /// PresetAlarm.caf は既存ユーザーの AlarmSound.fileName に永続化されている。
    /// presetDefinitions から外れていても、バンドルにファイルが無いと
    /// AlarmScheduler が .named() で解決できずアラームが鳴らない。
    @Test
    func presetAlarmCaf_existsInBundle() {
        let url = Bundle.main.url(forResource: "PresetAlarm", withExtension: "caf")
        #expect(url != nil, "PresetAlarm.caf must remain in the bundle — existing users' alarms depend on it")
    }

    /// 新規プリセットもバンドルに含まれていることを検証
    @Test
    func newPresets_existInBundle() {
        let newPresets = [
            "PresetMarimba", "PresetBell", "PresetCrescendo",
            "PresetBeep", "PresetAscending", "PresetDualTone", "PresetMusicBox"
        ]
        for name in newPresets {
            let url = Bundle.main.url(forResource: name, withExtension: "caf")
            #expect(url != nil, "\(name).caf must be in the bundle")
        }
    }
}
