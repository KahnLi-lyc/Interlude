import Foundation

/// 统一的时间源。所有 grace / 最短可见 / 结果 / 超时 / Toast 时长都经此计时，
/// 测试可注入虚拟时钟推进时间而无需真实等待。
@MainActor
protocol InterludeClock: AnyObject {
    /// 单调递增的当前时间（秒）。
    var now: TimeInterval { get }

    /// 挂起指定秒数；被取消时抛出 `CancellationError`。
    func sleep(for duration: TimeInterval) async throws
}

/// 基于 `ProcessInfo.systemUptime` 与 `Task.sleep` 的系统时钟。
@MainActor
final class SystemClock: InterludeClock {
    // MARK: - Public Properties

    var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: Self.nanoseconds(for: duration))
    }

    // MARK: - Private Methods

    /// 把秒转换为纳秒并避免 `UInt64` 溢出。
    private static func nanoseconds(for duration: TimeInterval) -> UInt64 {
        let maximumSeconds = TimeInterval(UInt64.max) / 1_000_000_000
        let clamped = min(max(0, duration), maximumSeconds)
        return UInt64(clamped * 1_000_000_000)
    }
}

extension TimeInterval {
    /// 把外部传入的时长规范为有限且不小于零的值。
    var normalizedDuration: TimeInterval {
        isFinite ? Swift.max(0, self) : 0
    }
}
