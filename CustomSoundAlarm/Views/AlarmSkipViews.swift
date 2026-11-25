import SwiftUI
import UIKit

/// 目覚まし時計の右下に禁止マーク（⊘）を付けたアイコン（#197 実機レビュー）。
///
/// 斜線を時計に重ねる案は、小さいと針と斜線が重なって時計に見えなかった。
/// 時計の形はそのまま残し、右下を丸く抜いて禁止マークを置く。
/// 「鳴らさない設定中」は呼び出し側で色（オレンジ）を変えて示す。
///
/// 休みの行に出すときは `circleProgress` / `slashProgress` / `gapProgress` を
/// 0 から 1 へ動かして、丸と斜線を描く（#296）。
struct AlarmOffIcon: View {
    /// メニュー用に ImageRenderer から描くときの固定サイズ。nil なら Dynamic Type。
    var pointSize: CGFloat?
    /// 時計の濃さ。層が出たあとに時計を出すために使う（#296）。
    var clockOpacity: Double = 1
    /// 禁止の丸を描く進み具合（0...1）。
    var circleProgress: CGFloat = 1
    /// 斜線を引く進み具合（0...1）。
    var slashProgress: CGFloat = 1
    /// 時計の抜きを広げる進み具合（0...1）。丸と一緒に動かす。
    var gapProgress: CGFloat = 1

    @ScaledMetric(relativeTo: .body) private var scaledPointSize: CGFloat = 17

    private var size: CGFloat { pointSize ?? scaledPointSize }

    /// 時計の枠に対する禁止マークの直径・中心・抜く余白（描画して比べて決めた値）。
    static let badgeDiameterRatio: CGFloat = 0.62
    static let badgeCenterInsetRatio: CGFloat = 0.25
    static let badgeGapRatio: CGFloat = 0.10
    /// 禁止の丸（中心線）の半径と線の太さ。`nosign` を測って合わせた値。
    static let badgeRingRadiusRatio: CGFloat = 0.340
    static let badgeRingStrokeRatio: CGFloat = 0.118
    /// 斜線の端（丸の内側）の位置。
    static let badgeSlashRadiusRatio: CGFloat = 0.235

    private var clockSize: CGSize {
        let symbol = UIImage(systemName: "alarm")?.size ?? CGSize(width: 1, height: 1)
        let ratio = symbol.height > 0 ? symbol.width / symbol.height : 1
        return CGSize(width: size * ratio, height: size)
    }

    private var badgeDiameter: CGFloat { size * Self.badgeDiameterRatio }

    /// 時計の枠（左上原点）での禁止マークの中心。右下の角から内側へ寄せる。
    private var badgeCenter: CGPoint {
        CGPoint(
            x: clockSize.width - badgeDiameter * Self.badgeCenterInsetRatio,
            y: clockSize.height - badgeDiameter * Self.badgeCenterInsetRatio
        )
    }

    /// 時計とマークの両方が収まる枠。
    private var canvasSize: CGSize {
        let radius = badgeDiameter / 2
        return CGSize(
            width: max(clockSize.width, badgeCenter.x + radius),
            height: max(clockSize.height, badgeCenter.y + radius)
        )
    }

    var body: some View {
        let radius = badgeDiameter / 2
        let cutoutRadius = (radius + size * Self.badgeGapRatio) * gapProgress
        let ringDiameter = badgeDiameter * Self.badgeRingRadiusRatio * 2
        let ringStroke = badgeDiameter * Self.badgeRingStrokeRatio
        ZStack(alignment: .topLeading) {
            Image(systemName: "alarm")
                .resizable()
                .scaledToFit()
                .frame(width: clockSize.width, height: clockSize.height)
                .opacity(clockOpacity)
                .mask(
                    BadgeCutoutMask(center: badgeCenter, radius: cutoutRadius)
                        .fill(style: FillStyle(eoFill: true))
                )

            Circle()
                .trim(from: 0, to: circleProgress)
                .stroke(style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
                .frame(width: ringDiameter, height: ringDiameter)
                .rotationEffect(.degrees(-90))
                .position(badgeCenter)

            AlarmOffSlash(
                endRadius: badgeDiameter * Self.badgeSlashRadiusRatio
            )
            .trim(from: 0, to: slashProgress)
            .stroke(style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
            .frame(width: badgeDiameter, height: badgeDiameter)
            .position(badgeCenter)
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// 時計の右下を丸く抜くマスク（even-odd）。blendMode は toolbar で効かないため使わない。
private struct BadgeCutoutMask: Shape {
    let center: CGPoint
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -radius, dy: -radius))
        path.addEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        return path
    }
}

/// 禁止マークの斜線（左上から右下へ）。`trim` で引かれるようにする（#296 実機確認）。
///
/// `nosign` と同じ「＼」の向き。`trim` は始点から終点へ描くので、
/// 引くときは左上から右下へ、戻るときは右下から左上へ消える。
private struct AlarmOffSlash: Shape {
    /// 中心から斜線の端までの距離（斜線の枠の幅に対する比ではなく実寸）。
    let endRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let offset = endRadius / sqrt(2)
        var path = Path()
        path.move(to: CGPoint(x: center.x - offset, y: center.y - offset))
        path.addLine(to: CGPoint(x: center.x + offset, y: center.y + offset))
        return path
    }
}

/// `Label` の icon に使うため、`AlarmOffIcon` を UIImage にする。
@MainActor
enum AlarmOffIconRenderer {
    private static var cache: [CGFloat: UIImage] = [:]

