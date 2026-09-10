# Interlude

[![CI](https://github.com/KahnLi-lyc/Interlude/actions/workflows/ci.yml/badge.svg)](https://github.com/KahnLi-lyc/Interlude/actions/workflows/ci.yml)
![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)
![iOS 15+](https://img.shields.io/badge/iOS-15%2B-blue.svg)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)
![License MIT](https://img.shields.io/badge/License-MIT-lightgrey.svg)

**Interlude** 是一个面向 UIKit 与 SwiftUI 的 HUD / 进度 / Toast 库，使用 Swift 6 严格并发编写。

它用 **每个任务一个 Token** 取代 `SVProgressHUD`、`MBProgressHUD` 的「全局 show / hide」模型，两个并发请求永远不会互相关掉对方的提示；同时内置受 `Toast-Swift` 启发的完整 Toast 系统，与 HUD 共用同一个窗口图层、主题与时钟。

[English](README.md)

![Interlude 截图](Docs/Screenshots/hero.png)

## 为什么选 Interlude

| | SVProgressHUD | MBProgressHUD | Toast-Swift | **Interlude** |
|---|---|---|---|---|
| 并发模型 | 全局 show / dismiss | 每次调用一个视图 | 每个视图一条 Toast | **每任务、每宿主一个 `Token`** |
| grace 延迟 | ✔ | ✔ | – | ✔（默认 0.15 s，等待期也拦截触摸） |
| 最短可见时间 | ✔ | ✔ | – | ✔ |
| 结果态（✓ / ✕ / ⓘ / 图片） | ✔ | – | – | ✔ + 触感 |
| 确定进度 | 圆环 | 圆环 / 条 / 环形 | – | **圆环、进度条、`Foundation.Progress` 绑定** |
| 取消按钮 / 超时 | – | – | – | ✔ |
| Toast | – | – | ✔ | ✔ stack / queue / replace、按钮、键盘避让 |
| 局部宿主（任意 `UIView`） | – | ✔ | ✔ | ✔ pop / 释放自动清理 |
| async / await | – | – | – | ✔ `Interlude.run` |
| SwiftUI | – | – | – | ✔ 修饰符 + `.interludeHost()` |
| Swift 6 严格并发 | – | – | – | ✔ |

## 安装

Interlude 仅通过 Swift Package Manager 分发。

```swift
dependencies: [
    .package(url: "https://github.com/KahnLi-lyc/Interlude.git", from: "1.0.0")
]
```

或在 Xcode 中 **File ▸ Add Package Dependencies…** 粘贴仓库地址。

## 快速开始

在 SceneDelegate 里配置一次窗口：

```swift
import Interlude

Interlude.configure { configuration in
    configuration.windowProvider = { [weak window] in window }
}
```

### 加载 → 结果

```swift
let token = Interlude.loading("保存中…")
api.save { result in
    switch result {
    case .success: token.finish(.success("已保存"))
    case .failure(let error): token.finish(.error(error.localizedDescription))
    }
}
```

`update` / `dismiss` / `finish` 都是 `nonisolated`，可以在任意线程、回调或 `deinit` 中调用。

### async / await

```swift
let user = try await Interlude.run("登录中", success: "欢迎回来") {
    try await auth.signIn(email, password)
}
```

成功则收起（或显示 `success` 文案），抛错则把 `localizedDescription` 作为错误结果展示，取消则静默收起。传 `cancellable: true` 会显示能取消 Task 的按钮。

### 进度

```swift
// 手动更新
let token = Interlude.progress(style: .bar, text: "上传中")
token.update(progress: 0.42)

// 绑定 Foundation.Progress
let token = Interlude.progress(uploadTask.progress, text: "上传中")

// async + 进度
try await Interlude.run("压缩中", style: .bar, totalUnitCount: 100) { progress in
    for chunk in chunks {
        try await compress(chunk)
        progress.completedUnitCount += 1
    }
}
```

### 纯文字、结果与自定义视图

```swift
Interlude.text("已复制到剪贴板")
Interlude.show(.success("完成"))
Interlude.show(.image(UIImage(systemName: "heart.fill")!, "已点赞"))
Interlude.custom(myAnimationView, text: "思考中…")
```

### Toast

```swift
Interlude.toast("消息已发送", icon: .success)
Interlude.toast("已保存", animation: .zoom)

Interlude.toast(
    "这条消息已从会话中移除。",
    title: "消息已删除",
    icon: .system("trash"),
    action: .init(title: "撤销") { restore() },
    duration: .long
)

let handle = Interlude.toast("当前离线", icon: .warning, duration: .persistent)
handle.dismiss()
```

策略（`stack(maximum:)` / `queue` / `replace`）、位置（`top` / `center` / `bottom` / `point`）、点按 / 滑动关闭与键盘避让都通过 `Interlude.configure { $0.toast… }` 配置。单次传入的 `animation:` 会覆盖 `theme.toast.animation`（默认 `.automatic`：边缘滑入，中间缩放）。

### 局部宿主

挂到任意视图而不是窗口。视图释放或所在页面被 pop / dismiss 时，覆盖层自动移除。

```swift
Interlude.loading("加载卡片", on: cardView)
Interlude.toast("只在卡片内显示", on: cardView)
```

### 取消、超时与回调

```swift
Interlude.loading("导出中", timeout: 30)
    .onCancel { exporter.cancel() }
    .onTimeout { log("导出超时") }
    .onDismiss { refresh() }
```

### SwiftUI

```swift
struct ContentView: View {
    @State private var isLoading = false
    @State private var progress: Double?
    @State private var toast: Interlude.Toast?

    var body: some View {
        Form { … }
            .interludeLoading(isPresented: $isLoading, text: "加载中")
            .interludeProgress($progress, style: .ring)
            .interludeToast($toast)
    }
}

// 把 HUD / Toast 限制在某个容器内
CardView()
    .interludeLoading(isPresented: $isCardLoading)
    .interludeHost()
```

## 行为约定

- **grace 延迟**（`graceTime`，0.15 s）：更快结束的任务不会闪现面板；blocking HUD 从第一次调用起就拦截触摸。
- **最短可见时间**（`minimumVisibleDuration`，0.35 s）：一旦可见就停留足够久。
- **后来者优先**：同一宿主多个 Token 时渲染最新的，收起后回到上一个。
- **只在空闲时显示结果**：`finish(.success)` 仅当宿主上没有其它活跃 Token 时才展示结果。
- **`dismissAll()`** 立即清空并使所有已有 Token 失效，迟到的 `finish` 会被忽略。
- **无障碍**：VoiceOver 播报、Dynamic Type、减弱动态效果（关闭动画）、降低透明度（实色面板）。
- **多语言**：en、zh-Hans、zh-Hant、ja、ko、fr、de、es、pt-BR，任何文案都可通过 `configuration.strings` 覆盖。

## 主题

```swift
var theme = Interlude.Theme.dark
theme.background = .solid(.systemIndigo)
theme.cornerRadius = 20
theme.animation = .zoom
theme.toast.animation = .slide
theme.toast.background = .blur(.systemThinMaterial)
Interlude.theme = theme

// 或按次覆盖
Interlude.loading("支付中", theme: .light)
```

预设：`.automatic`（跟随系统外观）、`.dark`、`.light`。

## 迁移对照

| 原调用 | Interlude |
|---|---|
| `SVProgressHUD.show()` / `dismiss()` | `let token = Interlude.loading()` / `token.dismiss()` |
| `SVProgressHUD.showSuccess(withStatus:)` | `token.finish(.success("…"))` 或 `Interlude.show(.success("…"))` |
| `MBProgressHUD.showAdded(to: view, animated:)` | `Interlude.loading(on: view)` |
| `hud.progress = 0.5` | `token.update(progress: 0.5)` |
| `view.makeToast("…")` | `Interlude.toast("…", on: view)` |

## 环境要求

- iOS 15.0+
- Swift 6.0 / Xcode 16+

## 示例工程

打开 `Example/InterludeExample.xcodeproj`（可用 `xcodegen` 从 `Example/project.yml` 重新生成）。每个公开 API 在示例列表里都有一行；`--autoplay <场景>` 启动参数可直接进入某个场景用于截图。

## 参与贡献

编码规范见 [AGENTS.md](AGENTS.md)，设计说明见 [DESIGN.md](DESIGN.md)。提 PR 前请运行 `swiftformat .`、`swiftlint --strict` 与测试。

## 许可证

MIT，见 [LICENSE](LICENSE)。
