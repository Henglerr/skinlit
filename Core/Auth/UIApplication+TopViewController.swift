import UIKit

extension UIApplication {
    var topViewController: UIViewController? {
        guard
            let scene = connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return nil
        }

        return topViewController(from: root)
    }

    private func topViewController(from root: UIViewController) -> UIViewController {
        if let navigation = root as? UINavigationController, let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }

        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }

        if let presented = root.presentedViewController {
            return topViewController(from: presented)
        }

        return root
    }
}
