import SwiftUI

/// 全画面ベッドサイド時計モード。
///
/// 横向き全画面で時刻・カウントダウン・次回アラーム（音名付き）を表示し、
/// 画面消灯を抑止する。焼き付き対策・輝度制御・夜間配色・調整オーバーレイ・
/// 複数レイアウトを搭載。
struct BedsideClockView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var alarmStore = AlarmStore.shared
    @State private var soundStore = SoundStore.shared

    @State private var now = Date()
    @State private var offset = CGSize.zero
    @State private var isPresented = false
    @State private var isIdle = false
    @State private var showOverlay = false
    @State private var showHint = false

    // 輝度制御
    @State private var savedBrightness: CGFloat = 0.5
    @State private var idleTimer: Timer?
    @State private var overlayTimer: Timer?
    @State private var hintTimer: Timer?

    // ユーザー設定
    @State private var settings: BedsideClockLogic.BedsideSettings = loadSettings()

    // 計測（#68 / #71）
    @State private var sessionState = BedsideSessionState.initial(now: Date())
    @State private var exitMethod: BedsideExitMethod = .exitButton

    private let clockTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private let countdownTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let offsetTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()
                clockDisplay
                alarmInfoSection
                Spacer()
            }
            .offset(offset)

            // 初回ヒント（長押しで終了）
            if showHint {
                VStack {
                    Spacer()
                    Text("bedside_exit_hint")
                        .font(.callout)
                        .foregroundStyle(theme.infoColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .padding(.bottom, 60)
                }
            }

            if showOverlay {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeOverlay()
                    }

                settingsOverlay
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onReceive(clockTimer) { _ in now = Date() }
        .onReceive(countdownTimer) { _ in now = Date() }
        .onReceive(offsetTimer) { _ in offset = BedsideClockLogic.clockOffset(for: now) }
        .onAppear { enterMode() }
        .onDisappear { exitMode() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                // 輝度復帰（既存・#56 の3経路の1つ）: 一時的な中断でも早く戻すほうが安全なので
                // .inactive 含む非アクティブすべてで実行（計測とは意図的に非対称）
                restoreBrightness()
                UIApplication.shared.isIdleTimerDisabled = false
            }

            // 計測: 実バックグラウンド化（.background）でのみ退出イベントを発火する。
            // .inactive はコントロールセンター等の一時的な中断で、ベッドサイドモードでは
            // 夜中に開くだけで短時間滞在の誤発火になるため除外（#73 レビュー指摘）。
            // iOS は実バックグラウンド化で .active → .inactive → .background と順に遷移するため
            // .background だけを見ても取りこぼしはない。二重発火もしない。
            if phase == .background {
                let result = BedsideSessionLogic.background(sessionState, now: Date())
                sessionState = result.state
                if case let .exited(duration, method) = result.event {
                    captureExit(duration: duration, method: method)
                }
            } else if phase == .active && isPresented {
                UIApplication.shared.isIdleTimerDisabled = true
                applyBrightness()

                // 計測: 復帰でセッション再起点（二重計上防止・イベントは発火しない）
                let result = BedsideSessionLogic.foreground(sessionState, now: Date())
                sessionState = result.state
            }
        }
        .onTapGesture {
            handleTap()
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            exitMethod = .longPress
            dismiss()
        }
    }

    // MARK: - Clock Display

    @ViewBuilder
    private var clockDisplay: some View {
        switch clockLayout {
        case .analog:
            // アナログフェイス（#72 Phase1・無料）
            AnalogClockFaceView(
                date: now,
                theme: theme,
                showSeconds: settings.showSeconds,
                fontScale: settings.fontScale
            )
        case .word:
            // ワードクロック（#72 Phase1・無料）
            WordClockView(
                date: now,
                theme: theme,
                fontScale: settings.fontScale,
                visibleElementCount: settings.visibleElementCount
            )
        case .flipClock:
            // フリップ時計（#72 Phase2・Pro）
            FlipClockFaceView(
                date: now,
                theme: theme,
                fontScale: settings.fontScale
            )
        case .sevenSegment:
            // 7セグLED（#72 Phase2・Pro）
            SevenSegmentFaceView(
                date: now,
                theme: theme,
                showSeconds: settings.showSeconds,
                fontScale: settings.fontScale
            )
        case .dot:
            // ドットマトリクス（#72 Phase2・Pro）
            DotMatrixFaceView(
                date: now,
                theme: theme,
                showSeconds: settings.showSeconds,
                fontScale: settings.fontScale
            )
        case .digitalLarge, .minimal, .digitalBold:
            let is24 = BedsideClockLogic.is24HourFormat(for: now)
            let timeStr = BedsideClockLogic.timeString(for: now, is24Hour: is24, showSeconds: settings.showSeconds)
            let layout = clockLayout
            let baseFontSize = BedsideClockLogic.clockFontSize(
                visibleElementCount: settings.visibleElementCount,
                fontScale: settings.fontScale
            )
            let fontSize = baseFontSize * layout.sizeMultiplier

            Text(timeStr)
                .font(.system(size: fontSize, weight: layout.fontWeight, design: layout.fontDesign))
                .foregroundStyle(theme.clockColor)
                .minimumScaleFactor(0.5)
        }
    }

    // MARK: - Alarm Info

    @ViewBuilder
    private var alarmInfoSection: some View {
        let fireDate = BedsideClockLogic.nextAlarmFireDate(
            alarms: alarmStore.alarms,
            currentDate: now
        )

        if let fireDate {
            VStack(spacing: 6) {
                if settings.showCountdown {
                    let timeText = BedsideClockLogic.nextAlarmText(
                        alarms: alarmStore.alarms,
                        currentDate: now
                    ) ?? ""
                    let countdown = AlarmCountdown.untilString(from: now, to: fireDate)

                    HStack(spacing: 8) {
                        Image(systemName: "alarm")
                            .font(.caption)
                        Text("\(timeText) — \(countdown)")
                            .font(.caption)
                    }
                    .foregroundStyle(theme.infoColor)
                }

                if settings.showSoundName {
                    if let alarm = nextEnabledAlarm(), !alarm.soundFileName.isEmpty {
                        let soundName = soundStore.displayName(for: alarm.soundFileName)
                        Text(soundName)
                            .font(.caption2)
                            .foregroundStyle(theme.infoColor)
                    }
                }

                if settings.showDate {
                    Text(now, format: .dateTime.year().month().day())
                        .font(.caption2)
                        .foregroundStyle(theme.infoColor)
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                Text("bedside_no_alarm")
                    .font(.caption)
            }
            .foregroundStyle(theme.warningColor)
        }
    }

    private func nextEnabledAlarm() -> AlarmEntry? {
        BedsideClockLogic.nextAlarmFireDate(alarms: alarmStore.alarms, currentDate: now)
            .flatMap { fire in
                alarmStore.alarms
                    .filter { $0.isEnabled }
                    .filter { $0.nextFireDate(from: now) == fire }
                    .first
            }
    }

    // MARK: - Settings Overlay

    private var settingsOverlay: some View {
        VStack(spacing: 20) {
            // ヘッダー: chevron.down（オーバーレイを閉じる）
            HStack {
                Spacer()
                Button {
                    closeOverlay()
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title)
                        .foregroundStyle(theme.infoColor)
                }
            }

            // 明るさスライダー
            VStack(spacing: 8) {
                Text("bedside_brightness")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.infoColor)
                HStack(spacing: 16) {
                    Image(systemName: "sun.min")
                        .font(.title3)
                        .foregroundStyle(theme.infoColor)
                    Slider(
                        value: Binding(
                            get: { settings.brightnessOffset },
                            set: { newVal in
                                settings.brightnessOffset = newVal
                                saveSettings()
                                applyBrightness()
                            }
                        ),
                        in: 0.2...1.0,
                        // ドラッグ確定時（onEditingChanged=false）に1回だけ送信（#71・毎フレーム連打の防止）
                        onEditingChanged: { editing in
                            if !editing {
                                AnalyticsService.shared.capture(.bedsideSettingChanged(
                                    setting: .brightness,
                                    value: .number(settings.brightnessOffset)
                                ))
                            }
                        }
                    )
                    .tint(theme.clockColor)
                    .frame(maxWidth: 240)
                    Image(systemName: "sun.max")
                        .font(.title3)
                        .foregroundStyle(theme.infoColor)
                }
            }

            // 文字サイズスライダー
            VStack(spacing: 8) {
                Text("bedside_font_size")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.infoColor)
                HStack(spacing: 16) {
                    Text("A")
                        .font(.caption)
                        .foregroundStyle(theme.infoColor)
                    Slider(
                        value: Binding(
                            get: { settings.fontScale },
                            set: { newVal in
                                settings.fontScale = newVal
                                saveSettings()
                            }
                        ),
                        in: 0.7...1.5,
                        // ドラッグ確定時に1回だけ送信（#71・毎フレーム連打の防止）
                        onEditingChanged: { editing in
                            if !editing {
                                AnalyticsService.shared.capture(.bedsideSettingChanged(
                                    setting: .fontScale,
                                    value: .number(settings.fontScale)
                                ))
                            }
                        }
                    )
                    .tint(theme.clockColor)
                    .frame(maxWidth: 240)
                    Text("A")
                        .font(.title2)
                        .foregroundStyle(theme.infoColor)
                }
            }

            // レイアウト選択
            VStack(spacing: 8) {
                Text("bedside_layout")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.infoColor)
                let layouts = BedsideClockLogic.ClockLayout.available(isPro: Entitlements.shared.effectiveIsPro)
                HStack(spacing: 8) {
                    ForEach(layouts, id: \.self) { layout in
                        Button {
                            settings.clockLayout = layout.rawValue
                            saveSettings()
                            AnalyticsService.shared.capture(.bedsideSettingChanged(
                                setting: .layout,
                                value: .string(layout.rawValue)
                            ))
                        } label: {
                            layoutPickerLabel(layout: layout)
                        }
                    }
                }
            }

            // 配色（無料3色・Pro6色）
            HStack(spacing: 12) {
                ForEach(BedsideClockLogic.ColorTheme.available(isPro: Entitlements.shared.effectiveIsPro), id: \.self) { t in
                    Button {
                        settings.colorTheme = t.rawValue
                        saveSettings()
                        AnalyticsService.shared.capture(.bedsideSettingChanged(
                            setting: .theme,
                            value: .string(t.rawValue)
                        ))
                    } label: {
                        themePickerLabel(theme: t)
                    }
                }
            }

            // 一時無料開放の案内（#72 Phase2・単一フラグで開閉）
            if Entitlements.isPromotionalUnlockActive {
                Text("promo_unlock_note")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.infoColor.opacity(0.75))
            }

            // 表示要素トグル
            VStack(spacing: 10) {
                toggleRow("bedside_show_countdown", isOn: $settings.showCountdown, analyticsElement: "countdown")
                toggleRow("bedside_show_sound_name", isOn: $settings.showSoundName, analyticsElement: "sound_name")
                toggleRow("bedside_show_date", isOn: $settings.showDate, analyticsElement: "date")
                toggleRow("bedside_show_seconds", isOn: $settings.showSeconds, analyticsElement: "seconds")
            }

            // ナイトモードを終了
            Button {
                exitMethod = .exitButton
                dismiss()
            } label: {
                Text("bedside_exit")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(theme.warningColor.opacity(0.2))
                    )
                    .foregroundStyle(theme.warningColor)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal, 40)
    }

    private func toggleRow(_ key: String, isOn: Binding<Bool>, analyticsElement: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            saveSettings()
            // 計測: 表示要素（秒表示は別設定として扱う）
            if analyticsElement == "seconds" {
                AnalyticsService.shared.capture(.bedsideSettingChanged(
                    setting: .seconds,
                    value: .bool(isOn.wrappedValue)
                ))
            } else {
                AnalyticsService.shared.capture(.bedsideSettingChanged(
                    setting: .elements,
                    value: .string("\(analyticsElement)_\(isOn.wrappedValue ? "on" : "off")")
                ))
            }
        } label: {
            HStack {
                Text(LocalizedStringResource(stringLiteral: key))
                    .font(.body)
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(theme.infoColor)
        }
    }

    private var theme: BedsideClockLogic.ColorTheme {
        BedsideClockLogic.ColorTheme(rawValue: settings.colorTheme) ?? .white
    }

    private var clockLayout: BedsideClockLogic.ClockLayout {
        BedsideClockLogic.ClockLayout(rawValue: settings.clockLayout) ?? .digitalLarge
    }

    // MARK: - Picker Labels（#72 Phase2・Proバッジ + 一時開放表示）

    /// Pro フェイスは Pro バッジ + 一時開放中の旨を併記する
    private func layoutPickerLabel(layout: BedsideClockLogic.ClockLayout) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(layout.displayName)
                    .font(.caption)
                if layout.isPro {
                    ProBadge()
                }
            }
            if layout.isPro && Entitlements.isPromotionalUnlockActive {
                Text("promo_unlock_badge")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.clockColor.opacity(0.9))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(clockLayout == layout ? Color.white.opacity(0.15) : Color.clear)
        )
        .foregroundStyle(theme.infoColor)
    }

    /// Pro カラーも同様にバッジ + 一時開放中の旨を併記する
    private func themePickerLabel(theme: BedsideClockLogic.ColorTheme) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(theme.displayName)
                    .font(.body)
                if theme.isPro {
                    ProBadge()
                }
            }
            if theme.isPro && Entitlements.isPromotionalUnlockActive {
                Text("promo_unlock_badge")
                    .font(.system(size: 8))
                    .foregroundStyle(self.theme.clockColor.opacity(0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(self.theme == theme ? Color.white.opacity(0.15) : Color.clear)
        )
        .foregroundStyle(self.theme.infoColor)
    }

    /// 「Pro」バッジ
    private struct ProBadge: View {
        var body: some View {
            Text("pro_badge")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.2)))
        }
    }

    // MARK: - Tap Handling

    private func handleTap() {
        if showOverlay { return }
        if isIdle {
            isIdle = false
            applyBrightness()
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            showOverlay = true
        }
        resetIdleTimer()
        resetOverlayTimer()
    }

    private func closeOverlay() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showOverlay = false
        }
        overlayTimer?.invalidate()
        resetIdleTimer()
    }

    // MARK: - Mode Lifecycle

    private func enterMode() {
        isPresented = true
        isIdle = false
        showOverlay = false

        AppDelegate.orientationLock = .allButUpsideDown
        forceRotateIfNeeded()

        UIApplication.shared.isIdleTimerDisabled = true
        now = Date()
        offset = BedsideClockLogic.clockOffset(for: now)

        savedBrightness = UIScreen.main.brightness
        applyBrightness()
        resetIdleTimer()

        // 計測: モードに入った（background / exit と同じく Date() を基準に統一）
        let result = BedsideSessionLogic.enter(now: Date())
        sessionState = result.state
        AnalyticsService.shared.capture(.bedsideEntered(
            layout: clockLayout.rawValue,
            theme: settings.colorTheme,
            hour: Calendar.current.component(.hour, from: now)
        ))

        // 初回ヒント
        if !AppGroup.bedsideHintShown {
            showHint = true
            AppGroup.bedsideHintShown = true
            hintTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
                withAnimation(.easeInOut(duration: 0.5)) {
                    showHint = false
                }
            }
        }
    }

    private func exitMode() {
        isPresented = false

        // 計測: モードを抜けた（滞在時間は区分で送る・二重発火しない）
        let result = BedsideSessionLogic.exit(sessionState, now: Date(), method: exitMethod)
        sessionState = result.state
        if case let .exited(duration, method) = result.event {
            captureExit(duration: duration, method: method)
        }

        AppDelegate.orientationLock = .portrait
        forceRotateIfNeeded()

        UIApplication.shared.isIdleTimerDisabled = false
        restoreBrightness()

        idleTimer?.invalidate()
        overlayTimer?.invalidate()
        hintTimer?.invalidate()
    }

    /// bedside_exited の共通送信ヘルパー（滞在時間は区分で送る）
    private func captureExit(duration: TimeInterval, method: BedsideExitMethod) {
        AnalyticsService.shared.capture(.bedsideExited(
            durationBucket: AnalyticsBuckets.durationBucket(seconds: duration),
            exitMethod: method.rawValue
        ))
    }

    // MARK: - Brightness

    private func applyBrightness() {
        if isIdle {
            UIScreen.main.brightness = BedsideClockLogic.idleBrightness(
                originalBrightness: savedBrightness,
                userOffset: settings.brightnessOffset
            )
        } else {
            UIScreen.main.brightness = BedsideClockLogic.dimmedBrightness(
                originalBrightness: savedBrightness,
                userOffset: settings.brightnessOffset
            )
        }
    }

    private func restoreBrightness() {
        UIScreen.main.brightness = savedBrightness
    }

    // MARK: - Timers

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
            isIdle = true
            closeOverlay()
            applyBrightness()
        }
    }

    private func resetOverlayTimer() {
        overlayTimer?.invalidate()
        overlayTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showOverlay = false
            }
        }
    }

    // MARK: - Settings Persistence

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            AppGroup.bedsideSettingsData = data
        }
    }

    private static func loadSettings() -> BedsideClockLogic.BedsideSettings {
        guard let data = AppGroup.bedsideSettingsData,
              let decoded = try? JSONDecoder().decode(BedsideClockLogic.BedsideSettings.self, from: data)
        else { return BedsideClockLogic.BedsideSettings() }
        return decoded
    }

    // MARK: - Rotation

    private func forceRotateIfNeeded() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return }

        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

        if AppDelegate.orientationLock != .portrait {
            if #available(iOS 16.0, *) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
            }
        }
    }
}
