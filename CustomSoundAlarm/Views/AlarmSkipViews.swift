import SwiftUI

/// 休みの日付表示（#197）。
enum AlarmSkipFormat {
    /// 「11/14（金）」。月日は数字で、曜日を添える（#197）。
    static func day(_ date: Date, locale: Locale = .current) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.setLocalizedDateFormatFromTemplate("Md")
        let datePart = dateFormatter.string(from: date)

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = locale
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE")
        let weekday = weekdayFormatter.string(from: date)

        let language = locale.language.languageCode?.identifier ?? ""
        if ["ja", "zh", "ko"].contains(language) {
            return "\(datePart)（\(weekday)）"
        }
        return "\(datePart) (\(weekday))"
    }

    /// 「11/14（金）22:40」
    static func dayAndTime(_ date: Date, locale: Locale = .current) -> String {
        "\(day(date, locale: locale)) \(time(date))"
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

    static func month(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: date)
    }

    /// 8週間先まで選べるときの、最後の日。
    static func maxSelectableDay(
        from now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(
            byAdding: .day,
            value: AlarmSkipLogic.maxGlobalSkipDays,
            to: today
        ) ?? today
    }
}

// MARK: - 一覧上部の1行

/// 「11/20（木）22:40 まで休み・4本 ［取り消す］」（#197 画面作り直し）。
struct GlobalSkipNoticeRow: View {
    let skip: GlobalSkip
    let entries: [AlarmEntry]
    let onUndo: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    message
                    undoButton
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    message
                    Spacer(minLength: 8)
                    undoButton
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var message: some View {
        Text(String(
            format: String(localized: "skip_all_active_fmt"),
            AlarmSkipFormat.dayAndTime(skip.end),
            count
        ))
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("skipAll.notice")
    }

    private var undoButton: some View {
        Button("skip_undo", action: onUndo)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("skipAll.undo")
    }

    private var count: Int {
        AlarmSkipLogic.globalSkipAlarmCount(skip: skip, entries: entries)
    }
}

// MARK: - すべてのアラームを休む

