import ObjectiveC
import UIKit

// MARK: - Host

/// HUD 与 Toast 共用的展示宿主。
@MainActor
enum Host {
    /// 使用 `Configuration.windowProvider` 返回的窗口。
    case global

    /// 使用调用方传入的局部视图。
    case view(UIView)

    /// 由可选参数解析宿主：`nil` 即全局窗口。
    init(_ view: UIView?) {
        if let view {
            self = .view(view)
        } else {
            self = .global
        }
    }

    /// 稳定的字典键。
    var key: HostKey {
        switch self {
        case .global:
            return .global
        case let .view(view):
            return .view(ObjectIdentifier(view))
        }
    }
}

// MARK: - HostKey

/// 可安全保存在 MainActor 字典中的宿主标识。
enum HostKey: Hashable, Sendable {
    case global
    case view(ObjectIdentifier)
}

// MARK: - HostLifetime

/// 为局部宿主绑定一个仅由宿主持有的释放哨兵，宿主释放时回调清理。
///
/// HUD 与 Toast 各占一个关联对象槽位，互不覆盖。
@MainActor
enum HostLifetime {
    // MARK: - Types

    enum Slot {
        case hud
        case toast
    }

    // MARK: - Private Properties

    private static var hudAssociationKey: UInt8 = 0
    private static var toastAssociationKey: UInt8 = 0

    // MARK: - Public Methods

    /// 用新的生命周期标识替换宿主现有哨兵。
    /// - Parameters:
    ///   - view: 局部宿主。
    ///   - slot: HUD 或 Toast 槽位。
    ///   - lifetimeIdentifier: 本次宿主状态的唯一标识，用于拒绝对象地址复用后的旧回调。
    ///   - onEnd: 宿主释放后在 MainActor 执行的清理。
    static func install(
        on view: UIView,
        slot: Slot,
        lifetimeIdentifier: UUID,
        onEnd: @escaping @MainActor @Sendable (ObjectIdentifier, UUID) -> Void
    ) {
        let observer = HostLifetimeObserver(
            hostIdentifier: ObjectIdentifier(view),
            lifetimeIdentifier: lifetimeIdentifier,
            onEnd: onEnd
        )
        switch slot {
        case .hud:
            objc_setAssociatedObject(view, &hudAssociationKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        case .toast:
            objc_setAssociatedObject(view, &toastAssociationKey, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// MARK: - HostLifetimeObserver

/// 只保存不可变身份值的释放观察器；宿主释放时通过 `deinit` 切回 MainActor。
private final class HostLifetimeObserver: Sendable {
    // MARK: - Private Properties

    private let hostIdentifier: ObjectIdentifier
    private let lifetimeIdentifier: UUID
    private let onEnd: @MainActor @Sendable (ObjectIdentifier, UUID) -> Void

    // MARK: - Initialization

    init(
        hostIdentifier: ObjectIdentifier,
        lifetimeIdentifier: UUID,
        onEnd: @escaping @MainActor @Sendable (ObjectIdentifier, UUID) -> Void
    ) {
        self.hostIdentifier = hostIdentifier
        self.lifetimeIdentifier = lifetimeIdentifier
        self.onEnd = onEnd
    }

    deinit {
        let hostIdentifier = hostIdentifier
        let lifetimeIdentifier = lifetimeIdentifier
        let onEnd = onEnd
        MainActorDispatch.runOnMainActorNowOrAsync {
            onEnd(hostIdentifier, lifetimeIdentifier)
        }
    }
}

// MARK: - PassthroughLayerView

/// 铺满宿主、自身不参与命中测试、只把触摸交给子视图的图层容器。
@MainActor
class PassthroughLayerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
