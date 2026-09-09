import UIKit

/// 库的 MainActor 运行时：持有配置、主题、时钟、触感与两个子系统。
///
/// 所有公开静态入口都转发到 `Runtime.shared`，测试通过 `resetForTesting` 替换时钟并清空状态。
@MainActor
final class Runtime {
    // MARK: - Public Properties

    static let shared = Runtime()

    var configuration = Interlude.Configuration()
    var theme: Interlude.Theme = .automatic
    private(set) var clock: any InterludeClock
    private(set) var haptics: any HapticsPlayer

    private(set) lazy var hud = HUDCoordinator(runtime: self)
    private(set) lazy var toasts = ToastPresenter(runtime: self)

    // MARK: - Initialization

    private init() {
        clock = SystemClock()
        haptics = SystemHapticsPlayer()
    }

    // MARK: - Public Methods

    /// 返回当前全局窗口；未配置 `windowProvider` 时在 Debug 下断言。
    func resolveGlobalWindow() -> UIWindow? {
        guard let provider = configuration.windowProvider else {
            assertionFailure("Interlude: call Interlude.configure { $0.windowProvider = … } before presenting global HUDs or toasts.")
            return nil
        }
        return provider()
    }

    /// 在开启触感时播放结果反馈。
    func playHaptic(for result: Interlude.Result) {
        guard configuration.hapticsEnabled, let type = result.hapticType else { return }
        haptics.play(type)
    }

    /// 读取本地化文案（含用户覆盖）。
    func string(_ key: Localization.Key) -> String {
        Localization.string(key, overrides: configuration.strings)
    }

    /// 清空全部状态并恢复默认配置。仅供测试。
    func resetForTesting(clock: (any InterludeClock)? = nil, haptics: (any HapticsPlayer)? = nil) {
        hud.performDismissAll()
        toasts.performDismissAll()
        configuration = Interlude.Configuration()
        theme = .automatic
        self.clock = clock ?? SystemClock()
        self.haptics = haptics ?? SystemHapticsPlayer()
        hud.resetForTesting()
        toasts.resetForTesting()
    }
}