    static func image(pointSize: CGFloat) -> UIImage? {
        if let cached = cache[pointSize] { return cached }
        let renderer = ImageRenderer(
            content: AlarmOffIcon(pointSize: pointSize)
                .foregroundStyle(.black)
        )
        renderer.scale = UIScreen.main.scale
        guard let image = renderer.uiImage else { return nil }
        cache[pointSize] = image
        return image
    }
}

/// 休みの日付表示（#197）。
enum AlarmSkipFormat {
    /// 「11/14（金）」。今年は月日だけ、今年以外は年を付ける（#197 実機レビュー）。
    static func day(
        _ date: Date,
        locale: Locale = .current,
        now: Date = Date(),
        includeYear: Bool = true
    ) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)
        let template = includeYear && !sameYear ? "yMd" : "Md"
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.setLocalizedDateFormatFromTemplate(template)
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
    static func dayAndTime(
        _ date: Date,
        locale: Locale = .current,
        now: Date = Date()
    ) -> String {
        "\(day(date, locale: locale, now: now)) \(time(date))"
    }

    /// 祝日の一覧の年見出し（ja は「2027年」）。
    static func year(_ year: Int, locale: Locale = .current) -> String {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("y")
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

/// 「⊘ 11/20（木）22:40 まで鳴りません・4本 ［再開］」（#197 / #296）。
///
/// いつまで・何本を出すのは一覧のこの1行だけ。カードや影は付けない。
struct GlobalSkipNoticeRow: View {
    let skip: GlobalSkip
    let entries: [AlarmEntry]
    let onResume: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    message
                    resumeButton
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    message
                    Spacer(minLength: 8)
                    resumeButton
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var message: some View {
        HStack(alignment: .center, spacing: 6) {
            AlarmOffIcon()
                .foregroundStyle(Color.actionText)
            Text(String(
                format: String(localized: "skip_all_active_fmt"),
                AlarmSkipFormat.dayAndTime(skip.end),
                count
            ))
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("skipAll.notice")
        }
    }

    private var resumeButton: some View {
        Button("skip_resume", action: onResume)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("skipAll.resume")
    }

    private var count: Int {
        AlarmSkipLogic.globalSkipAlarmCount(skip: skip, entries: entries)
    }
}

// MARK: - 止まっている行の層（#296）

/// 止めるとき・再開するときの時間（#296。実機確認でゆっくりにした）。
enum PausedRowTiming {
    /// 出るときに、上の行からずらす幅。
    static let stagger: TimeInterval = 0.08
    /// 戻るときに、上の行からずらす幅。
    static let exitStagger: TimeInterval = 0.06
    /// 帯が開く時間と、開ききってから行を動かすまでの待ち。
    static let noticeIn: TimeInterval = 0.30
    static let noticeSettle: TimeInterval = 0.40
    /// 帯が閉じる時間。
    static let noticeOut: TimeInterval = 0.30
    /// 行が戻りきってから、帯を閉じ始めるまで（いちばん下の行が 4 本のとき約 1.25 秒）。
    static let noticeCloseFloor: TimeInterval = 1.25

    /// 出るとき：層 → 時計 → 丸 → 斜線。時間は行が動き始めてから。
    static let layerIn: TimeInterval = 0.30
    static let clockStart: TimeInterval = 0.12
    static let clockIn: TimeInterval = 0.25
    static let circleStart: TimeInterval = 0.30
    static let circleIn: TimeInterval = 0.45
    static let slashStart: TimeInterval = 0.78
    static let slashIn: TimeInterval = 0.30

    /// 戻るとき：斜線 → 丸 → 層と時計（#296 実機確認）。
    static let slashOut: TimeInterval = 0.28
    static let circleOutStart: TimeInterval = 0.25
    static let circleOut: TimeInterval = 0.40
    static let layerOutStart: TimeInterval = 0.72
    static let layerOut: TimeInterval = 0.30

    /// 何番目に止まった行か（上から）でずらす。
    static func delay(forPausedIndex index: Int) -> TimeInterval {
        max(0, Double(index)) * stagger
    }

    /// 戻るときのずらし幅。
    static func exitDelay(forPausedIndex index: Int) -> TimeInterval {
        max(0, Double(index)) * exitStagger
    }

    /// 再開してから、いちばん下の行まで戻りきるまで（#296 実機確認）。
    static func exitEnd(pausedCount: Int) -> TimeInterval {
        exitDelay(forPausedIndex: max(0, pausedCount - 1))
            + layerOutStart
            + layerOut
    }

    /// 帯を閉じ始めるまで。行が戻りきるのを待ち、4 本なら約 1.25 秒。
    static func noticeCloseDelay(pausedCount: Int) -> TimeInterval {
        max(noticeCloseFloor, exitEnd(pausedCount: pausedCount))
    }
}

/// 止まっている行に、カードと同じ形でかぶせる層（#296）。
///
/// 出るとき：帯が開ききってから 0.4 秒待ち、層 → 時計 → 丸 → 斜線。
/// 消えるときは逆に、斜線 → 丸 → 層と時計（#296 実機確認）。
/// 行の高さは変えず、タップはこの層が受ける（下のスイッチには届かない）。
struct PausedAlarmOverlay: View {
    let isPaused: Bool
    /// 上から何番目に止まっている行か（ずらす順番）。
    let pausedIndex: Int
    /// 帯が開ききるまでの待ち。止めた瞬間に画面に出ていた行だけが使う。
    var entryDelay: TimeInterval = 0
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var layerOpacity: Double = 0
    @State private var clockOpacity: Double = 0
    @State private var circleProgress: CGFloat = 0
    @State private var slashProgress: CGFloat = 0
    @State private var gapProgress: CGFloat = 0
    /// 層が出ている間だけ、下の行の代わりにタップを受ける。
    @State private var receivesTouches = false
    @State private var transitionTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.warmListBackground.opacity(0.85))
                .opacity(layerOpacity)

            AlarmOffIcon(
                pointSize: 36,
                clockOpacity: clockOpacity,
                circleProgress: circleProgress,
                slashProgress: slashProgress,
                gapProgress: gapProgress
            )
            .foregroundStyle(Color.actionText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 行の中身とカードの縁の差（List の行の余白とカードの 4pt/3pt）だけ広げる。
        .padding(.horizontal, -12)
        .padding(.vertical, -13)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            guard receivesTouches else { return }
            onTap()
        }
        .allowsHitTesting(receivesTouches)
        // 本番では層を読み上げず、行の先頭に状態を足す（#296）。
        // UI テストのときだけ、出ている間は見つけられるようにする。
        .modifier(PausedRowOverlayAccessibility(isPaused: isPaused))
        .onAppear {
            if isPaused {
                showWithoutAnimation()
            }
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                runEnter()
            } else {
                runExit()
            }
        }
        .onDisappear {
            transitionTask?.cancel()
        }
    }

    /// 画面に出したときすでに止まっていた行（起動直後など）は、そのまま見せる。
    private func showWithoutAnimation() {
        transitionTask?.cancel()
        layerOpacity = 1
        clockOpacity = 1
        circleProgress = 1
        slashProgress = 1
        gapProgress = 1
        receivesTouches = true
    }

    private func runEnter() {
        transitionTask?.cancel()
        receivesTouches = true
        if reduceMotion {
            withAnimation(.easeOut(duration: PausedRowTiming.layerIn)) {
                layerOpacity = 1
                clockOpacity = 1
                circleProgress = 1
                slashProgress = 1
                gapProgress = 1
            }
            return
        }
        let delay = entryDelay + PausedRowTiming.delay(forPausedIndex: pausedIndex)
        transitionTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            withAnimation(.timingCurve(0.05, 0.7, 0.1, 1, duration: PausedRowTiming.layerIn)) {
                layerOpacity = 1
            }
            try? await Task.sleep(for: .seconds(PausedRowTiming.clockStart))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.05, 0.7, 0.1, 1, duration: PausedRowTiming.clockIn)) {
                clockOpacity = 1
            }
            try? await Task.sleep(for: .seconds(
                PausedRowTiming.circleStart - PausedRowTiming.clockStart
            ))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: PausedRowTiming.circleIn)) {
                circleProgress = 1
                gapProgress = 1
            }
            try? await Task.sleep(for: .seconds(
                PausedRowTiming.slashStart - PausedRowTiming.circleStart
            ))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: PausedRowTiming.slashIn)) {
                slashProgress = 1
            }
        }
    }

    private func runExit() {
        transitionTask?.cancel()
        receivesTouches = false
        if reduceMotion {
            withAnimation(.easeInOut(duration: PausedRowTiming.layerOut)) {
                layerOpacity = 0
                clockOpacity = 0
                circleProgress = 0
                slashProgress = 0
                gapProgress = 0
            }
            return
        }
        transitionTask = Task { @MainActor in
            let delay = PausedRowTiming.exitDelay(forPausedIndex: pausedIndex)
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            // 斜線は右下から左上へ戻る（`trim` の終点が縮む）。
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: PausedRowTiming.slashOut)) {
                slashProgress = 0
            }
            try? await Task.sleep(for: .seconds(PausedRowTiming.circleOutStart))
            guard !Task.isCancelled else { return }
            // 丸は反時計回りに戻る。
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: PausedRowTiming.circleOut)) {
                circleProgress = 0
                gapProgress = 0
            }
            // 行が戻り始めてから layerOutStart 後に、層と時計を消す。
            try? await Task.sleep(for: .seconds(
                PausedRowTiming.layerOutStart - PausedRowTiming.circleOutStart
            ))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: PausedRowTiming.layerOut)) {
                layerOpacity = 0
                clockOpacity = 0
            }
        }
    }
}

