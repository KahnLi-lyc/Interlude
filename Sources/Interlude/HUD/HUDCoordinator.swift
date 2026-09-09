import UIKit

// MARK: - HUDEntry

/// 单个 Token 对应的展示条目。存放在 MainActor 状态里，因此可持有 UIView 与闭包。
@MainActor
struct HUDEntry {
    let identifier: UUID
    var mode: HUDMode
    var text: String?
    var detail: String?
    var interaction: Interlude.Interaction
    var theme: Interlude.Theme?
    let displayOrder: Int
    let requestUptime: TimeInterval
    let skipsGrace: Bool
    var cancelTitle: String?
    var cancelHandler: (@MainActor () -> Void)?
    var dismissHandler: (@MainActor () -> Void)?
    var timeoutHandler: (@MainActor () -> Void)?
    var timeoutTask: Task<Void, Never>?
    var autoDismissTask: Task<Void, Never>?
    var progressObservation: NSKeyValueObservation?

    /// 有取消按钮时必须拦截触摸，否则按钮不可点。
    var effectiveInteraction: Interlude.Interaction {
        cancelTitle != nil ? .blocking : interaction
    }

    /// 结束条目附带的全部计时与观察。
    func tearDown() {
        timeoutTask?.cancel()
        autoDismissTask?.cancel()
        progressObservation?.invalidate()
    }
}

// MARK: - HUDSnapshot

/// 交给视图渲染的不可变快照。
@MainActor
struct HUDSnapshot {
    let mode: HUDMode
    let text: String?
    let detail: String?
    let interaction: Interlude.Interaction
    let cancelTitle: String?
    let theme: Interlude.Theme
}

// MARK: - HUDCoordinator

/// HUD 状态机：登记 Token、决定同宿主的显示优先级、驱动 grace / 最短可见 / 结果 / 超时计时。
@MainActor
final class HUDCoordinator {
    // MARK: - Types

    struct ShowRequest {
        var host: Host
        var mode: HUDMode
        var text: String?
        var detail: String?
        var interaction: Interlude.Interaction
        var theme: Interlude.Theme?
        var timeout: TimeInterval?
        var skipsGrace = false
        var autoDismissAfter: TimeInterval?
    }

    // MARK: - Public Properties

    /// 当前是否有任何宿主显示着面板。
    var isShowingAnything: Bool {
        if globalState.isContentVisible { return true }
        return localStates.values.contains { $0.isContentVisible }
    }

    var localHostCountForTesting: Int {
        localStates.count
    }

    // MARK: - Private Properties

    private unowned let runtime: Runtime
    private var sessionGeneration = 0
    private var displayOrder = 0
    private let globalState = HUDHostState(key: .global, hostView: nil)
    private var localStates: [ObjectIdentifier: HUDHostState] = [:]

    private var configuration: Interlude.Configuration {
        runtime.configuration
    }

    private var now: TimeInterval {
        runtime.clock.now
    }

    // MARK: - Initialization

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    // MARK: - Public Methods

    /// 登记一个条目并返回专属 Token。
    func show(_ request: ShowRequest) -> Interlude.Token {
        cleanupReleasedLocalStates()

        if case .global = request.host, runtime.resolveGlobalWindow() == nil {
            return .inert
        }

        let state = state(for: request.host)
        cancelDismissalTask(in: state)
        if state.isContentVisible {
            state.visibleSince = now
        }

        displayOrder &+= 1
        let token = Interlude.Token(identifier: UUID(), sessionGeneration: sessionGeneration)
        var entry = HUDEntry(
            identifier: token.identifier,
            mode: request.mode.clamped,
            text: request.text,
            detail: request.detail,
            interaction: request.interaction,
            theme: request.theme,
            displayOrder: displayOrder,
            requestUptime: now,
            skipsGrace: request.skipsGrace
        )
        entry.timeoutTask = makeTimeoutTask(for: token.identifier, timeout: request.timeout ?? configuration.timeout)
        entry.autoDismissTask = makeAutoDismissTask(for: token.identifier, after: request.autoDismissAfter)
        state.entries[token.identifier] = entry

        if case .result(let result) = request.mode {
            runtime.playHaptic(for: result)
        }

        presentActiveEntry(in: state)
        return token
    }

