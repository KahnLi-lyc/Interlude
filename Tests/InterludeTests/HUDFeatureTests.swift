import UIKit
import XCTest
@testable import Interlude

/// 超时、取消、回调、Progress 绑定、局部宿主与主题。
@MainActor
final class HUDFeatureTests: InterludeTestCase {
    // MARK: - Timeout

    func testTimeoutShowsErrorByDefault() async {
        Interlude.configure { $0.strings.timeout = "Too slow" }
        var timedOut = false
        let token = Interlude.loading(timeout: 2).onTimeout { timedOut = true }
        await clock.advance(by: 0.2)
        await clock.advance(by: 1.8)

        XCTAssertTrue(timedOut)
        XCTAssertFalse(token.isActive)
        XCTAssertEqual(globalOverlay?.renderedMode, .error)
        XCTAssertEqual(globalOverlay?.renderedText, "Too slow")
    }

    func testTimeoutCanDismissSilently() async {
        Interlude.configure {
            $0.timeout = 1
            $0.timeoutBehavior = .dismiss
        }
        let token = Interlude.loading()
        await clock.advance(by: 1)
        await clock.advance(by: 1)
        XCTAssertFalse(token.isActive)
        XCTAssertEqual(globalOverlay?.renderedMode, .hidden)
        XCTAssertTrue(haptics.played.isEmpty)
    }

    func testFinishingBeforeTimeoutCancelsTimer() async {
        let token = Interlude.loading(timeout: 1)
        await clock.advance(by: 0.2)
        token.finish(.success("Ok"))
        await drain()
        await clock.advance(by: 2)
        XCTAssertEqual(haptics.played, [.success], "超时不得再触发错误触感")
    }

    // MARK: - Cancel

    func testCancelButtonForcesBlockingAndInvokesHandler() async {
        var cancelled = false
        let token = Interlude.loading("Uploading", interaction: .passthrough)
            .onCancel(title: "Stop") { cancelled = true }
        await clock.advance(by: 0.2)

        let overlay = globalOverlay
        XCTAssertEqual(overlay?.isCancelButtonVisible, true)
        XCTAssertEqual(overlay?.isUserInteractionEnabled, true, "有取消按钮时必须拦截触摸")

        runtime.hud.performCancel(identifier: token.identifier)
        await drain()
        XCTAssertTrue(cancelled)
        XCTAssertFalse(token.isActive)
    }

    func testDefaultCancelTitleIsLocalized() async {
        Interlude.configure { $0.strings.cancel = "Abort" }
        Interlude.loading().onCancel {}
        await clock.advance(by: 0.2)
        XCTAssertEqual(globalOverlay?.isCancelButtonVisible, true)
    }

    // MARK: - onDismiss

    func testOnDismissFiresOnceAfterHide() async {
        var count = 0
        let token = Interlude.loading().onDismiss { count += 1 }
        await clock.advance(by: 0.2)
        token.dismiss()
        XCTAssertEqual(count, 0, "最短可见期间尚未隐藏")
        await clock.advance(by: 0.5)
        XCTAssertEqual(count, 1)
        token.dismiss()
        await drain()
        XCTAssertEqual(count, 1)
    }

    func testOnDismissFiresImmediatelyWhenOtherTokensRemain() async {
        var dismissed = false
        let first = Interlude.loading()
        let second = Interlude.loading().onDismiss { dismissed = true }
        await clock.advance(by: 0.2)
        second.dismiss()
        await drain()
        XCTAssertTrue(dismissed)
        XCTAssertTrue(first.isActive)
    }

    func testOnDismissFiresOnDismissAll() async {
        var dismissed = false
        Interlude.loading().onDismiss { dismissed = true }
        await clock.advance(by: 0.2)
        Interlude.dismissAll()
        XCTAssertTrue(dismissed)
    }

    // MARK: - Progress observation