/// 右上の bell.slash から開くシート（#197 画面作り直し）。
struct SkipAllSheet: View {
    let entries: [AlarmEntry]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showingCalendar = false
    /// 押す前から出す案内は、いちばん短い24時間で計算する。
    private var previewInterval: DateInterval? {
        AlarmSkipLogic.presetInterval(.hours24, from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 0) {
                        presetRow(.hours24)
                        Divider().padding(.leading, 16)
                        presetRow(.days3)
                        Divider().padding(.leading, 16)
                        presetRow(.days7)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )

                    Button {
                        showingCalendar = true
                    } label: {
                        Label("skip_all_custom", systemImage: "calendar")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .accessibilityIdentifier("skipAll.custom")

                    summary
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "skip_all_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCalendar) {
                SkipAllCalendarSheet(entries: entries) {
                    dismiss()
                }
                .presentationDetents([.large])
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Presets

    private func presetRow(_ preset: AlarmSkipLogic.GlobalSkipPreset) -> some View {
        let interval = AlarmSkipLogic.presetInterval(preset, from: Date())
        let count = interval.map {
            AlarmSkipLogic.occurrenceCount(entries: entries, in: $0)
        } ?? 0
        return Button {
            AlarmSkipService.skipAll(preset: preset)
            dismiss()
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(for: preset))
                        endText(interval: interval, count: count)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(title(for: preset))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        endText(interval: interval, count: count)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(16)
        .disabled(count == 0)
        .accessibilityIdentifier("skipAll.preset.\(preset.rawValue)")
    }

    private func endText(interval: DateInterval?, count: Int) -> some View {
        Text(String(
            format: String(localized: "skip_all_row_fmt"),
            interval.map { AlarmSkipFormat.dayAndTime($0.end) } ?? "",
            count
        ))
        .font(.footnote)
        .foregroundStyle(Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func title(for preset: AlarmSkipLogic.GlobalSkipPreset) -> LocalizedStringKey {
        switch preset {
        case .hours24: "skip_all_24h"
        case .days3: "skip_all_3d"
        case .days7: "skip_all_7d"
        case .custom: "skip_all_custom"
        }
    }

    private func distinctTimes(_ occurrences: [Date]) -> [String] {
        var seen: Set<String> = []
        var times: [String] = []
        for occurrence in occurrences {
            let time = AlarmSkipFormat.time(occurrence)
            if seen.insert(time).inserted {
                times.append(time)
            }
        }
        return times
    }

    // MARK: - Summary

    @ViewBuilder
    private var summary: some View {
        if let interval = previewInterval {
            let occurrences = AlarmSkipLogic.occurrences(entries: entries, in: interval)
            let oneTime = AlarmSkipLogic.oneTimeCount(entries: entries, in: interval)
            VStack(alignment: .leading, spacing: 8) {
                Text(String(
                    format: String(localized: "skip_all_summary_fmt"),
                    distinctTimes(occurrences).joined(separator: "・")
                ))
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("skipAll.summary")

                if oneTime > 0 {
                    Text(String(
                        format: String(localized: "skip_one_time_warning"),
                        oneTime
                    ))
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("skipAll.oneTimeWarning")
                }
            }
        }
    }
}

// MARK: - 日付を選ぶ

/// 開始日と終了日を月のカレンダーで選ぶ（ドラム式は使わない・#197）。
struct SkipAllCalendarSheet: View {
    let entries: [AlarmEntry]
    /// 休みに入ったあと、呼び出し元のシートも閉じる。
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var startDay: Date
    @State private var endDay: Date
    @State private var visibleMonth: Date

    private let calendar = Calendar.current
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    init(entries: [AlarmEntry], onApply: @escaping () -> Void) {
        self.entries = entries
        self.onApply = onApply
        let start = AlarmSkipLogic.nextFiringDay(entries: entries, after: Date())
        _startDay = State(initialValue: start)
        _endDay = State(initialValue: start)
        let calendar = Calendar.current
        _visibleMonth = State(
            initialValue: calendar.date(
                from: calendar.dateComponents([.year, .month], from: start)
            ) ?? start
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    monthHeader
                    weekdayHeader
                    monthGrid
                    Text("skip_calendar_hint")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    rangeSummary
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "skip_calendar_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("skip_apply") {
                        AlarmSkipService.skipAll(startDay: startDay, endDay: endDay)
                        dismiss()
                        onApply()
                    }
                    .disabled(interval == nil || occurrenceCount == 0)
                    .accessibilityIdentifier("skipCalendar.apply")
                }
            }
        }
        .accessibilityIdentifier("skipCalendar.root")
    }

    private var interval: DateInterval? {
        AlarmSkipLogic.customInterval(startDay: startDay, endDay: endDay)
    }

    private var occurrenceCount: Int {
        guard let interval else { return 0 }
        return AlarmSkipLogic.occurrenceCount(entries: entries, in: interval)
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canMoveMonth(by: -1))
            .accessibilityLabel(Text("skip_calendar_previous_month"))
            .accessibilityIdentifier("skipCalendar.previousMonth")

            Spacer()
            Text(AlarmSkipFormat.month(visibleMonth, calendar: calendar))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canMoveMonth(by: 1))
            .accessibilityLabel(Text("skip_calendar_next_month"))
            .accessibilityIdentifier("skipCalendar.nextMonth")
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: cellHeight)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let key = AlarmSkipLogic.dateKey(day, calendar: calendar)
        let isStart = calendar.isDate(day, inSameDayAs: startDay)
        let isEnd = calendar.isDate(day, inSameDayAs: endDay)
        let inRange = day >= calendar.startOfDay(for: startDay)
            && day <= calendar.startOfDay(for: endDay)
        let selectable = isSelectable(day)
        Button {
            select(day)
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(
                    size: dynamicTypeSize.isAccessibilitySize ? 22 : 17,
                    weight: .regular
                ))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: cellHeight)
                .background {
                    if inRange {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Brand.orange.opacity(0.15))
                    }
                }
                .overlay {
                    if isStart || isEnd {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Brand.orange, lineWidth: 2)
                    }
                }
                .foregroundStyle(selectable ? Color.primary : Color.textMuted)
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .accessibilityLabel(Text(AlarmSkipFormat.day(day)))
        .accessibilityAddTraits(isStart || isEnd ? .isSelected : [])
        .accessibilityIdentifier("skipCalendar.day.\(key)")
    }

    // MARK: - Range

    private var rangeSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(
                format: String(localized: "skip_calendar_range_fmt"),
                AlarmSkipFormat.day(startDay),
                AlarmSkipFormat.day(endDay)
            ))
            .font(.subheadline)
            .accessibilityIdentifier("skipCalendar.range")

            if let interval {
                Text(String(
                    format: String(localized: "skip_all_row_fmt"),
                    AlarmSkipFormat.dayAndTime(interval.end),
                    occurrenceCount
                ))
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Calendar math

    private var cellHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 58 : 42
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[first...] + symbols[..<first])
    }

    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth),
              let first = calendar.date(
                  from: calendar.dateComponents([.year, .month], from: visibleMonth)
              )
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: first)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            days.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        return days
    }

    private func isSelectable(_ day: Date) -> Bool {
        let today = calendar.startOfDay(for: Date())
        let maxDay = AlarmSkipLogic.maxGlobalSkipDays
        let last = calendar.date(byAdding: .day, value: maxDay, to: today) ?? today
        let target = calendar.startOfDay(for: day)
        return target >= today && target <= last
    }

    private func select(_ day: Date) {
        let target = calendar.startOfDay(for: day)
        if target < calendar.startOfDay(for: startDay) {
            startDay = target
            endDay = target
        } else if calendar.isDate(startDay, inSameDayAs: endDay) {
            endDay = target
        } else {
            startDay = target
            endDay = target
        }
    }

    private func canMoveMonth(by offset: Int) -> Bool {
        guard let target = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else {
            return false
        }
        let todayMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: Date())
        ) ?? Date()
        let maxMonth = calendar.date(
            from: calendar.dateComponents(
                [.year, .month],
                from: AlarmSkipFormat.maxSelectableDay(calendar: calendar)
            )
        ) ?? Date()
        return target >= todayMonth && target <= maxMonth
    }

    private func moveMonth(by offset: Int) {
        guard let target = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else {
            return
        }
        visibleMonth = target
    }
}

