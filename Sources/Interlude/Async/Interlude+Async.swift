import UIKit

public extension Interlude {
    /// Runs `operation` under a loading HUD and ends the HUD with the outcome.
    ///
    /// - A successful return dismisses the HUD, or shows `success` when provided.
    /// - A thrown error shows `failure(error)` as an error result; `nil` dismisses silently.
    /// - Cancellation (from the caller or the cancel button) dismisses silently and rethrows `CancellationError`.
    ///
    /// The operation runs on the main actor; awaiting inside it does not block the UI.
    /// - Parameters:
    ///   - text: Primary text of the HUD.
    ///   - host: A view to attach to. `nil` uses the global window.
    ///   - interaction: Whether touches are blocked while the operation runs.
    ///   - success: Result text shown on success. `nil` dismisses without a result.
    ///   - failure: Maps a thrown error to result text. Return `nil` to dismiss without a result.
    ///   - cancellable: Shows a cancel button that cancels the operation.
    ///   - timeout: Overrides ``Configuration/timeout`` for this task.
    ///   - theme: Overrides ``theme`` for this task.
    ///   - operation: The asynchronous work.
    @MainActor
    @discardableResult
    static func run<T: Sendable>(
        _ text: String? = nil,
        on host: UIView? = nil,
        interaction: Interaction = .blocking,
        success: String? = nil,
        failure: @escaping @MainActor (any Error) -> String? = { $0.localizedDescription },
        cancellable: Bool = false,
        timeout: TimeInterval? = nil,
        theme: Theme? = nil,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let token = loading(text, on: host, interaction: interaction, timeout: timeout, theme: theme)
        let task = Task { @MainActor in
            try await operation()
        }
        return try await finish(token: token, task: task, success: success, failure: failure, cancellable: cancellable)
    }

    /// Runs `operation` under a progress HUD bound to the supplied `Progress`.
    ///
    /// Update `progress.completedUnitCount` from the operation (any thread) and the ring or bar follows.
    /// - Parameters:
    ///   - text: Primary text of the HUD.
    ///   - style: Ring or bar.
    ///   - totalUnitCount: Total units of the created `Progress`.
    ///   - host: A view to attach to. `nil` uses the global window.
    ///   - interaction: Whether touches are blocked while the operation runs.
    ///   - success: Result text shown on success. `nil` dismisses without a result.
    ///   - failure: Maps a thrown error to result text. Return `nil` to dismiss without a result.
    ///   - cancellable: Shows a cancel button that cancels the operation and the `Progress`.
    ///   - timeout: Overrides ``Configuration/timeout`` for this task.
    ///   - theme: Overrides ``theme`` for this task.
    ///   - operation: The asynchronous work; receives the `Progress` to report through.
    @MainActor
    @discardableResult
    static func run<T: Sendable>(
        _ text: String? = nil,
        style: ProgressStyle,
        totalUnitCount: Int64 = 100,
        on host: UIView? = nil,
        interaction: Interaction = .blocking,
        success: String? = nil,
        failure: @escaping @MainActor (any Error) -> String? = { $0.localizedDescription },
        cancellable: Bool = false,
        timeout: TimeInterval? = nil,
        theme: Theme? = nil,
        operation: @escaping @MainActor (Progress) async throws -> T
    ) async throws -> T {
        let progress = Progress(totalUnitCount: totalUnitCount)
        let token = Self.progress(
            progress,
            style: style,
            text: text,
            on: host,
            interaction: interaction,
            timeout: timeout,
            theme: theme
        )
        let task = Task { @MainActor in
            try await operation(progress)
        }
        return try await finish(
            token: token,
            task: task,
            success: success,
            failure: failure,
            cancellable: cancellable,
            additionalCancellation: { progress.cancel() }
        )
    }

    // MARK: - Private Methods

    @MainActor
    private static func finish<T: Sendable>(
        token: Token,
        task: Task<T, any Error>,
        success: String?,
        failure: @escaping @MainActor (any Error) -> String?,
        cancellable: Bool,
        additionalCancellation: (@MainActor () -> Void)? = nil
    ) async throws -> T {
        if cancellable {
            token.onCancel {
                additionalCancellation?()
                task.cancel()
            }
        }

        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            if let success {
                token.finish(.success(success))
            } else {
                token.dismiss()
            }
            return value
        } catch is CancellationError {
            token.dismiss()
            throw CancellationError()
        } catch {
            if let message = failure(error) {
                token.finish(.error(message))
            } else {
                token.dismiss()
            }
            throw error
        }
    }
}
