import UIKit

/// Interlude — HUDs, progress and toasts for UIKit and SwiftUI.
///
/// Every presentation is driven by a token or handle so concurrent tasks never dismiss each
/// other's feedback. Configure the window once at launch:
///
/// ```swift
/// Interlude.configure { $0.windowProvider = { scene.keyWindow } }
/// let token = Interlude.loading("Saving…")
/// token.finish(.success("Saved"))
/// ```
public enum Interlude {
    // MARK: - Configuration

    /// The active configuration. Read-only; mutate through ``configure(_:)``.
    @MainActor
    public static var configuration: Configuration {
        Runtime.shared.configuration
    }

    /// The theme applied to presentations that do not pass their own.
    @MainActor
    public static var theme: Theme {
        get { Runtime.shared.theme }
        set { Runtime.shared.theme = newValue }
    }

    /// Whether any HUD panel is currently visible on any host.
    @MainActor
    public static var isShowingHUD: Bool {
        Runtime.shared.hud.isShowingAnything
    }

    /// Mutates the global configuration in place.
    @MainActor
    public static func configure(_ update: (inout Configuration) -> Void) {
        var configuration = Runtime.shared.configuration
        update(&configuration)
        Runtime.shared.configuration = configuration
    }

    // MARK: - HUD

    /// Shows an indeterminate loading HUD.
    /// - Parameters:
    ///   - text: Optional primary text.
    ///   - detail: Optional secondary text.
    ///   - host: A view to attach to. `nil` uses the global window.
    ///   - interaction: Whether touches are blocked while the HUD is registered.
    ///   - timeout: Overrides ``Configuration/timeout`` for this task.
    ///   - theme: Overrides ``theme`` for this task.
    @MainActor
    @discardableResult
    public static func loading(
        _ text: String? = nil,
        detail: String? = nil,
        on host: UIView? = nil,
        interaction: Interaction = .blocking,
        timeout: TimeInterval? = nil,
        theme: Theme? = nil
    ) -> Token {
        Runtime.shared.hud.show(
            HUDCoordinator.ShowRequest(
                host: Host(host),
                mode: .loading,
                text: text,
                detail: detail,
                interaction: interaction,
                theme: theme,
                timeout: timeout
            )
        )
    }

    /// Shows a determinate progress HUD.
    /// - Parameters:
    ///   - value: Initial progress in `0...1`.
    ///   - style: Ring or bar.
    ///   - text: Optional primary text.
    ///   - detail: Optional secondary text.
    ///   - host: A view to attach to. `nil` uses the global window.
    ///   - interaction: Whether touches are blocked while the HUD is registered.
    ///   - timeout: Overrides ``Configuration/timeout`` for this task.
    ///   - theme: Overrides ``theme`` for this task.
    @MainActor
    @discardableResult
    public static func progress(
        _ value: Double = 0,
        style: ProgressStyle = .ring,
        text: String? = nil,
        detail: String? = nil,
        on host: UIView? = nil,
        interaction: Interaction = .blocking,
        timeout: TimeInterval? = nil,
        theme: Theme? = nil
    ) -> Token {
        Runtime.shared.hud.show(
            HUDCoordinator.ShowRequest(
                host: Host(host),
                mode: .progress(value, style),
                text: text,
                detail: detail,
                interaction: interaction,
                theme: theme,
                timeout: timeout
            )
        )
    }

    /// Shows a progress HUD bound to a `Foundation.Progress`.
    @MainActor
    @discardableResult
    public static func progress(
        _ progress: Progress,
        style: ProgressStyle = .ring,
        text: String? = nil,
        on host: UIView? = nil,
        interaction: Interaction = .blocking,
        timeout: TimeInterval? = nil,
        theme: Theme? = nil
    ) -> Token {
        let token = Self.progress(
            progress.fractionCompleted,
            style: style,
            text: text,
            on: host,
            interaction: interaction,
            timeout: timeout,
            theme: theme
        )
        return token.observe(progress)
    }

