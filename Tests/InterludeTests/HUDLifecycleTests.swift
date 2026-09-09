import UIKit
import XCTest
@testable import Interlude

/// grace / 最短可见 / 多 Token / 结果 / dismissAll 等核心生命周期。
@MainActor
final class HUDLifecycleTests: InterludeTestCase {
    // MARK: - Grace

    func testLoadingIsPendingDuringGraceAndBlocksTouches() async {
        let token = Interlude.loading("Saving")
        await drain()

        let overlay = globalOverlay
        XCTAssertNotNil(overlay)
        XCTAssertEqual(overlay?.renderedMode, .pending)
        XCTAssertEqual(overlay?.isUserInteractionEnabled, true)
        XCTAssertFalse(Interlude.isShowingHUD)

        await clock.advance(by: 0.15)
        XCTAssertEqual(overlay?.renderedMode, .loading)
        XCTAssertEqual(overlay?.renderedText, "Saving")
        XCTAssertTrue(Interlude.isShowingHUD)
        XCTAssertTrue(token.isActive)
    }

    func testPassthroughDoesNotBlockTouchesDuringGrace() async {
        Interlude.loading(interaction: .passthrough)
        await drain()
        XCTAssertEqual(globalOverlay?.isUserInteractionEnabled, false)
        await clock.advance(by: 0.2)
        XCTAssertEqual(globalOverlay?.isUserInteractionEnabled, false)
    }

    func testDismissBeforeGraceNeverRendersPanel() async {
        let token = Interlude.loading()
        await drain()
        token.dismiss()
        await clock.advance(by: 1)

        XCTAssertEqual(globalOverlay?.renderedMode, .hidden)
        XCTAssertNil(globalOverlay?.superview)
        XCTAssertFalse(token.isActive)
    }

    func testDismissAfterVisibleRespectsMinimumDuration() async {
        let token = Interlude.loading()
        await clock.advance(by: 0.15)
        XCTAssertEqual(globalOverlay?.renderedMode, .loading)

        token.dismiss()
        await clock.advance(by: 0.1)
        XCTAssertEqual(globalOverlay?.renderedMode, .loading, "最短可见时间内不应隐藏")

        await clock.advance(by: 0.3)
        XCTAssertEqual(globalOverlay?.renderedMode, .hidden)
        XCTAssertNil(globalOverlay?.superview)
    }

    // MARK: - Multiple tokens

    func testLatestTokenWinsAndPreviousIsRestored() async {
        let first = Interlude.loading("First")
        await clock.advance(by: 0.2)
        let second = Interlude.progress(0.4, text: "Second")
        await drain()

        XCTAssertEqual(globalOverlay?.renderedMode, .progress(0.4, .ring))
        XCTAssertEqual(globalOverlay?.renderedText, "Second")

        second.dismiss()
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .loading)
        XCTAssertEqual(globalOverlay?.renderedText, "First")

