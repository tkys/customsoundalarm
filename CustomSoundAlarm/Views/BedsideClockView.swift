import SwiftUI

/// 全画面ベッドサイド時計モード。
///
/// 横向き全画面で時刻・カウントダウン・次回アラーム（音名付き）を表示し、
/// 画面消灯を抑止する。焼き付き対策・輝度制御・夜間配色・調整オーバーレイを搭載。
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

    // 輝度制御
    @State private var savedBrightness: CGFloat = 0.5
    @State private var idleTimer: Timer?
    @State private var overlayTimer: Timer?

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

            if showOverlay {
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
        let fontSize = BedsideClockLogic.clockFontSize(visibleElementCount: settings.visibleElementCount)

        return Text(timeStr)
            .font(.system(size: fontSize, weight: .light, design: .default))
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

    // MARK: - Tap Handling

    private func handleTap() {
        if isIdle {
            isIdle = false
            applyBrightness()
        }
        showOverlay = true
        resetIdleTimer()
        resetOverlayTimer()
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
    }

    private func exitMode() {
        isPresented = false

        AppDelegate.orientationLock = .portrait
        forceRotateIfNeeded()

        UIApplication.shared.isIdleTimerDisabled = false
        restoreBrightness()

        idleTimer?.invalidate()
        overlayTimer?.invalidate()
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
            showOverlay = false
            applyBrightness()
        }
    }

    private func resetOverlayTimer() {
        overlayTimer?.invalidate()
        overlayTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
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