// MARK: - 編集画面の日付を選んで休む

/// 月のカレンダーで複数の日付を選ぶ（ドラム式は使わない・#197）。
struct AlarmSkipDatesSheet: View {
    @Binding var skipDates: Set<String>

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<DateComponents>

    private let calendar = Calendar.current

    init(skipDates: Binding<Set<String>>) {
        _skipDates = skipDates
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let last = AlarmSkipFormat.maxSelectableDay(calendar: calendar)
        let components = skipDates.wrappedValue.compactMap { key -> DateComponents? in
            guard let date = AlarmSkipLogic.date(fromKey: key, calendar: calendar),
                  date >= today, date <= last else {
                return nil
            }
            return calendar.dateComponents([.year, .month, .day], from: date)
        }
        _selection = State(initialValue: Set(components))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    datePicker
                        .accessibilityIdentifier("skipDates.calendar")
                }

                Section {
                    if selectedDates.isEmpty {
                        Text("skip_dates_empty")
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        ForEach(selectedDates, id: \.self) { date in
                            Text(AlarmSkipFormat.day(date))
                        }
                    }
                } header: {
                    Text("skip_dates_selected")
                } footer: {
                    Text("skip_dates_footer")
                }
            }
            .navigationTitle(String(localized: "skip_dates_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("close") { dismiss() }
                        .accessibilityIdentifier("skipDates.close")
                }
            }
            .onChange(of: selection) { _, newValue in
                skipDates = dateKeys(from: newValue)
            }
        }
        .accessibilityIdentifier("skipDates.root")
    }

    private var datePicker: some View {
        let range = validRange
        return MultiDatePicker(selection: $selection, in: range) {
            EmptyView()
        }
    }

    private var validRange: Range<Date> {
        let today = calendar.startOfDay(for: Date())
        let last = AlarmSkipFormat.maxSelectableDay(calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return today..<end
    }

    private var selectedDates: [Date] {
        var dates: [Date] = []
        for components in selection {
            if let date = calendar.date(from: components) {
                dates.append(date)
            }
        }
        return dates.sorted()
    }

    private func dateKeys(from selection: Set<DateComponents>) -> Set<String> {
        let today = calendar.startOfDay(for: Date())
        let last = AlarmSkipFormat.maxSelectableDay(calendar: calendar)
        var keys: Set<String> = []
        for components in selection {
            guard let date = calendar.date(from: components),
                  date >= today, date <= last else { continue }
            keys.insert(AlarmSkipLogic.dateKey(date, calendar: calendar))
        }
        return keys
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
