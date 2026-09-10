import UIKit

public extension Interlude {
    /// Content model of a toast. Build one and pass it to ``Interlude/toast(_:on:)``, or use the
    /// convenience overloads that take a message directly.
    struct Toast: Identifiable, Equatable {
        // MARK: - Types

        /// How a toast appears and disappears.
        public enum Animation: Sendable, Equatable {
            /// Slide from the matching edge for ``Position/top`` and ``Position/bottom``;
            /// ``Position/center`` and ``Position/point(_:)`` use ``zoom``.
            case automatic

            /// Slide in from the matching edge. Centre and point toasts fade in with a short lift.
            case slide

            /// Opacity only.
            case fade

            /// Opacity plus scale: grows in from 0.85× and shrinks out to 0.85×.
            case zoom

            /// No animation.
            case none
        }

        /// Where the toast is anchored inside its host.
        public enum Position: Hashable, Sendable {
            /// Below the top safe area.
            case top

            /// Vertically centred.
            case center

            /// Above the bottom safe area (and above the keyboard in the global window).
            case bottom

            /// Centred on an explicit point in the host's coordinate space.
            case point(CGPoint)

            public func hash(into hasher: inout Hasher) {
                switch self {
                case .top: hasher.combine(0)
                case .center: hasher.combine(1)
                case .bottom: hasher.combine(2)
                case let .point(point):
                    hasher.combine(3)
                    hasher.combine(point.x)
                    hasher.combine(point.y)
                }
            }
        }

        /// How long a toast stays on screen.
        public enum Duration: Sendable, Equatable {
            /// 2 seconds.
            case short

            /// 3.5 seconds.
            case long

            /// A custom number of seconds.
            case seconds(TimeInterval)

            /// Stays until dismissed through its ``Handle`` or ``Interlude/dismissAllToasts()``.
            case persistent

            /// The resolved duration; `nil` for ``persistent``.
            public var timeInterval: TimeInterval? {
                switch self {
                case .short: return 2
                case .long: return 3.5
                case let .seconds(value): return value.normalizedDuration
                case .persistent: return nil
                }
            }
        }

        /// Leading icon.
        public enum Icon {
            case none
            case success
            case error
            case info
            case warning
            /// An SF Symbol name.
            case system(String)
            /// A custom image. Template images are tinted with the theme foreground colour.
            case image(UIImage)
        }

        /// An optional trailing button.
        public struct Action {
            public var title: String
            public var handler: @MainActor () -> Void

            public init(title: String, handler: @escaping @MainActor () -> Void) {
                self.title = title
                self.handler = handler
            }
        }

        /// How concurrent toasts at the same position and host are handled.
        public enum Policy: Sendable, Equatable {
            /// Show several toasts at once; the oldest is evicted beyond `maximum`.
            case stack(maximum: Int)

            /// One at a time, first in first out.
            case queue

            /// The newest toast replaces whatever is showing and clears the queue.
            case replace
        }

        /// Handle for one toast. `dismiss()` may be called from any thread.
        public final class Handle: Sendable {
            // MARK: - Public Properties

            public let identifier: UUID

            /// Whether the toast is currently on screen.
            @MainActor
            public var isVisible: Bool {
                Runtime.shared.toasts.isVisible(identifier: identifier)
            }

            // MARK: - Initialization

            init(identifier: UUID) {
                self.identifier = identifier
            }

            static let inert = Handle(identifier: UUID())

            // MARK: - Public Methods

            /// Removes the toast. Its completion receives `didTap == false`.
            public nonisolated func dismiss() {
                let identifier = identifier
                MainActorDispatch.runOnMainActorNowOrAsync {
                    Runtime.shared.toasts.performDismiss(identifier: identifier, didTap: false)
                }
            }
        }

        // MARK: - Public Properties

        public let id: UUID
        public var message: String?
        public var title: String?
        public var icon: Icon
        /// `nil` uses ``Interlude/ToastDefaults/position``.
        public var position: Position?
        /// `nil` uses ``Interlude/ToastDefaults/duration``.
        public var duration: Duration?
        /// `nil` uses the current theme's toast animation.
        ///
        /// Pass ``Animation/none`` as `Interlude.Toast.Animation.none`; a bare `.none` is `nil`
        /// and therefore falls back to the theme.
        public var animation: Animation?
        public var action: Action?
        /// `nil` uses ``Interlude/theme``.
        public var theme: Theme?
        /// A fully custom view. When set, `message`, `title`, `icon` and `action` are ignored.
        public var customView: UIView?
        /// Called when the toast disappears. `didTap` is `true` for taps and action buttons.
        public var completion: (@MainActor (_ didTap: Bool) -> Void)?

        // MARK: - Initialization

        public init(
            _ message: String,
            title: String? = nil,
            icon: Icon = .none,
            position: Position? = nil,
            duration: Duration? = nil,
            animation: Animation? = nil,
            action: Action? = nil,
            theme: Theme? = nil,
            completion: (@MainActor (_ didTap: Bool) -> Void)? = nil
        ) {
            id = UUID()
            self.message = message
            self.title = title
            self.icon = icon
            self.position = position
            self.duration = duration
            self.animation = animation
            self.action = action
            self.theme = theme
            self.completion = completion
        }

        /// A toast that shows an arbitrary view.
        public static func custom(
            _ view: UIView,
            position: Position? = nil,
            duration: Duration? = nil,
            animation: Animation? = nil,
            theme: Theme? = nil,
            completion: (@MainActor (_ didTap: Bool) -> Void)? = nil
        ) -> Toast {
            var toast = Toast(
                "",
                position: position,
                duration: duration,
                animation: animation,
                theme: theme,
                completion: completion
            )
            toast.message = nil
            toast.customView = view
            return toast
        }

        // MARK: - Public Methods

        public static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.id == rhs.id
        }

        /// 至少有一项可见内容才值得创建视图。
        var hasContent: Bool {
            if customView != nil { return true }
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
            if case .none = icon { return false }
            return true
        }
    }
}
