import SwiftUI

/// メイン画面：アラーム一覧 + 音源管理
struct ContentView: View {
    @State private var alarmStore = AlarmStore.shared
    @State private var soundStore = SoundStore.shared
    @State private var showingAddAlarm = false
    @State private var showingSoundPicker = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - アラーム一覧
                Section {
                    if alarmStore.alarms.isEmpty {
                        ContentUnavailableView(
                            "アラームなし",
                            systemImage: "alarm",
                            description: Text("＋ボタンからアラームを追加")
                        )
                    } else {
                        ForEach(alarmStore.alarms) { alarm in
                            AlarmRow(alarm: alarm) {
                                alarmStore.toggleEnabled(alarm)
                                Task {
                                    await AlarmScheduler.shared.syncAlarms(alarmStore.alarms)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                alarmStore.remove(alarmStore.alarms[index])
                            }
                            Task {
                                await AlarmScheduler.shared.syncAlarms(alarmStore.alarms)
                            }
                        }
                    }
                } header: {
                    Text("アラーム")
                }

                // MARK: - サウンド一覧
                Section {
                    if soundStore.sounds.isEmpty {
                        Text("音源を追加してください")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(soundStore.sounds) { sound in
                            Label(sound.name, systemImage: sound.isPreset ? "speaker.wave.2" : "waveform")
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                soundStore.remove(soundStore.sounds[index])
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("サウンド")
                        Spacer()
                        Button {
                            showingSoundPicker = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                }
            }
            .navigationTitle("Custom Alarm")
            .onAppear {
                // プリセット音が未登録なら追加
                if !soundStore.sounds.contains(where: { $0.fileName == "PresetAlarm.caf" }) {
                    let preset = AlarmSound(
                        name: "プリセット",
                        fileName: "PresetAlarm.caf",
                        isPreset: true
                    )
                    soundStore.add(preset)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddAlarm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAlarm) {
                AddAlarmView()
            }
            .sheet(isPresented: $showingSoundPicker) {
                SoundPickerView()
            }
        }
    }
}

// MARK: - AlarmRow

struct AlarmRow: View {
    let alarm: AlarmEntry
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.timeString)
                    .font(.system(size: 40, weight: .light, design: .rounded))
                HStack(spacing: 4) {
                    Text(alarm.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !alarm.soundFileName.isEmpty {
                        Text("・\(alarm.soundFileName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
