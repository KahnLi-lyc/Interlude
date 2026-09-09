import Foundation

public extension Interlude {
    /// Handle for one HUD presentation.
    ///
    /// Keep the token for as long as the task runs and end it explicitly with ``dismiss()`` or
    /// ``finish(_:)``. `update`, `dismiss` and `finish` are `nonisolated`: call them from any
    /// thread, a completion handler or `deinit`. Tokens created before ``Interlude/dismissAll()``
    /// become inert and silently ignore later calls.
    final class Token: Sendable {
        // MARK: - Public Properties

        /// Stable identifier of the underlying HUD entry.
        public let identifier: UUID

        /// Session generation captured at creation; used to invalidate tokens after `dismissAll()`.
        let sessionGeneration: Int

        /// Whether the coordinator still tracks this token.
        @MainActor
        public var isActive: Bool {
            Runtime.shared.hud.isActive(identifier: identifier, sessionGeneration: sessionGeneration)
        }

        // MARK: - Initialization

        init(identifier: UUID, sessionGeneration: Int) {
            self.identifier = identifier
            self.sessionGeneration = sessionGeneration
        }

        /// A token that never matches any entry. Returned when a presentation could not be made.
        static let inert = Token(identifier: UUID(), sessionGeneration: -1)

        // MARK: - Public Methods

        /// Updates determinate progress (clamped to `0...1`). Switches a loading HUD to a ring.
        public nonisolated func update(progress: Double) {
            let identifier = identifier
            let generation = sessionGeneration
            MainActorDispatch.runOnMainActorNowOrAsync {
                Runtime.shared.hud.performUpdate(identifier: identifier, sessionGeneration: generation) { entry in
                    let style: Interlude.ProgressStyle = if case let .progress(_, current) = entry.mode {
                        current
                    } else {
                        .ring
                    }
                    entry.mode = .progress(progress, style).clamped
                }
            }
        }

        /// Updates the primary text. `nil` or an empty string hides the label.
        public nonisolated func update(text: String?) {
            let identifier = identifier
            let generation = sessionGeneration
            MainActorDispatch.runOnMainActorNowOrAsync {
                Runtime.shared.hud.performUpdate(identifier: identifier, sessionGeneration: generation) { entry in
                    entry.text = text
                }
            }
        }

        /// Updates the secondary detail text shown under the primary text.
        public nonisolated func update(detail: String?) {
            let identifier = identifier
            let generation = sessionGeneration
            MainActorDispatch.runOnMainActorNowOrAsync {
                Runtime.shared.hud.performUpdate(identifier: identifier, sessionGeneration: generation) { entry in
                    entry.detail = detail
                }
            }
        }

        /// Ends the task without showing a result.
        public nonisolated func dismiss() {
            let identifier = identifier
            let generation = sessionGeneration
            MainActorDispatch.runOnMainActorNowOrAsync {
                Runtime.shared.hud.performDismiss(identifier: identifier, sessionGeneration: generation)
            }
        }

        /// Ends the task and, if no other task is active on the same host, shows `result` briefly.
        public nonisolated func finish(_ result: Interlude.Result) {
            let identifier = identifier
            let generation = sessionGeneration
            MainActorDispatch.runOnMainActorNowOrAsync {
                Runtime.shared.hud.performFinish(identifier: identifier, sessionGeneration: generation, result: result)
            }
        }

        /// Mirrors `progress.fractionCompleted` into the HUD. Observation ends with the token.
        /// - Parameters:
        ///   - progress: The `Foundation.Progress` to observe.
        ///   - updatesDetail: Also mirrors `localizedAdditionalDescription` into the detail label.
        @MainActor
        @discardableResult
        public func observe(_ progress: Progress, updatesDetail: Bool = true) -> Token {
            Runtime.shared.hud.observe(
                progress,
                updatesDetail: updatesDetail,
                identifier: identifier,
                sessionGeneration: sessionGeneration
            )
            return self
        }

        /// Shows a cancel button. Tapping it calls `handler` and dismisses the HUD.
        /// The overlay is forced to ``Interlude/Interaction/blocking`` so the button can be tapped.
        /// - Parameters:
        ///   - title: Button title. `nil` uses the localized "Cancel".
        ///   - handler: Called on the main actor when the user taps the button.
        @MainActor
        @discardableResult
        public func onCancel(title: String? = nil, _ handler: @escaping @MainActor () -> Void) -> Token {
            Runtime.shared.hud.setCancel(
                title: title,
                handler: handler,
                identifier: identifier,
                sessionGeneration: sessionGeneration
            )
            return self
        }

        /// Called once after the HUD for this token has fully disappeared.
        @MainActor
        @discardableResult
        public func onDismiss(_ handler: @escaping @MainActor () -> Void) -> Token {
            Runtime.shared.hud.setDismissHandler(handler, identifier: identifier, sessionGeneration: sessionGeneration)
            return self
        }

        /// Called when the task exceeds its timeout, before the configured ``Interlude/TimeoutBehavior`` runs.
        @MainActor
        @discardableResult
        public func onTimeout(_ handler: @escaping @MainActor () -> Void) -> Token {
            Runtime.shared.hud.setTimeoutHandler(handler, identifier: identifier, sessionGeneration: sessionGeneration)
            return self
        }
    }
}
