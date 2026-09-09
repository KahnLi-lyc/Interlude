import UIKit

/// Toast 子系统：按宿主与位置分组管理可见列表与队列，处理策略、手势、键盘避让与自动消失。
@MainActor
final class ToastPresenter {
    // MARK: - Private Properties

    private unowned let runtime: Runtime
    private let globalState = ToastHostState(key: .global, hostView: nil)
    private var localStates: [ObjectIdentifier: ToastHostState] = [:]
    private var keyboardFrame: CGRect = .null
    private var keyboardAnimationDuration: TimeInterval = 0.25
    private var isObservingKeyboard = false

    private var configuration: Interlude.Configuration {
        runtime.configuration
    }

    // MARK: - Initialization

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    // MARK: - Public Methods

    /// 展示一条 Toast 并返回句柄。
    func show(_ toast: Interlude.Toast, host: Host) -> Interlude.Toast.Handle {
        cleanupReleasedLocalStates()
        guard toast.hasContent else { return .inert }

        let state = state(for: host)
        guard let layer = installLayer(for: state) else { return .inert }
        startObservingKeyboardIfNeeded()

        let theme = toast.theme ?? runtime.theme
        let position = toast.position ?? configuration.toast.position
        let group = group(for: position, in: state, layer: layer, theme: theme)

        let entry = ToastEntry(
            identifier: toast.id,
            toast: toast,
            view: ToastView(toast: toast, theme: theme),
            duration: (toast.duration ?? configuration.toast.duration).timeInterval,
            position: position
        )
        configureGestures(for: entry, position: position)
        wireHandlers(for: entry)

        // 先展示新条目再淘汰旧条目，避免分组在中途因为空掉而被回收。
        switch configuration.toast.policy {
        case .replace:
            group.queue.removeAll()
            let previous = group.visible
            present(entry, in: state, group: group)
            previous.forEach { dismiss($0, in: state, group: group, didTap: false, animated: false) }
        case .queue:
            if group.visible.isEmpty {
                present(entry, in: state, group: group)
            } else {
                group.queue.append(entry)
            }
        case .stack(let maximum):
            present(entry, in: state, group: group)
            let limit = max(1, maximum)
            while group.visible.count > limit, let oldest = group.visible.first, oldest !== entry {
                dismiss(oldest, in: state, group: group, didTap: false, animated: true)
            }
        }
        return Interlude.Toast.Handle(identifier: toast.id)
    }

    func isVisible(identifier: UUID) -> Bool {
        locate(identifier) != nil
    }

    func performDismiss(identifier: UUID, didTap: Bool) {
        guard let (state, group, entry) = locate(identifier) else {
            removeFromQueues(identifier)
            return
        }
        dismiss(entry, in: state, group: group, didTap: didTap, animated: true)
    }

    func performDismissAll() {
        for state in [globalState] + Array(localStates.values) {
            for group in state.groups.values {
                group.queue.removeAll()
                group.visible.forEach { dismiss($0, in: state, group: group, didTap: false, animated: false) }
            }
        }
        localStates.removeAll()
    }

    /// HUD 覆盖层安装后调用，保证 Toast 图层始终位于 HUD 之上。
    func bringLayerToFront(in hostView: UIView) {
        let layer: PassthroughLayerView?
        if hostView === globalState.layer?.superview {
            layer = globalState.layer
        } else {
            layer = localStates[ObjectIdentifier(hostView)]?.layer
        }
        guard let layer, layer.superview === hostView else { return }
        hostView.bringSubviewToFront(layer)
    }

    func localHostDidEndLifetime(identifier: ObjectIdentifier, lifetimeIdentifier: UUID) {
        guard let state = localStates[identifier],
              state.lifetimeIdentifier == lifetimeIdentifier else {
            return
        }
        for group in state.groups.values {
            group.queue.removeAll()
            group.visible.forEach { dismiss($0, in: state, group: group, didTap: false, animated: false) }
        }
        localStates.removeValue(forKey: identifier)
    }

