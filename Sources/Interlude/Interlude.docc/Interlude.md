# ``Interlude``

Token-driven HUDs, progress indicators and toasts for UIKit and SwiftUI.

## Overview

Every presentation in Interlude is owned by a handle: a ``Interlude/Token`` for HUDs and a
``Interlude/Toast/Handle`` for toasts. Because the handle — not a global singleton — ends a
presentation, concurrent tasks never dismiss each other's feedback, and late callbacks after
``Interlude/dismissAll()`` are ignored instead of resurrecting a panel.

Configure the window once at launch, then call the static entry points anywhere:

```swift
Interlude.configure { $0.windowProvider = { scene.keyWindow } }

let token = Interlude.loading("Saving…")
token.finish(.success("Saved"))

Interlude.toast("Message sent", icon: .success)
```

## Topics

### Configuration

- ``Interlude/configure(_:)``
- ``Interlude/configuration``
- ``Interlude/Configuration``
- ``Interlude/ToastDefaults``
- ``Interlude/Strings``
- ``Interlude/theme``
- ``Interlude/Theme``

### HUD

- ``Interlude/loading(_:detail:on:interaction:timeout:theme:)``
- ``Interlude/progress(_:style:fill:text:detail:on:interaction:timeout:theme:)``
- ``Interlude/progress(_:style:fill:text:on:interaction:timeout:theme:)``
- ``Interlude/text(_:detail:duration:on:theme:)``
- ``Interlude/custom(_:text:detail:on:interaction:timeout:theme:)``
- ``Interlude/show(_:on:theme:)``
- ``Interlude/dismissAll()``
- ``Interlude/isShowingHUD``
- ``Interlude/Token``
- ``Interlude/Result``
- ``Interlude/Interaction``
- ``Interlude/ProgressStyle``
- ``Interlude/ProgressFill``
- ``Interlude/TimeoutBehavior``
- ``Interlude/Animation``

### Toast

- ``Interlude/toast(_:on:)``
- ``Interlude/toast(_:icon:position:duration:animation:on:completion:)``
- ``Interlude/toast(_:title:icon:action:position:duration:animation:on:completion:)``
- ``Interlude/dismissAllToasts()``
- ``Interlude/Toast``

### async / await

- ``Interlude/run(_:on:interaction:success:failure:cancellable:timeout:theme:operation:)``
- ``Interlude/run(_:style:fill:totalUnitCount:on:interaction:success:failure:cancellable:timeout:theme:operation:)``

### SwiftUI

- ``SwiftUICore/View/interludeLoading(isPresented:text:interaction:)``
- ``SwiftUICore/View/interludeProgress(_:style:fill:text:interaction:)``
- ``SwiftUICore/View/interludeToast(_:)``
- ``SwiftUICore/View/interludeHost()``
