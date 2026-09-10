import UIKit

public extension Interlude {
    /// Transition used when a HUD panel appears and disappears.
    enum Animation: Sendable, Equatable {
        /// Opacity only.
        case fade

        /// Opacity plus scale: shrinks in from 1.3× and shrinks out to 0.7×.
        case zoom

        /// Opacity plus scale: grows in from 0.7× and shrinks out to 0.7×.
        case zoomIn

        /// Opacity plus scale: shrinks in from 1.3× and grows out to 1.3×.
        case zoomOut

        /// No animation.
        case none
    }

    /// Every visual parameter used by HUDs and toasts. Assign to ``Interlude/theme`` or pass per call.
    struct Theme: Sendable {
        // MARK: - Types

        /// Panel background material.
        public enum Background: Sendable {
            /// A `UIVisualEffectView` blur.
            case blur(UIBlurEffect.Style)

            /// A solid colour.
            case solid(UIColor)
        }

        /// Optional drop shadow.
        public struct Shadow: Sendable {
            public var color: UIColor
            public var opacity: Float
            public var radius: CGFloat
            public var offset: CGSize

            public init(
                color: UIColor = .black,
                opacity: Float = 0.2,
                radius: CGFloat = 8,
                offset: CGSize = CGSize(width: 0, height: 4)
            ) {
                self.color = color
                self.opacity = opacity
                self.radius = radius
                self.offset = offset
            }
        }

        /// Toast specific visual parameters.
        public struct Toast: Sendable {
            public var background: Background = .solid(UIColor.black.withAlphaComponent(0.8))
            public var reduceTransparencyColor: UIColor = .init(white: 0.1, alpha: 1)
            public var foregroundColor: UIColor = .white
            public var secondaryForegroundColor: UIColor = .white.withAlphaComponent(0.8)
            public var actionTintColor: UIColor = .systemBlue
            public var cornerRadius: CGFloat = 10
            public var messageFont: UIFont = .preferredFont(forTextStyle: .subheadline)
            public var titleFont: UIFont = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
            public var actionFont: UIFont = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
            public var contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            public var maximumWidthRatio: CGFloat = 0.8
            public var edgeInset: CGFloat = 16
            public var spacing: CGFloat = 8
            public var iconSize: CGFloat = 20
            public var shadow: Shadow? = Shadow()
            public var animation: Interlude.Toast.Animation = .automatic
            public var animationDuration: TimeInterval = 0.2

            public init() {}
        }

        // MARK: - Public Properties

        public var background: Background
        public var reduceTransparencyColor: UIColor
        public var dimmingColor: UIColor
        public var foregroundColor: UIColor
        public var secondaryForegroundColor: UIColor
        public var indicatorColor: UIColor
        public var trackColor: UIColor
        public var successColor: UIColor = .systemGreen
        public var errorColor: UIColor = .systemRed
        public var infoColor: UIColor = .systemBlue
        public var cornerRadius: CGFloat = 12
        public var textFont: UIFont = .preferredFont(forTextStyle: .subheadline)
        public var detailFont: UIFont = .preferredFont(forTextStyle: .footnote)
        public var buttonFont: UIFont = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        public var contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        public var spacing: CGFloat = 10
        public var indicatorSize: CGFloat = 52
        public var ringLineWidth: CGFloat = 5
        public var minimumSize = CGSize(width: 96, height: 96)
        public var maximumWidth: CGFloat = 260
        public var offset: UIOffset = .zero
        public var animation: Animation = .fade
        public var animationDuration: TimeInterval = 0.15
        /// At least two colours draw a gradient on ring and bar progress; fewer uses ``indicatorColor``.
        public var progressGradient: [UIColor] = []

        var usesProgressGradient: Bool {
            progressGradient.count >= 2
        }

        public var toast = Toast()

        // MARK: - Initialization