    func isActive(identifier: UUID, sessionGeneration: Int) -> Bool {
        guard self.sessionGeneration == sessionGeneration else { return false }
        return state(containing: identifier) != nil
    }

    /// 修改条目并在其为当前显示条目时刷新视图。
    func performUpdate(identifier: UUID, sessionGeneration: Int, _ mutate: (inout HUDEntry) -> Void) {
        guard self.sessionGeneration == sessionGeneration,
              let state = state(containing: identifier),
              var entry = state.entries[identifier] else {
            return
        }
        mutate(&entry)
        entry.mode = entry.mode.clamped
        state.entries[identifier] = entry
        presentActiveEntry(in: state)
    }

    func performDismiss(identifier: UUID, sessionGeneration: Int) {
        guard self.sessionGeneration == sessionGeneration,
              let state = state(containing: identifier) else {
            return
        }
        removeEntry(identifier, from: state)
        updatePresentationAfterRemovingEntry(from: state)
    }

    func performFinish(identifier: UUID, sessionGeneration: Int, result: Interlude.Result) {
        guard self.sessionGeneration == sessionGeneration,
              let state = state(containing: identifier) else {
            return
        }
        let removed = removeEntry(identifier, from: state)

        guard state.entries.isEmpty else {
            presentActiveEntry(in: state)
            return
        }
        insertResultEntry(result, theme: removed?.theme, in: state)
    }

    /// 取消按钮触发：先回调业务，再关闭条目。
    func performCancel(identifier: UUID) {
        guard let state = state(containing: identifier),
              let entry = state.entries[identifier] else {
            return
        }
        entry.cancelHandler?()
        removeEntry(identifier, from: state)
        updatePresentationAfterRemovingEntry(from: state)
    }

    /// 立即清理全部宿主并使当前会话 Token 失效。
    func performDismissAll() {
        sessionGeneration &+= 1
        dismissImmediately(state: globalState, retainOverlay: true)
        localStates.values.forEach { dismissImmediately(state: $0, retainOverlay: false) }
        localStates.removeAll()
    }

    func observe(_ progress: Progress, updatesDetail: Bool, identifier: UUID, sessionGeneration: Int) {
        guard self.sessionGeneration == sessionGeneration,
              let state = state(containing: identifier),
              var entry = state.entries[identifier] else {
            return
        }
        entry.progressObservation?.invalidate()
        let token = Interlude.Token(identifier: identifier, sessionGeneration: sessionGeneration)
        entry.progressObservation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { @Sendable progress, _ in
            // KVO 回调可能来自后台线程；闭包显式 @Sendable 且只经 Token 的 nonisolated 方法切回主线程。
            token.update(progress: progress.fractionCompleted)
            if updatesDetail {
                let description = progress.localizedAdditionalDescription ?? ""
                token.update(detail: description.isEmpty ? nil : description)
            }
        }
        state.entries[identifier] = entry
    }

    func setCancel(title: String?, handler: @escaping @MainActor () -> Void, identifier: UUID, sessionGeneration: Int) {
        performUpdate(identifier: identifier, sessionGeneration: sessionGeneration) { entry in
            entry.cancelTitle = title ?? runtime.string(.cancel)
            entry.cancelHandler = handler
        }
    }

    func setDismissHandler(_ handler: @escaping @MainActor () -> Void, identifier: UUID, sessionGeneration: Int) {
        guard self.sessionGeneration == sessionGeneration,
              let state = state(containing: identifier) else {
            return
        }
        state.entries[identifier]?.dismissHandler = handler
    }

    func setTimeoutHandler(_ handler: @escaping @MainActor () -> Void, identifier: UUID, sessionGeneration: Int) {
        guard self.sessionGeneration == sessionGeneration,
              let state = state(containing: identifier) else {
            return
        }
        state.entries[identifier]?.timeoutHandler = handler
    }

    /// 页面退出或宿主释放后，按对象身份和生命周期标识清理局部状态。
    func localHostDidEndLifetime(identifier: ObjectIdentifier, lifetimeIdentifier: UUID) {
        guard let state = localStates[identifier],
              state.lifetimeIdentifier == lifetimeIdentifier else {
            return
        }
        localStates.removeValue(forKey: identifier)
        dismissImmediately(state: state, retainOverlay: false)
    }

