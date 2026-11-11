import SwiftUI

/// 休みの日付表示（#197）。
enum AlarmSkipFormat {
    static func day(_ date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func holiday(_ holiday: JapaneseHoliday) -> String {
        guard let date = AlarmSkipLogic.date(fromKey: holiday.dateKey) else {
            return holiday.dateKey
        }
        return "\(day(date))・\(String(localized: "holiday_mark"))"
    }
}

// MARK: - 次に鳴る日

/// 一覧の一番上に置く「次に鳴る日」のまとまり（#197）。
struct AlarmSkipDaySection: View {
    let group: AlarmSkipLogic.DayGroup
    let onSelect: () -> Void
    let onRange: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AlarmSkipFormat.day(group.date))
                        .font(.headline)
                    Text(timesText)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
                Text(String(format: String(localized: "skip_alarm_count"), group.entries.count))
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                if group.oneTimeCount > 0 {
                    Text(String(
                        format: String(localized: "skip_one_time_warning"),
                        group.oneTimeCount
                    ))
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                }

                buttons
            }
            .padding(.vertical, 4)
        } header: {
            WarmSectionHeader(title: String(localized: "skip_section_header"))
        }
    }

    private var timesText: String {
        group.entries.map(\.timeString).joined(separator: "・")
    }

    @ViewBuilder
    private var buttons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                skipThisDay
                selectButton
                rangeButton
            }
        } else {
            HStack(spacing: 8) {
                skipThisDay
                selectButton
                rangeButton
            }
        }
    }

    private var skipThisDay: some View {
        Button("skip_this_day") {
            AlarmSkipService.skipDay(group.date, entries: group.entries)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.textSecondary.opacity(0.35))
        )
        .accessibilityIdentifier("skip.day")
    }

    private var selectButton: some View {
        Button("skip_select", action: onSelect)
            .buttonStyle(.borderless)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.textSecondary.opacity(0.35))
            )
            .accessibilityIdentifier("skip.select")
    }

    private var rangeButton: some View {
        Button("skip_range", action: onRange)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("skip.range")
    }
}

// MARK: - 休みの案内

/// 「11/12（水）は休み・次は 11/13（木）6:00［取り消す］」（#197）。
struct AlarmSkipNoticeView: View {
    let notice: AlarmSkipLogic.Notice
    let onUndo: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("skip.notice")
            Spacer(minLength: 8)
            Button("skip_undo", action: onUndo)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("skip.undo")
        }
    }

    private var message: String {
        if let next = notice.nextFire {
            return String(
                format: String(localized: "skip_active_notice"),
                AlarmSkipFormat.day(notice.date),
                "\(AlarmSkipFormat.day(next)) \(AlarmSkipFormat.time(next))"
            )
        }
        return String(
            format: String(localized: "skip_active_notice_no_next"),
            AlarmSkipFormat.day(notice.date)
        )
    }
}

// MARK: - 選んで休む

struct AlarmSkipSelectionSheet: View {
    let date: Date
    let entries: [AlarmEntry]

    @Environment(\.dismiss) private var dismiss
    @State private var skipped: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(entries) { entry in
                        Button {
                            if skipped.contains(entry.id) {
                                skipped.remove(entry.id)
                            } else {
                                skipped.insert(entry.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: skipped.contains(entry.id)
                                    ? "circle"
                                    : "checkmark.circle.fill")
                                    .foregroundStyle(skipped.contains(entry.id)
                                        ? Color.textSecondary
                                        : Brand.orange)
                                Text("\(entry.timeString)  \(entry.label)")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("skipSelect.row.\(entry.id.uuidString)")
                    }
                } footer: {
                    Text("skip_select_hint")
                }
            }
            .navigationTitle(String(localized: "skip_select_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("skip_apply") {
                        AlarmSkipService.skipSelected(skipped, date: date)
                        dismiss()
                    }
                    .disabled(skipped.isEmpty)
                    .accessibilityIdentifier("skipSelect.apply")
                }
            }
        }
    }
}

// MARK: - 期間を選ぶ

struct AlarmSkipPeriodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.startOfDay(for: Date())

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "skip_start_date",
                    selection: $start,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("skipRange.start")
                DatePicker(
                    "skip_end_date",
                    selection: $end,
                    in: start...,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("skipRange.end")
            }
            .navigationTitle(String(localized: "skip_range_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("skip_apply") {
                        AlarmSkipService.skipRange(from: start, to: end)
                        dismiss()
                    }
                    .accessibilityIdentifier("skipRange.apply")
                }
            }
        }
    }
}

// MARK: - 祝日

/// 「この祝日は鳴らす」の一覧（#197）。
struct HolidayOverrideSheet: View {
    let holidays: [JapaneseHoliday]
    @Binding var overrides: Set<String>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(holidays) { holiday in
                        Toggle(isOn: Binding(
                            get: { overrides.contains(holiday.dateKey) },
                            set: { ring in
                                if ring {
                                    overrides.insert(holiday.dateKey)
                                } else {
                                    overrides.remove(holiday.dateKey)
                                }
                                AnalyticsService.shared.capture(.holidayRingOverride)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AlarmSkipFormat.holiday(holiday))
                                Text(holiday.name)
                                    .font(.footnote)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .accessibilityIdentifier("holiday.override.\(holiday.dateKey)")
                    }
                } footer: {
                    Text("holiday_ring_on")
                }
            }
            .navigationTitle(String(localized: "holiday_overrides_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("close") { dismiss() }
                }
            }
        }
    }
}
