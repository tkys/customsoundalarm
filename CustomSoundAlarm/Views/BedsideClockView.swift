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
                restoreBrightness()
                UIApplication.shared.isIdleTimerDisabled = false
            } else if isPresented {
                UIApplication.shared.isIdleTimerDisabled = true
                applyBrightness()
            }
        }
        .onTapGesture {
            handleTap()
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            dismiss()
        }
    }

    // MARK: - Clock Display

    private var clockDisplay: some View {
        let is24 = BedsideClockLogic.is24HourFormat(for: now)
        let timeStr = BedsideClockLogic.timeString(for: now, is24Hour: is24, showSeconds: settings.showSeconds)
        let layout = clockLayout
        let baseFontSize = BedsideClockLogic.clockFontSize(
            visibleElementCount: settings.visibleElementCount,
            fontScale: settings.fontScale
        )
        let fontSize = baseFontSize * layout.sizeMultiplier

        return Text(timeStr)
            .font(.system(size: fontSize, weight: layout.fontWeight, design: layout.fontDesign))
            .foregroundStyle(theme.clockColor)
            .minimumScaleFactor(0.5)
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
                    Slider(value: Binding(
                        get: { settings.brightnessOffset },
                        set: { newVal in
                            settings.brightnessOffset = newVal
                            saveSettings()
                            applyBrightness()
                        }
                    ), in: 0.2...1.0)
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
                    Slider(value: Binding(
                        get: { settings.fontScale },
                        set: { newVal in
                            settings.fontScale = newVal
                            saveSettings()
                        }
                    ), in: 0.7...1.5)
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
                let layouts = BedsideClockLogic.ClockLayout.available(isPro: Entitlements.shared.isPro)
                HStack(spacing: 8) {
                    ForEach(layouts, id: \.self) { layout in
                        Button {
                            settings.clockLayout = layout.rawValue
                            saveSettings()
                        } label: {
                            Text(layout.displayName)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(clockLayout == layout ?
                                              Color.white.opacity(0.15) : Color.clear)
                                )
                                .foregroundStyle(theme.infoColor)
                        }
                    }
                }
            }

            // 配色
            HStack(spacing: 12) {
                ForEach(BedsideClockLogic.ColorTheme.allCases, id: \.self) { t in
                    Button {
                        settings.colorTheme = t.rawValue
                        saveSettings()
                    } label: {
                        Text(t.displayName)
                            .font(.body)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(theme == t ?
                                          Color.white.opacity(0.15) : Color.clear)
                            )
                            .foregroundStyle(theme.infoColor)
                    }
                }
            }

            // 表示要素トグル
            VStack(spacing: 10) {
                toggleRow("bedside_show_countdown", isOn: $settings.showCountdown)
                toggleRow("bedside_show_sound_name", isOn: $settings.showSoundName)
                toggleRow("bedside_show_date", isOn: $settings.showDate)
                toggleRow("bedside_show_seconds", isOn: $settings.showSeconds)
            }

            // ナイトモードを終了
            Button {
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

    private func toggleRow(_ key: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            saveSettings()
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

        AppDelegate.orientationLock = .portrait
        forceRotateIfNeeded()

        UIApplication.shared.isIdleTimerDisabled = false
        restoreBrightness()

        idleTimer?.invalidate()
        overlayTimer?.invalidate()
        hintTimer?.invalidate()
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