    /// Shows a text-only HUD that dismisses itself.
    /// - Parameters:
    ///   - text: Primary text.
    ///   - detail: Optional secondary text.
    ///   - duration: Overrides ``Configuration/textDuration``.
    ///   - host: A view to attach to. `nil` uses the global window.
    ///   - theme: Overrides ``theme`` for this HUD.
    @MainActor
    @discardableResult
    public static func text(
        _ text: String,
        detail: String? = nil,
        duration: TimeInterval? = nil,
        on host: UIView? = nil,
        theme: Theme? = nil
    ) -> Token {
        Runtime.shared.hud.show(
            HUDCoordinator.ShowRequest(
                host: Host(host),
                mode: .text,
                text: text,
                detail: detail,
                interaction: .passthrough,
                theme: theme,
                timeout: nil,
                skipsGrace: true,
                autoDismissAfter: duration ?? Runtime.shared.configuration.textDuration
            )
        )
    }

    /// Shows a HUD with a custom view in place of the indicator.
    @MainActor
    @discardableResult
    public static func custom(
        _ view: UIView,
        text: String? = nil,
        detail: String? = nil,
        on host: UIView? = nil,
        interaction: Interaction = .blocking,
        timeout: TimeInterval? = nil,
        theme: Theme? = nil
    ) -> Token {
        Runtime.shared.hud.show(
            HUDCoordinator.ShowRequest(
                host: Host(host),
                mode: .custom(view),
                text: text,
                detail: detail,
                interaction: interaction,
                theme: theme,
                timeout: timeout
            )
        )
    }

    /// Shows a result directly, without a preceding task. It dismisses after ``Configuration/resultDuration``.
    @MainActor
    @discardableResult
    public static func show(_ result: Result, on host: UIView? = nil, theme: Theme? = nil) -> Token {
        Runtime.shared.hud.show(
            HUDCoordinator.ShowRequest(
                host: Host(host),
                mode: .result(result),
                text: result.text,
                detail: nil,
                interaction: .passthrough,
                theme: theme,
                timeout: nil,
                skipsGrace: true,
                autoDismissAfter: Runtime.shared.configuration.resultDuration
            )
        )
    }

    /// Removes every HUD on every host immediately and invalidates all existing tokens.
    /// Prefer ending tasks through their tokens; use this on logout or scene teardown.
    @MainActor
    public static func dismissAll() {
        Runtime.shared.hud.performDismissAll()
    }

    // MARK: - Toast

    /// Shows a toast built from a model.
    @MainActor
    @discardableResult
    public static func toast(_ toast: Toast, on host: UIView? = nil) -> Toast.Handle {
        Runtime.shared.toasts.show(toast, host: Host(host))
    }

    /// Shows a message toast.
    /// - Parameters:
    ///   - message: The text to show.
    ///   - icon: Optional leading icon.
    ///   - position: Overrides ``ToastDefaults/position``.
    ///   - duration: Overrides ``ToastDefaults/duration``.
    ///   - animation: Overrides the theme's toast animation. Pass `Interlude.Toast.Animation.none`
    ///     to disable motion; a bare `.none` is treated as `nil`.
    ///   - host: A view to attach to. `nil` uses the global window.
    ///   - completion: Called when the toast disappears; `didTap` is `true` for taps.
    @MainActor
    @discardableResult
    public static func toast(
        _ message: String,
        icon: Toast.Icon = .none,
        position: Toast.Position? = nil,
        duration: Toast.Duration? = nil,
        animation: Toast.Animation? = nil,
        on host: UIView? = nil,
        completion: (@MainActor (_ didTap: Bool) -> Void)? = nil
    ) -> Toast.Handle {
        toast(
            Toast(
                message,
                icon: icon,
                position: position,
                duration: duration,
                animation: animation,
                completion: completion
            ),
            on: host
        )
    }

    /// Shows a toast with a title, message and an action button.
    @MainActor
    @discardableResult
    public static func toast(
        _ message: String,
        title: String?,
        icon: Toast.Icon = .none,
        action: Toast.Action?,
        position: Toast.Position? = nil,
        duration: Toast.Duration? = nil,
        animation: Toast.Animation? = nil,
        on host: UIView? = nil,
        completion: (@MainActor (_ didTap: Bool) -> Void)? = nil
    ) -> Toast.Handle {
        toast(
            Toast(
                message,
                title: title,
                icon: icon,
                position: position,
                duration: duration,
                animation: animation,
                action: action,
                completion: completion
            ),
            on: host
        )
    }

    /// Removes every toast on every host, including queued ones.
    @MainActor
    public static func dismissAllToasts() {
        Runtime.shared.toasts.performDismissAll()
    }
}
