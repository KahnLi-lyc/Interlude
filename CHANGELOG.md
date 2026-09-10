# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Removed

- CocoaPods support (`Interlude.podspec`). Interlude is distributed via Swift Package Manager only.

## [1.0.1] - 2026-09-09

### Fixed

- CI/test toolchain compatibility: the test base class no longer calls the async `super.setUp()` /
  `super.tearDown()`, which Swift 6.1 (Xcode 16.4) rejected as sending a non-Sendable `XCTestCase`.
  CI now pins SwiftFormat 0.58.7 / SwiftLint 0.63.2 and resolves the simulator from
  `xcodebuild -showdestinations` with retries. No library code changed.

## [1.0.0] - 2026-09-09

### Added

- Token-driven HUD coordinator: grace time, minimum visible duration, latest-wins stacking per host,
  result shown only when idle, `dismissAll()` session invalidation.
- HUD modes: indeterminate loading, ring and bar progress, text-only, custom view, and
  success / error / info / image results with haptics.
- `Token.observe(_ progress: Progress)` KVO binding, `onCancel`, `onDismiss`, `onTimeout`,
  per-task `timeout` with `dismiss` or `error` behaviour.
- Toast system with `stack` / `queue` / `replace` policies, `top` / `center` / `bottom` / `point`
  positions, icons, title + action button, custom views, tap / swipe dismissal, persistent toasts
  with `Handle`, keyboard avoidance and completion callbacks.
- Local hosts for both HUDs and toasts with automatic cleanup on view release or view controller
  pop / dismiss; toast layer is always kept above the HUD overlay.
- `Interlude.run` async helpers with success / failure mapping, cancellation and a `Progress` variant.
- SwiftUI modifiers: `interludeLoading`, `interludeProgress`, `interludeToast`, `interludeHost`.
- Theme system with `automatic`, `dark`, `light` presets, blur or solid backgrounds, fade / zoom
  animations, Reduce Motion and Reduce Transparency support.
- Localized strings for en, zh-Hans, zh-Hant, ja, ko, fr, de, es, pt-BR with per-app overrides.
- 56 unit tests driven by an injectable clock; XcodeGen example app covering every public API.