    func resetForTesting() {
        performDismissAll()
        globalState.layer?.removeFromSuperview()
        globalState.layer = nil
        globalState.groups.removeAll()
        keyboardFrame = .null
    }

    /// 当前可见的 Toast 视图（按显示顺序）。
    func visibleViews(for host: Host, position: Interlude.Toast.Position? = nil) -> [ToastView] {
        guard let state = existingState(for: host) else { return [] }
        let groups = position.map { [state.groups[$0]].compactMap { $0 } } ?? Array(state.groups.values)
        return groups.flatMap { $0.visible.map(\.view) }
    }

    func queuedCount(for host: Host) -> Int {
        existingState(for: host)?.groups.values.reduce(0) { $0 + $1.queue.count } ?? 0
    }

    func layerView(for host: Host) -> PassthroughLayerView? {
        existingState(for: host)?.layer
    }

    // MARK: - Private Methods

    private func present(_ entry: ToastEntry, in state: ToastHostState, group: ToastGroup) {
        group.visible.append(entry)
        let view = entry.view
        view.isHidden = true
        view.alpha = 0
        group.stack.addArrangedSubview(view)
        if let layer = state.layer {
            view.widthAnchor.constraint(
                lessThanOrEqualTo: layer.widthAnchor,
                multiplier: view.theme.toast.maximumWidthRatio
            ).isActive = true
        }

        let animated = !UIAccessibility.isReduceMotionEnabled
        let offset = entranceOffset(for: entry.position)
        view.transform = animated ? CGAffineTransform(translationX: offset.x, y: offset.y) : .identity
        UIView.animate(
            withDuration: animated ? view.theme.toast.animationDuration : 0,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            view.isHidden = false
            view.alpha = 1
            view.transform = .identity
            group.stack.layoutIfNeeded()
        }

        announce(entry.toast)
        scheduleAutoDismiss(for: entry, in: state, group: group)
    }

