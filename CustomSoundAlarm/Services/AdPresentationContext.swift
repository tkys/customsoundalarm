import UIKit

/// 広告を表示するための最前面の ViewController を解決する（#147）。
@MainActor
enum AdPresentationContext {
    /// ウィンドウのルート ViewController。
    /// シートの閉じるアニメーション中でも広告がシートごと消えないように、
    /// 全画面広告はこの VC から出す。
    static func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return (activeScene?.windows.first(where: \.isKeyWindow)
            ?? activeScene?.windows.first)?.rootViewController
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = activeScene?.windows.first(where: \.isKeyWindow)
            ?? activeScene?.windows.first else {
            return nil
        }
        return top(from: window.rootViewController)
    }

    private static func top(from viewController: UIViewController?) -> UIViewController? {
        guard let viewController else { return nil }
        if let navigation = viewController as? UINavigationController {
            return top(from: navigation.visibleViewController)
        }
        if let tab = viewController as? UITabBarController {
            return top(from: tab.selectedViewController)
        }
        if let presented = viewController.presentedViewController {
            return top(from: presented)
        }
        return viewController
    }
}
