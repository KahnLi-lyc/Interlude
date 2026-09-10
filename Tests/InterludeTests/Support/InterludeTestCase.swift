import UIKit
import XCTest
@testable import Interlude

/// 记录触感调用的测试替身。
@MainActor
final class RecordingHaptics: HapticsPlayer {
    private(set) var played: [UINotificationFeedbackGenerator.FeedbackType] = []

    func play(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        played.append(type)
    }
}

/// 所有用例的基类：注入虚拟时钟、独立窗口，并在结束时重置运行时。
@MainActor
class InterludeTestCase: XCTestCase {
    // MARK: - Public Properties

    var clock: ManualClock!
    var haptics: RecordingHaptics!
    var window: UIWindow!

    var runtime: Runtime {
        Runtime.shared
    }

    // MARK: - Lifecycle

    // 不调用 `super.setUp()`：XCTestCase 的异步版本默认为空实现，而 Swift 6.1 会把该调用
    // 判定为跨隔离发送非 Sendable 的 XCTestCase（6.2 已修复）。
    override func setUp() async throws {
        UIView.setAnimationsEnabled(false)
        clock = ManualClock()
        haptics = RecordingHaptics()
        runtime.resetForTesting(clock: clock, haptics: haptics)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.isHidden = false
        self.window = window

        Interlude.configure { configuration in
            configuration.windowProvider = { [weak window] in window }
        }
    }

    override func tearDown() async throws {
        runtime.resetForTesting()
        window.isHidden = true
        window = nil
        clock = nil
        haptics = nil
        UIView.setAnimationsEnabled(true)
    }

    // MARK: - Helpers

    var globalOverlay: HUDView? {
        runtime.hud.overlay(for: .global)
    }

    func overlay(on view: UIView) -> HUDView? {
        runtime.hud.overlay(for: .view(view))
    }

    func drain() async {
        await ManualClock.drain()
    }

    /// 让本地宿主进入窗口层级，模拟真实页面。
    func makeLocalHost() -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        window.rootViewController?.view.addSubview(view)
        return view
    }
}