    private func dismiss(_ entry: ToastEntry, in state: ToastHostState, group: ToastGroup, didTap: Bool, animated: Bool) {
        guard let index = group.visible.firstIndex(where: { $0.identifier == entry.identifier }) else { return }
        group.visible.remove(at: index)
        entry.dismissTask?.cancel()
        entry.dismissTask = nil

        let view = entry.view
        view.isUserInteractionEnabled = false
        let finish: @MainActor () -> Void = { [weak self] in
            view.removeFromSuperview()
            entry.toast.completion?(didTap)
            self?.presentNextIfNeeded(in: state, group: group)
        }

        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            view.isHidden = true
            finish()
            return
        }
        UIView.animate(
            withDuration: view.theme.toast.animationDuration,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState],
            animations: {
                view.alpha = 0
                view.isHidden = true
                group.stack.layoutIfNeeded()
            },
            completion: { _ in
                finish()
            }
        )
    }

    private func presentNextIfNeeded(in state: ToastHostState, group: ToastGroup) {
        if group.visible.isEmpty, !group.queue.isEmpty {
            let next = group.queue.removeFirst()
            present(next, in: state, group: group)
            return
        }
        guard group.visible.isEmpty, group.queue.isEmpty else { return }
        group.stack.removeFromSuperview()
        state.groups.removeValue(forKey: group.position)

        guard state.groups.isEmpty else { return }
        state.layer?.removeFromSuperview()
        state.layer = nil
        if case .view(let identifier) = state.key {
            localStates.removeValue(forKey: identifier)
        }
    }

    private func scheduleAutoDismiss(for entry: ToastEntry, in state: ToastHostState, group: ToastGroup) {
        guard let duration = entry.duration else { return }
        entry.dismissTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await runtime.clock.sleep(for: duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            dismiss(entry, in: state, group: group, didTap: false, animated: true)
        }
    }

    private func configureGestures(for entry: ToastEntry, position: Interlude.Toast.Position) {
        let swipeDirections: [UISwipeGestureRecognizer.Direction]
        switch position {
        case .top: swipeDirections = [.up]
        case .bottom: swipeDirections = [.down]
        case .center, .point: swipeDirections = [.up, .down]
        }
        entry.view.configureGestures(
            tapToDismiss: configuration.toast.isTapToDismissEnabled,
            swipeDirections: configuration.toast.isSwipeToDismissEnabled ? swipeDirections : []
        )
    }

    private func wireHandlers(for entry: ToastEntry) {
        let identifier = entry.identifier
        entry.view.tapHandler = { [weak self] in
            self?.performDismiss(identifier: identifier, didTap: true)
        }
        entry.view.swipeHandler = { [weak self] in
            self?.performDismiss(identifier: identifier, didTap: false)
        }
        entry.view.actionHandler = { [weak self] in
            entry.toast.action?.handler()
            self?.performDismiss(identifier: identifier, didTap: true)
        }
    }

    private func announce(_ toast: Interlude.Toast) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let text = [toast.title, toast.message].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        guard !text.isEmpty else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func entranceOffset(for position: Interlude.Toast.Position) -> CGPoint {
        switch position {
        case .top: return CGPoint(x: 0, y: -12)
        case .bottom: return CGPoint(x: 0, y: 12)
        case .center, .point: return .zero
        }
    }

    // MARK: 宿主与图层

    private func state(for host: Host) -> ToastHostState {
        switch host {
        case .global:
            return globalState
        case .view(let view):
            let identifier = ObjectIdentifier(view)
            if let state = localStates[identifier] {
                return state
            }
            let state = ToastHostState(key: .view(identifier), hostView: view)
            localStates[identifier] = state
            HostLifetime.install(on: view, slot: .toast, lifetimeIdentifier: state.lifetimeIdentifier) { identifier, lifetime in
                Runtime.shared.toasts.localHostDidEndLifetime(identifier: identifier, lifetimeIdentifier: lifetime)
            }
            return state
        }
    }

    private func existingState(for host: Host) -> ToastHostState? {
        switch host {
        case .global:
            return globalState
        case .view(let view):
            return localStates[ObjectIdentifier(view)]
        }
    }

    private func installLayer(for state: ToastHostState) -> PassthroughLayerView? {
        let hostView: UIView?
        switch state.key {
        case .global:
            hostView = runtime.resolveGlobalWindow()
        case .view:
            hostView = state.hostView
        }
        guard let hostView else { return nil }

        let layer = state.layer ?? PassthroughLayerView()
        state.layer = layer
        if layer.superview !== hostView {
            layer.removeFromSuperview()
            layer.frame = hostView.bounds
            layer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hostView.addSubview(layer)
        }
        hostView.bringSubviewToFront(layer)
        return layer
    }

    private func group(
        for position: Interlude.Toast.Position,
        in state: ToastHostState,
        layer: PassthroughLayerView,
        theme: Interlude.Theme
    ) -> ToastGroup {
        if let group = state.groups[position] {
            return group
        }
        let inset = theme.toast.edgeInset
        let group = ToastGroup(position: position, spacing: theme.toast.spacing, edgeInset: inset)
        state.groups[position] = group

        let stack = group.stack
        layer.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let guide = layer.safeAreaLayoutGuide
        var constraints = [
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: layer.leadingAnchor, constant: inset),
            layer.trailingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: inset)
        ]
        switch position {
        case .top:
            constraints += [
                stack.centerXAnchor.constraint(equalTo: layer.centerXAnchor),
                stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: inset)
            ]
        case .center:
            constraints += [
                stack.centerXAnchor.constraint(equalTo: layer.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: layer.centerYAnchor)
            ]
        case .bottom:
            let bottom = guide.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: inset + keyboardInset(for: state))
            group.bottomConstraint = bottom
            constraints += [
                stack.centerXAnchor.constraint(equalTo: layer.centerXAnchor),
                bottom
            ]
        case .point(let point):
            constraints += [
                stack.centerXAnchor.constraint(equalTo: layer.leadingAnchor, constant: point.x),
                stack.centerYAnchor.constraint(equalTo: layer.topAnchor, constant: point.y)
            ]
        }
        NSLayoutConstraint.activate(constraints)
        return group
    }

    private func cleanupReleasedLocalStates() {
        let released = localStates.compactMap { identifier, state in
            state.hostView == nil ? (identifier, state.lifetimeIdentifier) : nil
        }
        released.forEach { identifier, lifetime in
            localHostDidEndLifetime(identifier: identifier, lifetimeIdentifier: lifetime)
        }
    }

    private func locate(_ identifier: UUID) -> (ToastHostState, ToastGroup, ToastEntry)? {
        for state in [globalState] + Array(localStates.values) {
            for group in state.groups.values {
                if let entry = group.visible.first(where: { $0.identifier == identifier }) {
                    return (state, group, entry)
                }
            }
        }
        return nil
    }

    private func removeFromQueues(_ identifier: UUID) {
        for state in [globalState] + Array(localStates.values) {
            for group in state.groups.values {
                guard let index = group.queue.firstIndex(where: { $0.identifier == identifier }) else { continue }
                let entry = group.queue.remove(at: index)
                entry.toast.completion?(false)
                presentNextIfNeeded(in: state, group: group)
                return
            }
        }
    }

    // MARK: 键盘避让

    private func startObservingKeyboardIfNeeded() {
        guard !isObservingKeyboard else { return }
        isObservingKeyboard = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc
    private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        keyboardAnimationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        keyboardFrame = frame
        updateKeyboardInsets()
    }

    @objc
    private func keyboardWillHide(_ notification: Notification) {
        keyboardAnimationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        keyboardFrame = .null
        updateKeyboardInsets()
    }

    private func keyboardInset(for state: ToastHostState) -> CGFloat {
        guard configuration.toast.avoidsKeyboard,
              state.key == .global,
              !keyboardFrame.isNull,
              let layer = state.layer,
              let window = layer.window else {
            return 0
        }
        let keyboardInLayer = layer.convert(keyboardFrame, from: window.screen.coordinateSpace)
        let overlap = layer.bounds.maxY - keyboardInLayer.minY
        // 键盘已经盖过安全区的部分不需要再补偿。
        return max(0, overlap - layer.safeAreaInsets.bottom)
    }

    private func updateKeyboardInsets() {
        guard let group = globalState.groups[.bottom], let bottom = group.bottomConstraint else { return }
        bottom.constant = group.edgeInset + keyboardInset(for: globalState)
        let layer = globalState.layer
        UIView.animate(withDuration: keyboardAnimationDuration, delay: 0, options: [.beginFromCurrentState]) {
            layer?.layoutIfNeeded()
        }
    }
}

