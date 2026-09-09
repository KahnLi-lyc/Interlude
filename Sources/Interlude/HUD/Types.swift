import UIKit

public extension Interlude {
    /// How a HUD overlay treats touches on the host.
    enum Interaction: Sendable, Equatable {
        /// The overlay intercepts every touch, including during the grace period. Use for submits and payments.
        case blocking

        /// The overlay is transparent to touches; the user keeps working.
        case passthrough

        var blocksTouches: Bool {
            self == .blocking
        }
    }

    /// Visual style of determinate progress.
    enum ProgressStyle: Sendable, Equatable {
        /// A circular ring with the percentage in the centre.
        case ring

        /// A horizontal bar with the percentage on the trailing side.
        case bar
    }

    /// A short-lived outcome shown after a task finishes.
    enum Result: Sendable {
        /// A green checkmark. The optional text replaces the default accessibility label.
        case success(String? = nil)

        /// A red cross.
        case error(String? = nil)

        /// A blue info icon.
        case info(String? = nil)

        /// A custom image. Template images are tinted with the theme foreground colour.
        case image(UIImage, String? = nil)

        /// The user visible text, if any.
        public var text: String? {
            switch self {
            case .success(let text), .error(let text), .info(let text), .image(_, let text):
                return text
            }
        }

        var hapticType: UINotificationFeedbackGenerator.FeedbackType? {
            switch self {
            case .success: return .success
            case .error: return .error
            case .info: return .warning
            case .image: return nil
            }
        }
    }
}

/// HUD 面板的内容模式；`custom` 持有 UIView，因此只在 MainActor 使用。
@MainActor
enum HUDMode {
    case loading
    case progress(Double, Interlude.ProgressStyle)
    case text
    case custom(UIView)
    case result(Interlude.Result)

    /// 进度限制到 `0...1`，NaN 视为 0。
    var clamped: HUDMode {
        guard case .progress(let value, let style) = self else { return self }
        return .progress(HUDMode.clampProgress(value), style)
    }

    var isResult: Bool {
        if case .result = self { return true }
        return false
    }

    static func clampProgress(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }
}
