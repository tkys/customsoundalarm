import SwiftUI

/// 全画面ベッドサイド時計モード。
///
/// 横向き全画面で時刻・カウントダウン・次回アラーム（音名付き）を表示し、
/// 画面消灯を抑止する。焼き付き対策・輝度制御・夜間配色を搭載。
struct BedsideClockView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var alarmStore = AlarmStore.shared
    @State private var soundStore = SoundStore.shared

    @State private var now = Date()
    @State private var offset = CGSize.zero
    @State private var isPresented = false
    @State private var colorTheme: BedsideClockLogic.ColorTheme = BedsideClockLogic.ColorTheme(rawValue: AppGroup.bedsideColorThemeRaw) ?? .white
    @State private var isIdle = false

    // 輝度制御
    @State private var savedBrightness: CGFloat = 0.5
    @State private var idleTimer: Timer?

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

                themeSwitcher
            }
            .offset(offset)
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
        // タップで操作（輝度戻す + dismiss は長押し）
        .onTapGesture {
            if isIdle {
                isIdle = false
                applyBrightness()
                resetIdleTimer()
            }
        }
        .onLongPressGesture(minimumDuration: 0.6) {
            dismiss()
        }
    }

    // MARK: - Clock Display

    private var clockDisplay: some View {
        let is24 = BedsideClockLogic.is24HourFormat(for: now)
        let formatter = DateFormatter()
        formatter.dateFormat = is24 ? "HH:mm" : "h:mm"

        return Text(formatter.string(from: now))
            .font(.system(size: 96, weight: .light, design: .default))
            .foregroundStyle(colorTheme.clockColor)
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
                // 時刻 + カウントダウン
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
                .foregroundStyle(colorTheme.infoColor)

                // 音名
                if let alarm = nextEnabledAlarm(),
                   !alarm.soundFileName.isEmpty {
                    let soundName = soundStore.displayName(for: alarm.soundFileName)
                    Text(soundName)
                        .font(.caption2)
                        .foregroundStyle(colorTheme.infoColor)
                }
            }
        } else {
            // アラーム未設定の警告
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                Text("bedside_no_alarm")
                    .font(.caption)
            }
            .foregroundStyle(colorTheme.warningColor)
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

    // MARK: - Theme Switcher

    private var themeSwitcher: some View {
        HStack(spacing: 12) {
            ForEach(BedsideClockLogic.ColorTheme.allCases, id: \.self) { theme in
                Button {
                    colorTheme = theme
                    AppGroup.bedsideColorThemeRaw = theme.rawValue
                } label: {
                    Text(theme.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(colorTheme == theme ?
                                      Color.white.opacity(0.15) : Color.clear)
                        )
                        .foregroundStyle(colorTheme.infoColor)
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Mode Lifecycle

    private func enterMode() {
        isPresented = true
        isIdle = false

        AppDelegate.orientationLock = .allButUpsideDown
        forceRotateIfNeeded()

        UIApplication.shared.isIdleTimerDisabled = true
        now = Date()
        offset = BedsideClockLogic.clockOffset(for: now)

        // 輝度を保存して減光
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
    }

    // MARK: - Brightness

    private func applyBrightness() {
        if isIdle {
            UIScreen.main.brightness = BedsideClockLogic.idleBrightness(
                originalBrightness: savedBrightness
            )
        } else {
            UIScreen.main.brightness = BedsideClockLogic.dimmedBrightness(
                originalBrightness: savedBrightness
            )
        }
    }

    private func restoreBrightness() {
        UIScreen.main.brightness = savedBrightness
    }

    // MARK: - Idle Timer

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
            isIdle = true
            applyBrightness()
        }
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