        /// Creates a theme from the colours that differ between light and dark variants.
        public init(
            background: Background,
            reduceTransparencyColor: UIColor,
            dimmingColor: UIColor,
            foregroundColor: UIColor,
            secondaryForegroundColor: UIColor,
            indicatorColor: UIColor,
            trackColor: UIColor
        ) {
            self.background = background
            self.reduceTransparencyColor = reduceTransparencyColor
            self.dimmingColor = dimmingColor
            self.foregroundColor = foregroundColor
            self.secondaryForegroundColor = secondaryForegroundColor
            self.indicatorColor = indicatorColor
            self.trackColor = trackColor
        }

        // MARK: - Presets

        /// Dark panel with light content. Works on any background.
        public static let dark: Theme = {
            var theme = Theme(
                background: .blur(.systemChromeMaterialDark),
                reduceTransparencyColor: UIColor(white: 0.08, alpha: 0.96),
                dimmingColor: UIColor.black.withAlphaComponent(0.12),
                foregroundColor: .white,
                secondaryForegroundColor: UIColor.white.withAlphaComponent(0.7),
                indicatorColor: .white,
                trackColor: UIColor.white.withAlphaComponent(0.25)
            )
            theme.progressGradient = [theme.indicatorColor, theme.infoColor]
            return theme
        }()

        /// Light panel with dark content.
        public static let light: Theme = {
            var theme = Theme(
                background: .blur(.systemChromeMaterialLight),
                reduceTransparencyColor: UIColor(white: 0.97, alpha: 0.98),
                dimmingColor: UIColor.black.withAlphaComponent(0.08),
                foregroundColor: UIColor(white: 0.1, alpha: 1),
                secondaryForegroundColor: UIColor(white: 0.1, alpha: 0.6),
                indicatorColor: UIColor(white: 0.1, alpha: 1),
                trackColor: UIColor(white: 0.1, alpha: 0.15)
            )
            theme.progressGradient = [theme.indicatorColor, theme.infoColor]
            theme.toast.background = .solid(UIColor(white: 0.97, alpha: 0.98))
            theme.toast.reduceTransparencyColor = UIColor(white: 0.97, alpha: 1)
            theme.toast.foregroundColor = UIColor(white: 0.1, alpha: 1)
            theme.toast.secondaryForegroundColor = UIColor(white: 0.1, alpha: 0.7)
            return theme
        }()

        /// Follows the system appearance using dynamic colours.
        public static let automatic: Theme = {
            var theme = Theme(
                background: .blur(.systemChromeMaterial),
                reduceTransparencyColor: UIColor.dynamic(
                    light: UIColor(white: 0.97, alpha: 0.98),
                    dark: UIColor(white: 0.08, alpha: 0.96)
                ),
                dimmingColor: UIColor.dynamic(
                    light: UIColor.black.withAlphaComponent(0.08),
                    dark: UIColor.black.withAlphaComponent(0.2)
                ),
                foregroundColor: .label,
                secondaryForegroundColor: .secondaryLabel,
                indicatorColor: .label,
                trackColor: UIColor.dynamic(
                    light: UIColor(white: 0.1, alpha: 0.15),
                    dark: UIColor.white.withAlphaComponent(0.25)
                )
            )
            theme.progressGradient = [theme.indicatorColor, theme.infoColor]
            theme.toast.background = .blur(.systemChromeMaterial)
            theme.toast.reduceTransparencyColor = UIColor.dynamic(
                light: UIColor(white: 0.97, alpha: 1),
                dark: UIColor(white: 0.1, alpha: 1)
            )
            theme.toast.foregroundColor = .label
            theme.toast.secondaryForegroundColor = .secondaryLabel
            return theme
        }()
    }
}

// MARK: - Helpers

extension UIColor {
    /// 按当前界面风格切换的动态颜色。
    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }

    /// 解析当前 trait 下的 `CGColor`，供图层使用。
    var resolvedCGColor: CGColor {
        resolvedColor(with: UITraitCollection.current).cgColor
    }
}

extension UIFont {
    /// 在保留 Dynamic Type 文本样式的前提下调整字重。
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
