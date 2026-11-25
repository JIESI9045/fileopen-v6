import UIKit

/// 文件「打开方式」两条入口（iOS 13+ 走 UISceneDelegate）：
/// - 冷启动：scene(_:willConnectTo:options:) 的 connectionOptions.urlContexts
/// - 热启动：scene(_:openURLContexts:)
/// 窗口先上屏（绝不留空白），再处理文件。
/// 另外每次进前台都检查「收件箱」，实现"放进去就自动开"。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let root = RootVC()
        let w = UIWindow(windowScene: ws)
        w.rootViewController = root
        w.makeKeyAndVisible()
        window = w
        Router.shared.root = root
        Log.add("窗口已上屏（冷启动）")

        let urls = connectionOptions.urlContexts.map { $0.url }
        if urls.isEmpty {
            Log.add("冷启动没有带文件（正常点图标）")
        } else {
            Log.add("冷启动带来 \(urls.count) 个文件")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                Router.shared.handle(urls)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Router.shared.checkInbox()
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        let urls = URLContexts.map { $0.url }
        Log.add("热启动带来 \(urls.count) 个文件")
        Router.shared.handle(urls)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Log.add("scene 进入前台")
        Router.shared.root?.reload()
        Router.shared.checkInbox()
    }
}