    func testObservingFoundationProgress() async {
        let progress = Progress(totalUnitCount: 10)
        let token = Interlude.progress(progress, style: .bar, text: "Download")
        await clock.advance(by: 0.2)
        XCTAssertEqual(globalOverlay?.renderedMode, .progress(0, .bar))

        progress.completedUnitCount = 5
        await drain()
        XCTAssertEqual(globalOverlay?.renderedProgress, 0.5)

        token.dismiss()
        await clock.advance(by: 1)
        progress.completedUnitCount = 10
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .hidden, "Token 结束后观察必须停止")
    }

    // MARK: - Local hosts

    func testLocalHostIsIndependentFromGlobal() async {
        let local = makeLocalHost()
        let localToken = Interlude.loading("Local", on: local)
        Interlude.loading("Global")
        await clock.advance(by: 0.2)

        XCTAssertEqual(overlay(on: local)?.renderedText, "Local")
        XCTAssertEqual(globalOverlay?.renderedText, "Global")
        XCTAssertTrue(overlay(on: local)?.superview === local)

        localToken.dismiss()
        await clock.advance(by: 1)
        XCTAssertNil(overlay(on: local))
        XCTAssertEqual(globalOverlay?.renderedText, "Global")
        XCTAssertEqual(runtime.hud.localHostCountForTesting, 0)
    }

    func testLocalHostReleaseCleansUpState() async {
        var host: UIView? = makeLocalHost()
        let token = Interlude.loading(on: host)
        await clock.advance(by: 0.2)
        XCTAssertEqual(runtime.hud.localHostCountForTesting, 1)

        host?.removeFromSuperview()
        host = nil
        await drain()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(runtime.hud.localHostCountForTesting, 0)
        XCTAssertFalse(token.isActive)
    }

    func testLocalHostPopCleansUpAfterTransition() {
        XCTAssertTrue(HUDView.shouldCleanupLocalHostAfterTransition(
            transitionWasCancelled: false,
            isAttachedToWindow: false
        ))
        XCTAssertFalse(HUDView.shouldCleanupLocalHostAfterTransition(
            transitionWasCancelled: true,
            isAttachedToWindow: false
        ))
        XCTAssertFalse(HUDView.shouldCleanupLocalHostAfterTransition(
            transitionWasCancelled: false,
            isAttachedToWindow: true
        ))
    }

    // MARK: - Theme

    func testGlobalThemeIsApplied() async {
        var theme = Interlude.Theme.light
        theme.cornerRadius = 4
        theme.background = .solid(.red)
        Interlude.theme = theme

        Interlude.loading()
        await clock.advance(by: 0.2)
        XCTAssertEqual(globalOverlay?.panelCornerRadius, 4)
        XCTAssertNil(globalOverlay?.panelEffect)
    }

    func testPerCallThemeOverridesGlobal() async {
        var theme = Interlude.Theme.dark
        theme.cornerRadius = 30
        Interlude.loading(theme: theme)
        await clock.advance(by: 0.2)
        XCTAssertEqual(globalOverlay?.panelCornerRadius, 30)
    }

    func testResultInheritsTokenTheme() async {
        var theme = Interlude.Theme.dark
        theme.cornerRadius = 30
        let token = Interlude.loading(theme: theme)
        await clock.advance(by: 0.2)
        token.finish(.success())
        await drain()
        XCTAssertEqual(globalOverlay?.renderedMode, .success)
        XCTAssertEqual(globalOverlay?.panelCornerRadius, 30)
    }

    // MARK: - Localization

    func testEnglishAndChineseTablesAreBundled() throws {
        let bundle = Localization.resourceBundle
        let english = try XCTUnwrap(Bundle(path: XCTUnwrap(bundle.path(forResource: "en", ofType: "lproj"))))
        let chinese = try XCTUnwrap(Bundle(path: XCTUnwrap(bundle.path(forResource: "zh-Hans", ofType: "lproj"))))
        XCTAssertEqual(english.localizedString(forKey: "interlude.loading", value: nil, table: nil), "Loading")
        XCTAssertEqual(chinese.localizedString(forKey: "interlude.loading", value: nil, table: nil), "加载中")
        XCTAssertFalse(Localization.string(.loading, overrides: Interlude.Strings()).isEmpty)
    }

    func testStringsOverrideBundledLocalization() {
        var strings = Interlude.Strings()
        strings.loading = "Hang on"
        XCTAssertEqual(Localization.string(.loading, overrides: strings), "Hang on")
    }

    func testAllLanguagesContainEveryKey() throws {
        let bundle = Localization.resourceBundle
        let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es", "pt-BR"]
        for language in languages {
            let path = try XCTUnwrap(
                bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
                language
            )
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String], language)
            for key in Localization.Key.allCases {
                XCTAssertNotNil(table[key.rawValue], "\(language) 缺少 \(key.rawValue)")
            }
        }
    }
}
