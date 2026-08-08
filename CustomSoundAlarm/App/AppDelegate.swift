import UIKit

/// アプリ全体の画面向きを制御する AppDelegate。
///
/// このアプリは縦向き固定だが、ベッドサイド時計モードのみ横向きを許可する（#52）。
/// `AppDelegate.orientationLock` で画面ごとに許可する向きを切り替える:
/// - 通常時: `.portrait`
/// - ベッドサイドモード: `.allButUpsideDown`
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// 現在許可する画面向き。ベッドサイドモードの onAppear/onDisappear で切り替える。
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}
