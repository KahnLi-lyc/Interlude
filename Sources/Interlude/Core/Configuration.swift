import UIKit

public extension Interlude {
    /// Returns the window that hosts global HUDs and toasts. Always invoked on the main actor.
    typealias WindowProvider = @MainActor @Sendable () -> UIWindow?

    /// What happens when a HUD task exceeds its timeout.
    enum TimeoutBehavior: Sendable, Equatable {
        /// Dismiss silently without showing a result.
        case dismiss

        /// Show an error result. `nil` uses the localized "Request timed out" text.
        case error(message: String?)
    }

    /// Global behaviour and timing configuration. Mutate through ``Interlude/configure(_:)``.
    struct Configuration: Sendable {
        // MARK: - Public Properties

        /// Provides the window for global presentations. Required before any global HUD or toast can appear.
        public var windowProvider: WindowProvider?

        /// Delay before a HUD panel becomes visible. Tasks that finish sooner never flash a panel.
        public var graceTime: TimeInterval = 0.15

        /// Minimum time a visible panel stays on screen before it may hide.
        public var minimumVisibleDuration: TimeInterval = 0.35

        /// How long success / error / info results remain visible.
        public var resultDuration: TimeInterval = 1.2

        /// Default duration for ``Interlude/text(_:detail:duration:on:theme:)`` HUDs.
        public var textDuration: TimeInterval = 1.5

        /// Default timeout applied to every HUD task. `nil` disables timeouts.
        public var timeout: TimeInterval?

        /// What to do when a task times out.
        public var timeoutBehavior: TimeoutBehavior = .error(message: nil)

        /// Whether result states trigger haptic feedback.
        public var hapticsEnabled = true

        /// Default toast behaviour.
        public var toast = ToastDefaults()

        /// Overrides for the bundled localized strings.
        public var strings = Strings()

        // MARK: - Initialization

        public init() {}
    }

    /// Default values applied to toasts that do not specify their own.
    struct ToastDefaults: Sendable {
        // MARK: - Public Properties

        /// Where toasts appear when the call site does not specify a position.
        public var position: Toast.Position = .bottom

        /// How long toasts stay when the call site does not specify a duration.
        public var duration: Toast.Duration = .short

        /// How concurrent toasts at the same position are handled.
        public var policy: Toast.Policy = .stack(maximum: 3)

        /// Tapping a toast dismisses it and reports `didTap == true`.
        public var isTapToDismissEnabled = true

        /// Swiping a toast towards its edge dismisses it.
        public var isSwipeToDismissEnabled = true

        /// Bottom toasts in the global window move above the keyboard.
        public var avoidsKeyboard = true

        // MARK: - Initialization

        public init() {}
    }

    /// Optional overrides for the strings Interlude ships in nine languages.
    /// A `nil` field falls back to the bundled localization.
    struct Strings: Sendable {
        // MARK: - Public Properties

        /// Accessibility label for loading HUDs without text.
        public var loading: String?

        /// Accessibility label for success results without text.
        public var success: String?

        /// Accessibility label for error results without text.
        public var error: String?

        /// Accessibility label for info results without text.
        public var info: String?

        /// Message shown when a task times out with ``TimeoutBehavior/error(message:)``.
        public var timeout: String?

        /// Default title of the cancel button.
        public var cancel: String?

        /// Accessibility hint announced for dismissible toasts.
        public var toastDismissHint: String?

        // MARK: - Initialization

        public init() {}
    }
}