// MARK: - ToastHostState

@MainActor
private final class ToastHostState {
    let key: HostKey
    let lifetimeIdentifier = UUID()
    weak var hostView: UIView?
    var layer: PassthroughLayerView?
    var groups: [Interlude.Toast.Position: ToastGroup] = [:]

    init(key: HostKey, hostView: UIView?) {
        self.key = key
        self.hostView = hostView
    }
}

// MARK: - ToastGroup

/// 同一宿主、同一位置的可见列表与等待队列。
@MainActor
private final class ToastGroup {
    let position: Interlude.Toast.Position
    let edgeInset: CGFloat
    let stack: UIStackView
    var visible: [ToastEntry] = []
    var queue: [ToastEntry] = []
    var bottomConstraint: NSLayoutConstraint?

    init(position: Interlude.Toast.Position, spacing: CGFloat, edgeInset: CGFloat) {
        self.position = position
        self.edgeInset = edgeInset
        stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = spacing
    }
}

// MARK: - ToastEntry

@MainActor
private final class ToastEntry {
    let identifier: UUID
    let toast: Interlude.Toast
    let view: ToastView
    let duration: TimeInterval?
    let position: Interlude.Toast.Position
    var dismissTask: Task<Void, Never>?

    init(identifier: UUID, toast: Interlude.Toast, view: ToastView, duration: TimeInterval?, position: Interlude.Toast.Position) {
        self.identifier = identifier
        self.toast = toast
        self.view = view
        self.duration = duration
        self.position = position
    }
}
