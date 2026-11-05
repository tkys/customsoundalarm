#if DEBUG
import SwiftUI

/// 同期の実行記録（DEBUG のみ・#163）。
/// 「なぜ作り直したか」を確認するための開発者向け画面。
struct SyncLogView: View {
    @State private var entries: [AlarmSyncLogEntry] = AppGroup.alarmSyncLog

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        List {
            if entries.isEmpty {
                Text("同期の記録はまだありません")
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(entries.reversed()) { entry in
                    Section {
                        row("きっかけ", entry.trigger.rawValue)
                        row("時刻", Self.timestampFormatter.string(from: entry.timestamp))
                        row("作り直し", "\(entry.rescheduledCount)件")
                        row("延期", "\(entry.deferredCount)件")
                        if entry.rescheduledCount > 0 {
                            row(
                                "理由",
                                "changed \(entry.changedCount) / missing \(entry.missingCount) / forced \(entry.forcedCount)"
                            )
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("syncLog.root")
        .navigationTitle("同期ログ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("消去") {
                    AppGroup.alarmSyncLog = []
                    entries = []
                }
                .accessibilityIdentifier("syncLog.clear")
            }
        }
        .onAppear {
            entries = AppGroup.alarmSyncLog
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}
#endif
