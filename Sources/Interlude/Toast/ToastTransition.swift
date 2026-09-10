import UIKit

/// 根据动画类型、位置与最终布局计算 Toast 的出入场 transform。
struct ToastTransition: Equatable {
    // MARK: - Types

    private enum Constants {
        static let zoomScale: CGFloat = 0.85
        static let centerSlideOffset: CGFloat = 8
        static let fallbackSlideDistance: CGFloat = 80
    }

    // MARK: - Public Properties

    let appearing: CGAffineTransform
    let disappearing: CGAffineTransform

    var isAlphaOnly: Bool {
        appearing == .identity && disappearing == .identity
    }

    // MARK: - Public Methods

    static func resolve(
        animation: Interlude.Toast.Animation,
        position: Interlude.Toast.Position,
        viewFrame: CGRect,
        layerBounds: CGRect
    ) -> ToastTransition {
        switch resolvedStyle(animation, position: position) {
        case .automatic:
            // resolvedStyle 不会再返回 automatic。
            return ToastTransition(appearing: .identity, disappearing: .identity)
        case .slide:
            let translation = slideTranslation(
                position: position,
                viewFrame: viewFrame,
                layerBounds: layerBounds
            )
            let transform = CGAffineTransform(translationX: translation.x, y: translation.y)
            return ToastTransition(appearing: transform, disappearing: transform)
        case .fade, .none:
            return ToastTransition(appearing: .identity, disappearing: .identity)
        case .zoom:
            let transform = CGAffineTransform(scaleX: Constants.zoomScale, y: Constants.zoomScale)
            return ToastTransition(appearing: transform, disappearing: transform)
        }
    }

    static func resolvedStyle(
        _ animation: Interlude.Toast.Animation,
        position: Interlude.Toast.Position
    ) -> Interlude.Toast.Animation {
        switch animation {
        case .automatic:
            switch position {
            case .top, .bottom: return .slide
            case .center, .point: return .zoom
            }
        case .slide, .fade, .zoom, .none:
            return animation
        }
    }

    // MARK: - Private Methods

    private static func slideTranslation(
        position: Interlude.Toast.Position,
        viewFrame: CGRect,
        layerBounds: CGRect
    ) -> CGPoint {
        switch position {
        case .top:
            let distance = viewFrame.maxY > 0 ? viewFrame.maxY : Constants.fallbackSlideDistance
            return CGPoint(x: 0, y: -distance)
        case .bottom:
            let originY = viewFrame.isEmpty
                ? layerBounds.maxY - Constants.fallbackSlideDistance
                : viewFrame.minY
            return CGPoint(x: 0, y: layerBounds.maxY - originY)
        case .center, .point:
            return CGPoint(x: 0, y: -Constants.centerSlideOffset)
        }
    }
}