        first.dismiss()
        await clock.advance(by: 1)
        XCTAssertEqual(globalOverlay?.renderedMode, .hidden)
    }

    func testFinishShowsResultOnlyWhenNoOtherTokenIsActive() async {
        let first = Interlude.loading("First")
        let second = Interlude.loading("Second")
        await clock.advance(by: 0.2)

        second.finish(.success("Done"))
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .loading, "仍有活跃 Token 时不展示结果")
        XCTAssertEqual(globalOverlay?.renderedText, "First")

        first.finish(.success("All done"))
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .success)
        XCTAssertEqual(globalOverlay?.renderedText, "All done")

        await clock.advance(by: 1.2)
        await clock.advance(by: 0.5)
        XCTAssertEqual(globalOverlay?.renderedMode, .hidden)
    }

    func testResultPlaysHapticOnce() async {
        let token = Interlude.loading()
        await clock.advance(by: 0.2)
        token.finish(.error("Oops"))
        await drain()
        XCTAssertEqual(haptics.played, [.error])
    }

    func testHapticsCanBeDisabled() async {
        Interlude.configure { $0.hapticsEnabled = false }
        Interlude.show(.success())
        await drain()
        XCTAssertTrue(haptics.played.isEmpty)
    }

    // MARK: - Updates

    func testUpdateProgressSwitchesLoadingToRingAndClamps() async {
        let token = Interlude.loading()
        await clock.advance(by: 0.2)

        token.update(progress: 1.7)
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .progress(1, .ring))
        XCTAssertEqual(globalOverlay?.displayedPercentage, "100%")

        token.update(progress: -3)
        await drain()
        XCTAssertEqual(globalOverlay?.renderedProgress, 0)

        token.update(progress: .nan)
        await drain()
        XCTAssertEqual(globalOverlay?.renderedProgress, 0)
    }

    func testBarStyleIsPreservedAcrossUpdates() async {
        let token = Interlude.progress(0.1, style: .bar, text: "Downloading")
        await clock.advance(by: 0.2)
        token.update(progress: 0.5)
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .progress(0.5, .bar))
    }

    func testUpdateTextAndDetail() async {
        let token = Interlude.loading("A")
        await clock.advance(by: 0.2)
        token.update(text: "B")
        token.update(detail: "1 / 3")
        await drain()
        XCTAssertEqual(globalOverlay?.renderedText, "B")
        XCTAssertEqual(globalOverlay?.renderedDetail, "1 / 3")

        token.update(text: nil)
        await drain()
        XCTAssertNil(globalOverlay?.renderedText)
    }

    func testTokenCallsFromBackgroundThreadAreAppliedOnMain() async {
        let token = Interlude.loading()
        await clock.advance(by: 0.2)

        let expectation = expectation(description: "background update")
        DispatchQueue.global().async {
            token.update(progress: 0.5)
            token.update(text: "Background")
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)
        // 后台派发经 DispatchQueue.main.async 回主线程，等待一轮 run loop。
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(globalOverlay?.renderedMode, .progress(0.5, .ring))
        XCTAssertEqual(globalOverlay?.renderedText, "Background")
    }

    // MARK: - dismissAll

    func testDismissAllInvalidatesExistingTokens() async {
        let token = Interlude.loading()
        await clock.advance(by: 0.2)
        Interlude.dismissAll()
        XCTAssertFalse(token.isActive)
        XCTAssertEqual(globalOverlay?.renderedMode, .hidden)

        token.finish(.success("Late"))
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .hidden, "旧 Token 不得复活 HUD")
        XCTAssertFalse(Interlude.isShowingHUD)
    }

    func testInertTokenWhenWindowIsUnavailable() async {
        Interlude.configure { $0.windowProvider = { nil } }
        let token = Interlude.loading()
        await clock.advance(by: 1)
        XCTAssertFalse(token.isActive)
        XCTAssertNil(globalOverlay)
        token.finish(.success())
        await drain()
        XCTAssertFalse(Interlude.isShowingHUD)
    }

    // MARK: - Text / result HUD

    func testTextHUDSkipsGraceAndAutoDismisses() async {
        Interlude.text("Copied", duration: 1)
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .text)
        XCTAssertEqual(globalOverlay?.isUserInteractionEnabled, false)

        await clock.advance(by: 1)
        await clock.advance(by: 0.5)
        XCTAssertEqual(globalOverlay?.renderedMode, .hidden)
    }

    func testShowResultDirectly() async {
        Interlude.show(.info("Heads up"))
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .info)
        XCTAssertEqual(globalOverlay?.renderedText, "Heads up")
        XCTAssertEqual(haptics.played, [.warning])

        await clock.advance(by: 2)
        XCTAssertEqual(globalOverlay?.renderedMode, .hidden)
    }

    func testImageResultUsesProvidedImage() async {
        let image = UIImage(systemName: "star.fill")!
        Interlude.show(.image(image, "Starred"))
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .image)
        XCTAssertNotNil(globalOverlay?.resultImage)
    }

    // MARK: - Custom view

    func testCustomViewIsEmbedded() async {
        let custom = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        Interlude.custom(custom, text: "Custom")
        await clock.advance(by: 0.2)
        XCTAssertEqual(globalOverlay?.renderedMode, .custom)
        XCTAssertTrue(globalOverlay?.customContentView === custom)
    }
}
