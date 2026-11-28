import SwiftUI

/// プレイリストを作ったあとに、使うアラームを選ぶシート（#324）。
struct PlaylistApplyView: View {
    let playlist: Playlist
    let onFinish: (PlaylistApplyAction, Int) -> Void

    @State private var alarmStore = AlarmStore.shared
    @State private var selectedIDs: Set<UUID> = []
    @State private var didFinish = false

    private var selectedAlarms: [AlarmEntry] {
        alarmStore.alarms.filter { selectedIDs.contains($0.id) }
    }

    private var showsBackupNote: Bool {
        selectedAlarms.contains { $0.backupMinutes != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PlaylistRowLabel(playlist: playlist)
                        .accessibilityIdentifier("playlistApply.playlist")
                }

                Section {
                    ForEach(alarmStore.alarms) { alarm in
                        Button {
                            toggle(alarm.id)
                        } label: {
                            alarmRow(alarm)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("playlistApply.alarm")
                        .accessibilityAddTraits(
                            selectedIDs.contains(alarm.id) ? .isSelected : []
                        )
                    }
                } footer: {
                    if showsBackupNote {
                        Text("playlist_backup_note")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("playlistApply.root")
            .navigationTitle("playlist_apply_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("playlist_apply_later") {
                        finish(.later)
                    }
                    .accessibilityIdentifier("playlistApply.later")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("playlist_apply_apply") {
                        apply()
                    }
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityIdentifier("playlistApply.apply")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            guard !didFinish else { return }
            didFinish = true
            onFinish(.dismissed, selectedIDs.count)
        }
    }

    private func alarmRow(_ alarm: AlarmEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(alarm.displayTime)
                        .foregroundStyle(.primary)
                    if !alarm.label.isEmpty {
                        Text(alarm.label)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                Text(AlarmSoundDisplay.name(for: alarm))
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: selectedIDs.contains(alarm.id)
                ? "checkmark.circle.fill"
                : "circle")
                .font(.title3)
                .foregroundStyle(selectedIDs.contains(alarm.id)
                    ? Brand.orange
                    : Color.textMuted)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func apply() {
        guard !selectedIDs.isEmpty else { return }
        let updated = PlaylistApplyLogic.appliedAlarms(
            alarmStore.alarms,
            selectedIDs: selectedIDs,
            playlistID: playlist.id
        )
        let changed = updated.filter { selectedIDs.contains($0.id) }
        for alarm in changed {
            alarmStore.update(alarm)
        }
        for alarm in changed {
            if let source = BackupLoudVariantService.sourceToPrepare(
                backupMinutes: alarm.backupMinutes,
                resolvedSourceFileName: AlarmScheduler.shared.backupSourceFileName(for: alarm)
            ) {
                BackupLoudVariantService.prepareInBackground(for: source)
            }
        }
        AlarmScheduler.shared.syncAlarms(
            alarmStore.alarms,
            editedEntryIDs: selectedIDs,
            trigger: .edit
        )
        finish(.apply)
    }

    private func finish(_ action: PlaylistApplyAction) {
        guard !didFinish else { return }
        didFinish = true
        onFinish(action, selectedIDs.count)
    }
}
