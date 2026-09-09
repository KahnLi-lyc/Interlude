import UIKit
import XCTest
@testable import Interlude

/// `Interlude.run` 的成功、失败、取消与进度绑定。
@MainActor
final class AsyncTests: InterludeTestCase {
    private struct SampleError: LocalizedError {
        var errorDescription: String? { "Network unreachable" }
    }

    func testRunShowsSuccessResult() async throws {
        let value = try await Interlude.run("Saving", success: "Saved") {
            await Task.yield()
            return 42
        }
        XCTAssertEqual(value, 42)
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .success)
        XCTAssertEqual(globalOverlay?.renderedText, "Saved")
    }

    func testRunDismissesSilentlyWithoutSuccessText() async throws {
        try await Interlude.run("Saving") {
            await Task.yield()
        }
        await clock.advance(by: 1)
        XCTAssertNotEqual(globalOverlay?.renderedMode, .success)
        XCTAssertFalse(Interlude.isShowingHUD)
    }

    func testRunShowsMappedError() async {
        do {
            try await Interlude.run("Loading") {
                throw SampleError()
            }
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(error is SampleError)
        }
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .error)
        XCTAssertEqual(globalOverlay?.renderedText, "Network unreachable")
    }

    func testRunFailureMappingToNilDismissesSilently() async {
        _ = try? await Interlude.run("Loading", failure: { _ in nil }) {
            throw SampleError()
        }
        await clock.advance(by: 1)
        XCTAssertFalse(Interlude.isShowingHUD)
        XCTAssertTrue(haptics.played.isEmpty)
    }

    func testRunCancellationDismissesWithoutResult() async {
        let task = Task { @MainActor in
            try await Interlude.run("Cancelling", cancellable: true) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        await drain()
        task.cancel()
        let result = await task.result
        XCTAssertTrue((try? result.get()) == nil)
        if case .failure(let error) = result {
            XCTAssertTrue(error is CancellationError)
        }
        await clock.advance(by: 1)
        XCTAssertFalse(Interlude.isShowingHUD)
        XCTAssertTrue(haptics.played.isEmpty)
    }

    func testRunWithProgressMirrorsUnits() async throws {
        try await Interlude.run("Uploading", style: .bar, totalUnitCount: 4, success: "Uploaded") { progress in
            await self.clock.advance(by: 0.2)
            progress.completedUnitCount = 2
            await self.drain()
            XCTAssertEqual(self.globalOverlay?.renderedMode, .progress(0.5, .bar))
            progress.completedUnitCount = 4
        }
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .success)
    }
}
