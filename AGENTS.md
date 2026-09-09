# Interlude 开发规范

本文件对参与本仓库的人与 AI 代理同等生效。任何代码改动都必须满足本文；与 `DESIGN.md` 冲突时，先更新文档再改代码。

---

## 1. 项目事实

- 仓库：<https://github.com/KahnLi-lyc/Interlude>，SwiftPM 单 Target 库 `Interlude`。
- 平台：iOS 15.0+，`swift-tools-version: 6.0`，Swift 6 language mode。
- 渲染层：UIKit。SwiftUI 只做适配（ViewModifier + `UIViewRepresentable`），不复制状态机与渲染逻辑。
- 依赖：零第三方依赖。布局使用原生 Auto Layout（`NSLayoutConstraint.activate`），不引入 SnapKit 等。
- 资源：通过 `Bundle.module` 读取；本地化位于 `Sources/Interlude/Resources/*.lproj/Localizable.strings`。
- 实现规格与验收标准：`DESIGN.md`。实现前先读对应章节，实现后对照「验收标准」补测试。

---

## 2. 并发规则

1. 所有 UIKit 类型、Coordinator、Presenter 标 `@MainActor`。
2. 允许从任意线程调用的入口（Token / Handle 的更新与结束、`dismissAll`）声明为 `nonisolated`，只携带 `Sendable` 值，内部通过 `MainActorDispatch.runOnMainActorNowOrAsync` 切回主线程。
3. 编译选项 `-strict-concurrency=complete`，零警告。
4. 禁止：
   - `@unchecked Sendable`
   - `nonisolated(unsafe)`
   - `DispatchQueue.main.sync`
   - 在 `MainActorDispatch.swift` 之外使用 `Thread.isMainThread` 或 `MainActor.assumeIsolated`
   - 用锁包装 UIKit 对象
5. 计时统一走 `Clock` 协议（`now` + `sleep`），不直接调用 `Task.sleep` 或 `DispatchQueue.asyncAfter`，以便测试注入 `ManualClock`。
6. 每个异步 Task 必须可取消，并用「生命周期代次」校验回调是否过期，避免旧回调操作新状态。

---

## 3. 视图代码规则

1. 子视图统一用 `private lazy var`，在闭包内完成全部静态样式配置：

   ```swift
   private lazy var titleLabel: UILabel = {
       let label = UILabel()
       label.font = theme.textFont
       label.adjustsFontForContentSizeCategory = true
       label.textAlignment = .center
       label.numberOfLines = 0
       label.isAccessibilityElement = false
       return label
   }()
   ```

2. 视图层级与约束在 `setupViews()` / `setupConstraints()` 中建立，只建立一次；随主题变化的属性放在 `applyTheme(_:)`。
3. `required init?(coder:)` 标 `@available(*, unavailable)` 并 `fatalError`。
4. 装饰性子视图 `isAccessibilityElement = false`；容器提供单一无障碍语义。
5. 不硬编码颜色、字体、圆角、间距；全部来自 `Interlude.Theme`。
6. 动画前检查 `UIAccessibility.isReduceMotionEnabled`；材质前检查 `UIAccessibility.isReduceTransparencyEnabled`。

---

## 4. 文件结构与 MARK 分组

每个文件一个主类型（可附带私有辅助类型）。类型内按以下顺序分组，缺项可省略，**不可乱序**：

```swift
// MARK: - Public Properties
// MARK: - Private Properties
// MARK: - Views
// MARK: - Initialization
// MARK: - Lifecycle
// MARK: - Public Methods
// MARK: - View Setup
// MARK: - Actions
// MARK: - Private Methods
```

- 协议实现放在类型外的 `extension`，以 `// MARK: - <协议名>` 分组。
- 嵌套类型（`enum RenderedMode` 等）放在文件顶部主类型之前，或在类型内最前面用 `// MARK: - Types` 分组。
- 文件头不写作者、日期等信息，只保留必要的 `import`。
- 目录：`Sources/Interlude/{Interlude.swift, Core, HUD, Toast, Async, SwiftUI, Resources}`。

---

## 5. 命名

1. 遵循 [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)：类型用名词，方法用动词短语，`Bool` 用 `is / has / should / can` 前缀。
2. 公开类型全部嵌套在 `Interlude` 命名空间下（`Interlude.Token`、`Interlude.Theme`），不加 `HUD`、`Overlay`、`Interlude` 等冗余前缀。
3. 内部类型（`HUDCoordinator`、`HUDView`、`ToastPresenter`）不公开，不加前缀。
4. 参数标签让调用读起来像句子：`Interlude.loading("Saving…", on: view)`、`token.finish(.success("Saved"))`。
5. 变量名对应具体职责，不复用通用名（`presentationTask` 而非 `task1`）。
6. 常量集中在类型内 `private enum Constants` 或主题中，不散落魔法数字。

---

## 6. 注释

1. 公开 API 使用英文 DocC（`///`），包含一句摘要，必要时 `- Parameters:` / `- Returns:` / `- Note:`。
2. 内部实现注释使用中文，解释「为什么这样做」而不是复述代码。
3. 不保留被注释掉的代码；不写 TODO 而不关联 Issue。

---

## 7. 测试

1. 目标 `InterludeTests`，XCTest，运行于 iOS Simulator。
2. 每条 `DESIGN.md` 验收标准（`AC-xx-n`）对应至少一个测试，测试名沿用 §7 测试矩阵：`test_<行为>_<条件>_<预期>`。
3. 不真实 sleep；通过 `Interlude.resetForTesting(clock:)` 注入 `ManualClock` 并 `advance(by:)`。
4. 测试用 `@MainActor final class XxxTests: XCTestCase`；`setUp` / `tearDown` 中调用 `Interlude.resetForTesting()`。
5. 需要窗口时使用测试内创建的 `UIWindow`，不依赖 App 主窗口。

---

## 8. 提交与工具

1. Conventional Commits：`feat:` / `fix:` / `docs:` / `test:` / `refactor:` / `chore:`，一个阶段一个可独立回滚的提交。
2. 提交前本地通过：`swift build`、`xcodebuild test`（Simulator）、`swiftformat --lint .`、`swiftlint`。
3. 不提交 `.DS_Store`、`xcuserdata`、`.build`、`DerivedData`。
4. 新增公开 API 必须同步更新：`DESIGN.md` 对应章节、README 用法、CHANGELOG `Unreleased`。
5. 新增语言必须补齐全部 `Localizable.strings` 键，并让 `test_localization_allLprojKeysMatch` 通过。

---

## 9. 禁止事项速查

- 不写 `@discardableResult` 的 HUD 展示方法（Token 必须被持有）；`text` / `show` / `toast` 例外。
- 不提供「关闭最近一个 HUD」的模糊接口。
- 不在 Token 上实现 `deinit` 自动关闭。
- 不在库内使用 `UIApplication.shared.keyWindow` 猜窗口；窗口只来自 `Configuration.windowProvider`。
- 不在 SwiftUI 适配层重新实现渲染。
- 不引入第三方依赖。
