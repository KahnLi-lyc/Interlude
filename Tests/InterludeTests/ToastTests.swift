import UIKit
import XCTest
@testable import Interlude

/// Toast 展示、策略、句柄、完成回调、局部宿主与层级。
@MainActor
final class ToastTests: InterludeTestCase {
    // MARK: - Helpers

    private var visibleGlobalToasts: [ToastView] {
        runtime.toasts.visibleViews(for: .global)
    }

    // MARK: - Basics

    func testToastAppearsAndAutoDismisses() async {
        var completed: Bool?
        Interlude.toast("Saved", duration: .seconds(1)) { completed = $0 }
        await drain()
        XCTAssertEqual(visibleGlobalToasts.count, 1)
        XCTAssertEqual(visibleGlobalToasts.first?.toast.message, "Saved")

        await clock.advance(by: 1)
        XCTAssertTrue(visibleGlobalToasts.isEmpty)
        XCTAssertEqual(completed, false)
        XCTAssertNil(runtime.toasts.layerView(for: .global), "没有 Toast 时图层应被移除")
    }

    func testPersistentToastStaysUntilHandleDismiss() async {
        let handle = Interlude.toast("Offline", duration: .persistent)
        await clock.advance(by: 100)
        XCTAssertTrue(handle.isVisible)

        handle.dismiss()
        await drain()
        XCTAssertFalse(handle.isVisible)
        XCTAssertTrue(visibleGlobalToasts.isEmpty)
    }

    func testEmptyToastReturnsInertHandle() async {
        let handle = Interlude.toast("   ")
        await drain()
        XCTAssertFalse(handle.isVisible)
        XCTAssertTrue(visibleGlobalToasts.isEmpty)
    }

    func testTapReportsDidTap() async {
        var didTap: Bool?
        let handle = Interlude.toast("Tap me", duration: .persistent) { didTap = $0 }
        await drain()
        runtime.toasts.performDismiss(identifier: handle.identifier, didTap: true)
        await drain()
        XCTAssertEqual(didTap, true)
    }

    func testActionButtonRunsHandlerAndDismisses() async {
        var actionRan = false
        var didTap: Bool?
        Interlude.toast(
            "Message deleted",
            title: nil,
            action: .init(title: "Undo") { actionRan = true },
            duration: .persistent
        ) { didTap = $0 }
        await drain()

        let view = visibleGlobalToasts.first
        XCTAssertEqual(view?.isActionButtonVisible, true)
        view?.actionHandler?()
        await drain()
        XCTAssertTrue(actionRan)
        XCTAssertEqual(didTap, true)
        XCTAssertTrue(visibleGlobalToasts.isEmpty)
    }

    // MARK: - Policies

    func testStackPolicyEvictsOldestBeyondMaximum() async {
        Interlude.configure { $0.toast.policy = .stack(maximum: 2) }
        Interlude.toast("1", duration: .persistent)
        Interlude.toast("2", duration: .persistent)
        Interlude.toast("3", duration: .persistent)
        await drain()
        XCTAssertEqual(visibleGlobalToasts.map(\.toast.message), ["2", "3"])
    }

    func testQueuePolicyShowsOneAtATime() async {
        Interlude.configure { $0.toast.policy = .queue }
        Interlude.toast("1", duration: .seconds(1))
        Interlude.toast("2", duration: .seconds(1))
        await drain()
        XCTAssertEqual(visibleGlobalToasts.map(\.toast.message), ["1"])
        XCTAssertEqual(runtime.toasts.queuedCount(for: .global), 1)

        await clock.advance(by: 1)
        XCTAssertEqual(visibleGlobalToasts.map(\.toast.message), ["2"])
        XCTAssertEqual(runtime.toasts.queuedCount(for: .global), 0)

        await clock.advance(by: 1)
        XCTAssertTrue(visibleGlobalToasts.isEmpty)
    }

    func testReplacePolicyKeepsOnlyNewest() async {
        Interlude.configure { $0.toast.policy = .replace }
        Interlude.toast("1", duration: .persistent)
        Interlude.toast("2", duration: .persistent)
        await drain()
        XCTAssertEqual(visibleGlobalToasts.map(\.toast.message), ["2"])
    }

    func testPositionsAreIndependentGroups() async {
        Interlude.configure { $0.toast.policy = .queue }
        Interlude.toast("Top", position: .top, duration: .persistent)
        Interlude.toast("Bottom", position: .bottom, duration: .persistent)
        await drain()
        XCTAssertEqual(runtime.toasts.visibleViews(for: .global, position: .top).count, 1)
        XCTAssertEqual(runtime.toasts.visibleViews(for: .global, position: .bottom).count, 1)
    }

    // MARK: - dismissAll

    func testDismissAllToastsClearsQueueToo() async {
        Interlude.configure { $0.toast.policy = .queue }
        var completions = 0
        Interlude.toast("1", duration: .persistent) { _ in completions += 1 }
        Interlude.toast("2", duration: .persistent) { _ in completions += 1 }
        await drain()

        Interlude.dismissAllToasts()
        await drain()
        XCTAssertTrue(visibleGlobalToasts.isEmpty)
        XCTAssertEqual(runtime.toasts.queuedCount(for: .global), 0)
        XCTAssertEqual(completions, 1, "被清空的排队项不触发完成回调；可见项触发一次")
    }

