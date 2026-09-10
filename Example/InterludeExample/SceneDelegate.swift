import Interlude
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    // MARK: - Public Properties

    var window: UIWindow?

    // MARK: - Lifecycle

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: DemoListViewController())
        window.makeKeyAndVisible()
        self.window = window

        // 一次性配置：提供窗口，其余保持默认。
        Interlude.configure { configuration in
            configuration.windowProvider = { [weak window] in window }
        }
        runAutoplayIfRequested()
    }

    // MARK: - Private Methods

    /// 供截图 / UI 自动化使用：`--autoplay <scenario>` 启动后直接演示某个场景。
    private func runAutoplayIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--autoplay"), arguments.indices.contains(index + 1) else { return }
        let scenario = arguments[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch scenario {
            case "loading":
                Interlude.loading("Saving…")
            case "progress":
                Interlude.progress(0.64, text: "Uploading", detail: "64 / 100")
            case "bar":
                Interlude.progress(0.42, style: .bar, text: "Downloading").onCancel {}
            case "success":
                Interlude.show(.success("Saved"))
            case "error":
                Interlude.show(.error("Card declined"))
            case "text":
                Interlude.text("Copied to clipboard", duration: 10)
            case "toast":
                Interlude.toast("Message sent", icon: .success, duration: .persistent)
                Interlude.toast(
                    "The message was removed from this chat.",
                    title: "Message deleted",
                    icon: .system("trash"),
                    action: .init(title: "Undo") {},
                    duration: .persistent
                )
                Interlude.toast("Update available", icon: .info, position: .top, duration: .persistent)
            case "toast-bottom":
                Interlude.toast("Message sent", duration: .persistent)
            case "toast-center":
                Interlude.toast("Centered", position: .center, duration: .persistent)
            case "toast-top":
                Interlude.toast("Saved", icon: .success, position: .top, duration: .persistent)
            default:
                break
            }
        }
    }
}
