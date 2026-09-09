import Foundation

/// 库内唯一允许判断主线程并 `assumeIsolated` 的地方。
///
/// Token / Handle 的 `nonisolated` 入口都经此切回 MainActor：主线程上同步执行，
/// 保证 `deinit` 或同步回调中调用能立即生效；其它线程异步派发，避免死锁。
enum MainActorDispatch {
    // MARK: - Public Methods

    /// 主线程立即执行，非主线程异步切回主线程执行。
    /// - Parameter block: 需要在 MainActor 上执行的工作。
    nonisolated static func runOnMainActorNowOrAsync(_ block: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                block()
            }
            return
        }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                block()
            }
        }
    }
}
