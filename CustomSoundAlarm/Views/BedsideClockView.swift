import SwiftUI

/// 全画面ベッドサイド時計モード。
///
/// 横向き全画面で時刻・次回アラームを表示し、画面消灯を抑止する。
/// 焼き付き対策として数分ごとに表示位置を微小移動する。
///
/// - 時計面のバリエーションは `Entitlements.isPro` で将来拡張可能。
///   本Issueでは無料の1面（シンプルデジタル）のみ実装。
struct BedsideClockView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var alarmStore = AlarmStore.shared

    @State private var now = Date()
    @State private var offset = CGSize.zero
    @State private var isPresented = false

    /// タイマー（1秒ごとに時刻を更新）
    private let clockTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    /// 焼き付き対策オフセットの更新タイマー（5分ごと）
    private let offsetTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                clockDisplay
                nextAlarmLabel
            }
            .offset(offset)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onReceive(clockTimer) { _ in
            now = Date()
        }
        .onReceive(offsetTimer) { _ in
            offset = BedsideClockLogic.clockOffset(for: now)
        }
        .onAppear { enterMode() }
        .onDisappear { exitMode() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                UIApplication.shared.isIdleTimerDisabled = false
            } else if isPresented {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
        .onTapGesture {
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
            .foregroundStyle(Color.white.opacity(0.85))
            .minimumScaleFactor(0.5)
    }

    // MARK: - Next Alarm

    @ViewBuilder
    private var nextAlarmLabel: some View {
        if let text = BedsideClockLogic.nextAlarmText(
            alarms: alarmStore.alarms,
            currentDate: now
        ) {
            HStack(spacing: 6) {
                Image(systemName: "alarm")
                    .font(.caption)
                Text(text)
                    .font(.caption)
            }
            .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    // MARK: - Mode Lifecycle

    private func enterMode() {
        isPresented = true

        AppDelegate.orientationLock = .allButUpsideDown
        forceRotateIfNeeded()

        UIApplication.shared.isIdleTimerDisabled = true
        now = Date()
        offset = BedsideClockLogic.clockOffset(for: now)
    }

    private func exitMode() {
        isPresented = false

        AppDelegate.orientationLock = .portrait
        forceRotateIfNeeded()

        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// 画面向きの変更を即時反映する（iOS 16+ の新 API）
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