    func resetForTesting() {
        performDismissAll()
        displayOrder = 0
        globalState.overlay?.removeFromSuperview()
        globalState.overlay = nil
        globalState.attachedWindow = nil
    }

    /// 返回宿主当前的覆盖层视图，供测试断言渲染状态。
    func overlay(for host: Host) -> HUDView? {
        switch host {
        case .global:
            return globalState.overlay
        case .view(let view):
            return localStates[ObjectIdentifier(view)]?.overlay
        }
    }

    // MARK: - Private Methods

    private func insertResultEntry(_ result: Interlude.Result, theme: Interlude.Theme?, in state: HUDHostState) {
        cancelDismissalTask(in: state)
        displayOrder &+= 1
        let identifier = UUID()
        var entry = HUDEntry(
            identifier: identifier,
            mode: .result(result),
            text: result.text,
            detail: nil,
            interaction: .passthrough,
            theme: theme,
            displayOrder: displayOrder,
            requestUptime: now,
            skipsGrace: true
        )
        entry.autoDismissTask = makeAutoDismissTask(for: identifier, after: configuration.resultDuration)
        state.entries[identifier] = entry
        state.visibleSince = now
        runtime.playHaptic(for: result)
        presentActiveEntry(in: state)
    }

    @discardableResult
    private func removeEntry(_ identifier: UUID, from state: HUDHostState) -> HUDEntry? {
        guard let entry = state.entries.removeValue(forKey: identifier) else { return nil }
        entry.tearDown()
        if let handler = entry.dismissHandler {
            if state.entries.isEmpty {
                state.pendingDismissHandlers.append(handler)
            } else {
                handler()
            }
        }
        return entry
    }

    private func makeTimeoutTask(for identifier: UUID, timeout: TimeInterval?) -> Task<Void, Never>? {
        guard let timeout, timeout.isFinite, timeout > 0 else { return nil }
        let generation = sessionGeneration
        return Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await runtime.clock.sleep(for: timeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            performTimeout(identifier: identifier, sessionGeneration: generation)
        }
    }

    private func makeAutoDismissTask(for identifier: UUID, after duration: TimeInterval?) -> Task<Void, Never>? {
        guard let duration else { return nil }
        let generation = sessionGeneration
        return Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await runtime.clock.sleep(for: duration.normalizedDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            performDismiss(identifier: identifier, sessionGeneration: generation)
        }
    }

    private func performTimeout(identifier: UUID, sessionGeneration: Int) {
        guard self.sessionGeneration == sessionGeneration,
              let state = state(containing: identifier),
              let entry = state.entries[identifier] else {
            return
        }
        entry.timeoutHandler?()
        switch configuration.timeoutBehavior {
        case .dismiss:
            performDismiss(identifier: identifier, sessionGeneration: sessionGeneration)
        case .error(let message):
            performFinish(
                identifier: identifier,
                sessionGeneration: sessionGeneration,
                result: .error(message ?? runtime.string(.timeout))
            )
        }
    }

    // MARK: 活跃条目展示