    // MARK: - Hosts

    func testLocalHostToastAttachesToView() async {
        let local = makeLocalHost()
        Interlude.toast("Local", duration: .persistent, on: local)
        await drain()
        XCTAssertEqual(runtime.toasts.visibleViews(for: .view(local)).count, 1)
        XCTAssertTrue(runtime.toasts.layerView(for: .view(local))?.superview === local)
        XCTAssertTrue(visibleGlobalToasts.isEmpty)
    }

    func testToastLayerStaysAboveHUDOverlay() async {
        Interlude.toast("Above", duration: .persistent)
        Interlude.loading()
        await clock.advance(by: 0.2)

        let subviews = window.subviews
        let hudIndex = subviews.firstIndex { $0 is HUDView }
        let toastIndex = subviews.firstIndex { $0 is PassthroughLayerView }
        XCTAssertNotNil(hudIndex)
        XCTAssertNotNil(toastIndex)
        XCTAssertGreaterThan(toastIndex ?? -1, hudIndex ?? -1)
    }

    func testCustomToastView() async {
        let custom = UILabel()
        custom.text = "Custom"
        Interlude.toast(.custom(custom, duration: .persistent))
        await drain()
        XCTAssertEqual(visibleGlobalToasts.count, 1)
        XCTAssertTrue(custom.isDescendant(of: visibleGlobalToasts[0]))
    }

    // MARK: - Model

    func testDurationValues() {
        XCTAssertEqual(Interlude.Toast.Duration.short.timeInterval, 2)
        XCTAssertEqual(Interlude.Toast.Duration.long.timeInterval, 3.5)
        XCTAssertEqual(Interlude.Toast.Duration.seconds(-1).timeInterval, 0)
        XCTAssertNil(Interlude.Toast.Duration.persistent.timeInterval)
    }

    // MARK: - Animation

    func test_toast_animation_automaticResolvesByPosition() {
        let frame = CGRect(x: 80, y: 400, width: 200, height: 40)
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)

        let bottom = ToastTransition.resolve(
            animation: .automatic,
            position: .bottom,
            viewFrame: frame,
            layerBounds: bounds
        )
        XCTAssertEqual(bottom.appearing.tx, 0)
        XCTAssertGreaterThan(bottom.appearing.ty, 0)
        XCTAssertEqual(bottom.appearing.a, 1, accuracy: 0.001)
        XCTAssertEqual(bottom.appearing.d, 1, accuracy: 0.001)

        let top = ToastTransition.resolve(
            animation: .automatic,
            position: .top,
            viewFrame: frame,
            layerBounds: bounds
        )
        XCTAssertEqual(top.appearing.tx, 0)
        XCTAssertLessThan(top.appearing.ty, 0)

        let center = ToastTransition.resolve(
            animation: .automatic,
            position: .center,
            viewFrame: frame,
            layerBounds: bounds
        )
        XCTAssertEqual(center.appearing.a, center.appearing.d, accuracy: 0.001)
        XCTAssertLessThan(center.appearing.a, 1)
        XCTAssertEqual(center.appearing.tx, 0)
        XCTAssertEqual(center.appearing.ty, 0)
    }

    func test_toast_animation_slideOffsetLeavesLayerBounds() {
        let viewFrame = CGRect(x: 40, y: 700, width: 200, height: 44)
        let layerBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let transition = ToastTransition.resolve(
            animation: .slide,
            position: .bottom,
            viewFrame: viewFrame,
            layerBounds: layerBounds
        )
        let moved = viewFrame.offsetBy(dx: transition.appearing.tx, dy: transition.appearing.ty)
        XCTAssertGreaterThanOrEqual(moved.minY, layerBounds.maxY)
    }

    func test_toast_animation_reduceMotion_immediate() async {
        Interlude.toast(
            "Instant",
            duration: .persistent,
            animation: Interlude.Toast.Animation.none
        )
        await drain()
        window.layoutIfNeeded()
        runtime.toasts.layerView(for: .global)?.layoutIfNeeded()

        guard let view = visibleGlobalToasts.first else {
            return XCTFail("Expected a visible toast")
        }
        XCTAssertEqual(view.alpha, 1)
        XCTAssertEqual(view.transform, .identity)
        XCTAssertFalse(view.isHidden)
        XCTAssertNotEqual(view.frame.size, .zero)
        XCTAssertEqual(view.resolvedAnimation, Interlude.Toast.Animation.none)

        guard let layer = runtime.toasts.layerView(for: .global) else {
            return XCTFail("Expected a toast layer")
        }
        let frameInLayer = view.convert(view.bounds, to: layer)
        XCTAssertGreaterThan(
            frameInLayer.minY,
            400,
            "bottom toast should sit in the lower half, not at the overlay origin"
        )
    }

    func test_toast_animation_perToastOverridesTheme() async {
        var theme = Interlude.theme
        theme.toast.animation = .fade
        Interlude.theme = theme

        Interlude.toast("Zoom", duration: .persistent, animation: .zoom)
        await drain()
        XCTAssertEqual(visibleGlobalToasts.first?.resolvedAnimation, .zoom)
    }
}
