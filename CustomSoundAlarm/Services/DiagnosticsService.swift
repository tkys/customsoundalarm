import Foundation
import AVFoundation
import AlarmKit
import PostHog
import UIKit

/// お問い合わせ用の診断ファイルを作る（#255）。
///
/// 生成した JSON は一時ディレクトリに置き、メールの添付または共有シートで渡す。
/// 送信するかどうかは本人が選ぶ。サーバーへの自動送信はしない。
@MainActor
enum DiagnosticsService {

    static let fileName = "MySoundAlarm-diagnostics.json"

    /// 診断 JSON を作り、一時ファイルの URL を返す。
    static func writeReport() async -> URL? {
        let alarms = AlarmStore.shared.alarms
        let sounds = SoundStore.shared.sounds
        let soundsDirectory = AudioConverter.shared.soundsDirectory

        // 計測は重いのでメインスレッドの外で行う。
        let measurementInputs: [(UUID, URL)] = sounds.map { sound in
            let url: URL
            if sound.isPreset {
                let base = sound.fileName.replacingOccurrences(of: ".caf", with: "")
                url = Bundle.main.url(forResource: base, withExtension: "caf")
                    ?? soundsDirectory.appendingPathComponent(sound.fileName)
            } else {
                url = soundsDirectory.appendingPathComponent(sound.fileName)
            }
            return (sound.id, url)
        }
        let measurements = await Task.detached(priority: .userInitiated) {
            var result: [UUID: DiagnosticsReportBuilder.SoundMeasurement] = [:]
            for (id, url) in measurementInputs {
                let exists = FileManager.default.fileExists(atPath: url.path)
                let lufs = exists ? LoudnessMeter.measure(fileURL: url)?.lufs : nil
                let format = url.pathExtension.lowercased()
                result[id] = DiagnosticsReportBuilder.SoundMeasurement(
                    lufs: lufs,
                    format: format.isEmpty ? "unknown" : format
                )
            }
            return result
        }.value

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let locale = Locale.current.identifier

        let data = DiagnosticsReportBuilder.makeJSON(
            appVersion: version ?? "—",
            build: build ?? "—",
            osVersion: UIDevice.current.systemVersion,
            deviceModel: SettingsLogic.deviceModelName(),
            localeIdentifier: locale,
            alarmKitAuthorization: authorizationStateName(),
            alarmKitRegisteredCount: try? AlarmManager.shared.alarms.count,
            alarms: alarms,
            sounds: sounds,
            measurements: measurements,
            historyLines: AlarmLocalHistoryStore.recentLines(limit: DiagnosticsReportBuilder.historyLimit),
            postHogDistinctID: postHogDistinctID(),
            audioOutputs: audioOutputPortTypes()
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// メールに添付する本文用のデータ。
    static func reportData(at url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    static func authorizationStateName() -> String {
        switch AlarmManager.shared.authorizationState {
        case .authorized: "authorized"
        case .denied: "denied"
        case .notDetermined: "not_determined"
        @unknown default: "unknown"
        }
    }

    static func postHogDistinctID() -> String? {
        let id = PostHogSDK.shared.getDistinctId()
        return id.isEmpty ? nil : id
    }

    static func audioOutputPortTypes() -> [String] {
        AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue)
    }
}