    private func presentActiveEntry(in state: HUDHostState) {
        guard let entry = activeEntry(in: state),
              let overlay = installOverlay(for: state) else {
            return
        }

        cancelPresentationTask(in: state)
        if state.isContentVisible {
            overlay.render(snapshot(for: entry), animated: false)
            return
        }

        overlay.prepareForPendingPresentation(interaction: entry.effectiveInteraction, theme: resolvedTheme(for: entry))

        let elapsed = max(0, now - entry.requestUptime)
        let remainingGrace = entry.skipsGrace ? 0 : max(0, configuration.graceTime.normalizedDuration - elapsed)
        guard remainingGrace > 0 else {
            showActiveEntryNow(in: state)
            return
        }

        let generation = advanceLifecycleGeneration(in: state)
        let key = state.key
        state.presentationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await runtime.clock.sleep(for: remainingGrace)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let currentState = self.state(for: key),
                  currentState.lifecycleGeneration == generation else {
                return
            }
            currentState.presentationTask = nil
            showActiveEntryNow(in: currentState)
        }
    }

    private func showActiveEntryNow(in state: HUDHostState) {
        guard let entry = activeEntry(in: state),
              let overlay = installOverlay(for: state) else {
            return
        }
        cancelPresentationTask(in: state)
        state.isContentVisible = true
        state.visibleSince = now
        overlay.render(snapshot(for: entry), animated: true)
    }

    private func activeEntry(in state: HUDHostState) -> HUDEntry? {
        state.entries.values.max(by: { $0.displayOrder < $1.displayOrder })
    }

    private func snapshot(for entry: HUDEntry) -> HUDSnapshot {
        HUDSnapshot(
            mode: entry.mode,
            text: entry.text,
            detail: entry.detail,
            interaction: entry.effectiveInteraction,
            cancelTitle: entry.cancelTitle,
            theme: resolvedTheme(for: entry)
        )
    }

    private func resolvedTheme(for entry: HUDEntry) -> Interlude.Theme {
        entry.theme ?? runtime.theme
    }

    // MARK: 隐藏调度

    private func updatePresentationAfterRemovingEntry(from state: HUDHostState) {
        guard state.entries.isEmpty else {
            presentActiveEntry(in: state)
            return
        }

        cancelPresentationTask(in: state)
        guard state.isContentVisible else {
            dismissImmediately(state: state, retainOverlay: state.key == .global)
            removeLocalStateIfIdle(state)
            return
        }
        scheduleDismissalRespectingMinimumDuration(for: state)
    }

    private func scheduleDismissalRespectingMinimumDuration(for state: HUDHostState) {
        cancelDismissalTask(in: state)
        let visibleSince = state.visibleSince ?? now
        let elapsed = max(0, now - visibleSince)
        let remaining = max(0, configuration.minimumVisibleDuration.normalizedDuration - elapsed)

        guard remaining > 0 else {
            beginAnimatedHide(for: state)
            return
        }

        let generation = advanceLifecycleGeneration(in: state)
        let key = state.key
        state.dismissalTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await runtime.clock.sleep(for: remaining)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let currentState = self.state(for: key),
                  currentState.lifecycleGeneration == generation,
                  currentState.entries.isEmpty else {
                return
            }
            currentState.dismissalTask = nil
            beginAnimatedHide(for: currentState)
        }
    }

    private func beginAnimatedHide(for state: HUDHostState) {
        cancelPresentationTask(in: state)
        cancelDismissalTask(in: state)

        let generation = advanceLifecycleGeneration(in: state)
        let key = state.key
        guard let overlay = state.overlay else {
            completeHide(for: key, generation: generation, overlay: nil)
            return
        }

        overlay.hide(animated: true) { [weak self, weak overlay] in
            self?.completeHide(for: key, generation: generation, overlay: overlay)
        }
    }

    private func completeHide(for key: HostKey, generation: Int, overlay: HUDView?) {
        guard let state = state(for: key),
              state.lifecycleGeneration == generation,
              state.entries.isEmpty else {
            return
        }

        if case .view = key {
            overlay?.localHostExitHandler = nil
        }
        overlay?.removeFromSuperview()
        state.isContentVisible = false
        state.visibleSince = nil

        switch key {
        case .global:
            break
        case .view(let identifier):
            state.overlay = nil
            localStates.removeValue(forKey: identifier)
        }
        flushDismissHandlers(in: state)
    }

    private func dismissImmediately(state: HUDHostState, retainOverlay: Bool) {
        cancelPresentationTask(in: state)
        cancelDismissalTask(in: state)
        _ = advanceLifecycleGeneration(in: state)

        for entry in state.entries.values {
            entry.tearDown()
            if let handler = entry.dismissHandler {
                state.pendingDismissHandlers.append(handler)
            }
        }
        state.entries.removeAll()

        if !retainOverlay {
            state.overlay?.localHostExitHandler = nil
        }
        state.overlay?.hide(animated: false) {}
        state.overlay?.removeFromSuperview()
        state.isContentVisible = false
        state.visibleSince = nil

        if !retainOverlay {
            state.overlay = nil
            state.attachedWindow = nil
        }
        flushDismissHandlers(in: state)
    }

    private func flushDismissHandlers(in state: HUDHostState) {
        let handlers = state.pendingDismissHandlers
        state.pendingDismissHandlers.removeAll()
        handlers.forEach { $0() }
    }

    // MARK: 计时任务

    private func cancelPresentationTask(in state: HUDHostState) {
        state.presentationTask?.cancel()
        state.presentationTask = nil
    }

    private func cancelDismissalTask(in state: HUDHostState) {
        state.dismissalTask?.cancel()
        state.dismissalTask = nil
    }

    private func advanceLifecycleGeneration(in state: HUDHostState) -> Int {
        state.lifecycleGeneration &+= 1
        return state.lifecycleGeneration
    }

    // MARK: 宿主管理

    private func state(for host: Host) -> HUDHostState {
        switch host {
        case .global:
            return globalState
        case .view(let view):
            let identifier = ObjectIdentifier(view)
            if let state = localStates[identifier] {
                return state
            }
            let state = HUDHostState(key: .view(identifier), hostView: view)
            localStates[identifier] = state
            HostLifetime.install(on: view, slot: .hud, lifetimeIdentifier: state.lifetimeIdentifier) { identifier, lifetime in
                Runtime.shared.hud.localHostDidEndLifetime(identifier: identifier, lifetimeIdentifier: lifetime)
            }
            return state
        }
    }

    private func state(containing identifier: UUID) -> HUDHostState? {
        if globalState.entries[identifier] != nil {
            return globalState
        }
        return localStates.values.first { $0.entries[identifier] != nil }
    }

    private func state(for key: HostKey) -> HUDHostState? {
        switch key {
        case .global:
            return globalState
        case .view(let identifier):
            return localStates[identifier]
        }
    }

    private func installOverlay(for state: HUDHostState) -> HUDView? {
        let hostView: UIView?
        switch state.key {
        case .global:
            guard let window = runtime.resolveGlobalWindow() else { return nil }
            state.attachedWindow = window
            hostView = window
        case .view:
            hostView = state.hostView
        }

        guard let hostView else { return nil }
        let overlay = state.overlay ?? HUDView()
        state.overlay = overlay

        switch state.key {
        case .global:
            overlay.localHostExitHandler = nil
        case .view(let identifier):
            let lifetimeIdentifier = state.lifetimeIdentifier
            overlay.localHostExitHandler = { [weak self] in
                self?.localHostDidEndLifetime(identifier: identifier, lifetimeIdentifier: lifetimeIdentifier)
            }
        }
        overlay.cancelHandler = { [weak self] identifier in
            self?.performCancel(identifier: identifier)
        }
        overlay.activeIdentifierProvider = { [weak self, weak state] in
            guard let self, let state else { return nil }
            return activeEntry(in: state)?.identifier
        }

        if overlay.superview !== hostView {
            overlay.removeFromSuperview()
            overlay.frame = hostView.bounds
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hostView.addSubview(overlay)
        } else {
            overlay.frame = hostView.bounds
        }
        hostView.bringSubviewToFront(overlay)
        // Toast 图层必须始终位于 HUD 之上，HUD blocking 不能挡住 Toast。
        runtime.toasts.bringLayerToFront(in: hostView)
        return overlay
    }

    private func cleanupReleasedLocalStates() {
        let released = localStates.compactMap { identifier, state in
            state.hostView == nil ? (identifier, state.lifetimeIdentifier) : nil
        }
        released.forEach { identifier, lifetime in
            localHostDidEndLifetime(identifier: identifier, lifetimeIdentifier: lifetime)
        }
    }

    private func removeLocalStateIfIdle(_ state: HUDHostState) {
        guard state.entries.isEmpty,
              state.overlay == nil,
              case .view(let identifier) = state.key else {
            return
        }
        localStates.removeValue(forKey: identifier)
    }
}

// MARK: - HUDHostState

/// 单个宿主的可变状态。
@MainActor
private final class HUDHostState {
    let key: HostKey
    let lifetimeIdentifier = UUID()
    weak var hostView: UIView?
    weak var attachedWindow: UIWindow?
    var overlay: HUDView?
    var entries: [UUID: HUDEntry] = [:]
    var presentationTask: Task<Void, Never>?
    var dismissalTask: Task<Void, Never>?
    var isContentVisible = false
    var visibleSince: TimeInterval?
    var lifecycleGeneration = 0
    var pendingDismissHandlers: [@MainActor () -> Void] = []

    init(key: HostKey, hostView: UIView?) {
        self.key = key
        self.hostView = hostView
    }
}
