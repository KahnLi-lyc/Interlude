import Foundation
@testable import Interlude

/// 手动推进的虚拟时钟：`sleep` 登记唤醒时刻，`advance` 按序唤醒到期任务。
@MainActor
final class ManualClock: InterludeClock {
    // MARK: - Types

    private struct Sleeper {
        let deadline: TimeInterval
        let order: Int
        let continuation: CheckedContinuation<Void, any Error>
    }

    // MARK: - Public Properties

    private(set) var now: TimeInterval = 0

    var pendingSleeperCount: Int {
        sleepers.count
    }

    // MARK: - Private Properties

    private var sleepers: [Sleeper] = []
    private var order = 0

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    func sleep(for duration: TimeInterval) async throws {
        let deadline = now + max(0, duration)
        order += 1
        let order = order
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sleepers.append(Sleeper(deadline: deadline, order: order, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelSleeper(order: order)
            }
        }
    }

    /// 推进时间并唤醒所有到期的睡眠者，随后让出执行权让任务体运行。
    func advance(by delta: TimeInterval) async {
        // 先让刚创建的任务跑到 sleep 登记点，否则会漏掉它们。
        await Self.drain()
        let target = now + delta
        while let next = sleepers.filter({ $0.deadline <= target }).min(by: { ($0.deadline, $0.order) < (
            $1.deadline,
            $1.order
        ) }) {
            now = max(now, next.deadline)
            sleepers.removeAll { $0.order == next.order }
            next.continuation.resume()
            await Self.drain()
        }
        now = target
        await Self.drain()
    }

    /// 让当前已就绪的主线程任务全部执行完。
    static func drain(iterations: Int = 20) async {
        for _ in 0 ..< iterations {
            await Task.yield()
        }
    }

    // MARK: - Private Methods

    private func cancelSleeper(order: Int) {
        guard let index = sleepers.firstIndex(where: { $0.order == order }) else { return }
        let sleeper = sleepers.remove(at: index)
        sleeper.continuation.resume(throwing: CancellationError())
    }
}