/// 層の読み上げ。本番は隠し、UI テストのときだけ止まっている行を見つけられるようにする。
private struct PausedRowOverlayAccessibility: ViewModifier {
    let isPaused: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if AppGroup.isUITestExposePausedRow && isPaused {
            content
                .accessibilityElement()
                .accessibilityIdentifier("paused.row.overlay")
        } else {
            content.accessibilityHidden(true)
        }
    }
}

// MARK: - すべてのアラームを休む

/// 右上の目覚まし時計＋禁止マークのアイコンから開くシート（#197 画面作り直し）。
struct SkipAllSheet: View {
    let entries: [AlarmEntry]
    /// いま全体の休み中なら、シートから再開できる（#296）。
    var hasActiveSkip: Bool = false

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
                ToolbarItemGroup(placement: .confirmationAction) {
                    if hasActiveSkip {
                        Button("skip_resume") {
                            AlarmSkipService.undoAll()
                            dismiss()
                        }
                        .accessibilityIdentifier("skipAll.sheetResume")
                    }
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

    /// 24時間の間に鳴らなくなるアラーム（最大4本＋「ほかN本」）。
    private func silencedEntries(in interval: DateInterval) -> [AlarmEntry] {
        entries.filter { alarm in
            !AlarmSkipLogic.occurrences(of: alarm, in: interval).isEmpty
        }
        .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    // MARK: - Summary

    @ViewBuilder
    private var summary: some View {
        if let interval = previewInterval {
            let silenced = silencedEntries(in: interval)
            let oneTime = AlarmSkipLogic.oneTimeCount(entries: entries, in: interval)
            VStack(alignment: .leading, spacing: 8) {
                if !silenced.isEmpty {
                    Text("skip_all_silenced_title")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("skipAll.silencedTitle")

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(silenced.prefix(4)) { alarm in
                            SkipSilencedAlarmRow(alarm: alarm)
                        }
                        if silenced.count > 4 {
                            Text(String(
                                format: String(localized: "skip_all_more_fmt"),
                                silenced.count - 4
                            ))
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityIdentifier("skipAll.more")
                        }
                    }
                    .accessibilityIdentifier("skipAll.silencedList")
                }

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

/// 一括シートに出す「鳴らなくなるアラーム」の小さな行（#197 実機レビュー）。
private struct SkipSilencedAlarmRow: View {
    let alarm: AlarmEntry

    var body: some View {
        HStack(spacing: 10) {
            SoundThumbnail(
                sound: AlarmSoundDisplay.representativeSound(for: alarm),
                size: 26
            )
            VStack(alignment: .leading, spacing: 1) {
                AlarmTimeText(
                    hour: alarm.hour,
                    minute: alarm.minute,
                    typography: AlarmTimeTypography(
                        digits: .subheadline,
                        period: .caption2,
                        spacing: 2
                    )
                )
                Text(displayName)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var displayName: String {
        if !alarm.label.isEmpty { return alarm.label }
        let soundName = AlarmSoundDisplay.name(for: alarm)
        return soundName.isEmpty ? String(localized: "default_sound") : soundName
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
