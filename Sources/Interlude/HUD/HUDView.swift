import UIKit

/// HUD 覆盖层：负责面板渲染、出入场动画、触摸策略、无障碍与局部宿主退出观察。
///
/// 视图不持有业务状态，所有内容来自 `HUDSnapshot`；`RenderedMode` 等只读属性供 Coordinator 与测试观察。
@MainActor
final class HUDView: UIView {
    // MARK: - Types

    /// 当前实际渲染的模式。
    enum RenderedMode: Equatable {
        case pending
        case loading
        case progress(Double, Interlude.ProgressStyle)
        case text
        case custom
        case success
        case error
        case info
        case image
        case hidden
    }

    typealias LocalHostExitHandler = @MainActor () -> Void

    // MARK: - Public Properties

    private(set) var renderedMode: RenderedMode = .hidden
    private(set) var renderedText: String?
    private(set) var renderedDetail: String?
    private(set) var renderedProgress: Double?
    private(set) var displayedPercentage: String?
    private(set) var resultImage: UIImage?
    private(set) var theme: Interlude.Theme = .dark

    /// 局部宿主页面完成 pop / dismiss 后执行的清理；全局 HUD 保持 nil。
    var localHostExitHandler: LocalHostExitHandler?

    /// 取消按钮点击后回调当前显示条目的标识。
    var cancelHandler: (@MainActor (UUID) -> Void)?

    /// 由 Coordinator 提供当前显示条目的标识。
    var activeIdentifierProvider: (@MainActor () -> UUID?)?

    var isPanelVisible: Bool {
        panel.alpha > 0.01
    }

    var isCancelButtonVisible: Bool {
        !cancelButton.isHidden
    }

    var panelCornerRadius: CGFloat {
        panel.layer.cornerRadius
    }

    var panelEffect: UIVisualEffect? {
        panel.effect
    }

    var customContentView: UIView? {
        customContainer.subviews.first
    }

    // MARK: - Private Properties

    private var hostExitObservationGeneration = 0
    private var panelCenterXConstraint: NSLayoutConstraint?
    private var panelCenterYConstraint: NSLayoutConstraint?
    private var panelMaxWidthConstraint: NSLayoutConstraint?
    private var panelMinWidthConstraint: NSLayoutConstraint?
    private var panelMinHeightConstraint: NSLayoutConstraint?
    private var stackTopConstraint: NSLayoutConstraint?
    private var stackBottomConstraint: NSLayoutConstraint?
    private var stackLeadingConstraint: NSLayoutConstraint?
    private var stackTrailingConstraint: NSLayoutConstraint?
    private var indicatorWidthConstraint: NSLayoutConstraint?
    private var indicatorHeightConstraint: NSLayoutConstraint?
    /// 进度条比指示器宽，bar 模式下把容器撑到进度条宽度。
    private var barWidthConstraint: NSLayoutConstraint?
    private var customSizeConstraints: [NSLayoutConstraint] = []

    private let percentageFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    // MARK: - Views

    private lazy var panel: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: nil)
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        return stack
    }()

    private lazy var indicatorContainer: UIView = {
        let view = UIView()
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = false
        indicator.isAccessibilityElement = false
        return indicator
    }()

    private lazy var ringView = RingProgressView()

    private lazy var barView = BarProgressView()

    private lazy var resultImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(weight: .regular)
        imageView.isAccessibilityElement = false
        return imageView
    }()

    private lazy var customContainer: UIView = {
        let view = UIView()
        view.isAccessibilityElement = false
        return view
    }()

    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.isAccessibilityElement = false
        return label
    }()

    private lazy var detailLabel: UILabel = {
        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.isAccessibilityElement = false
        return label
    }()

    private lazy var cancelButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupConstraints()
        setupAccessibilityNotifications()
        applyTheme(theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        hostExitObservationGeneration &+= 1

        guard newWindow == nil,
              localHostExitHandler != nil,
              let owner = owningViewController,
              isControllerHierarchyExiting(owner) else {
            return
        }

        let generation = hostExitObservationGeneration
        if let coordinator = owner.transitionCoordinator {
            let registered = coordinator.animate(alongsideTransition: nil) { [weak self] context in
                self?.completeHostExitObservation(generation: generation, transitionWasCancelled: context.isCancelled)
            }
            if registered {
                return
            }
        }

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.completeHostExitObservation(generation: generation, transitionWasCancelled: false)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard renderedMode != .hidden else { return }
        applyBackgroundStyle()
    }

    // MARK: - Public Methods

    /// grace 等待期：面板透明但已按策略拦截触摸。
    func prepareForPendingPresentation(interaction: Interlude.Interaction, theme: Interlude.Theme) {
        cancelVisualAnimations()
        applyTheme(theme)
        resetIndicators()

        renderedMode = .pending
        renderedText = nil
        renderedDetail = nil
        renderedProgress = nil
        displayedPercentage = nil
        resultImage = nil

        isUserInteractionEnabled = interaction.blocksTouches
        clearAccessibility()
        backgroundColor = .clear
        panel.alpha = 0
    }

    /// 渲染快照；`animated` 只影响从不可见到可见的过程以及进度过渡。
    func render(_ snapshot: HUDSnapshot, animated: Bool) {
        let previousMode = renderedMode
        let previousText = renderedText
        let shouldReveal = previousMode == .pending || previousMode == .hidden

        cancelVisualAnimations()
        applyTheme(snapshot.theme)

        let keepsProgress = if case .progress = previousMode, case .progress = snapshot.mode {
            true
        } else {
            false
        }
        resetIndicators(resetProgress: !keepsProgress)

        applyVisibleInteraction(snapshot.interaction)
        updateText(snapshot.text)
        updateDetail(snapshot.detail)
        updateCancelButton(title: snapshot.cancelTitle)

        switch snapshot.mode {
        case .loading:
            renderLoading(text: snapshot.text, previousMode: previousMode, previousText: previousText)
        case let .progress(value, style):
            renderProgress(
                value,
                style: style,
                text: snapshot.text,
                animated: animated,
                previousMode: previousMode,
                previousText: previousText
            )
        case .text:
            renderTextOnly(text: snapshot.text)
        case let .custom(view):
            renderCustom(view, text: snapshot.text)
        case let .result(result):
            renderResult(result)
        }

        renderedText = snapshot.text
        renderedDetail = snapshot.detail
        revealPanel(animated: animated && shouldReveal)
    }

    /// 淡出面板并在结束后回调。
    func hide(animated: Bool, completion: @escaping @MainActor () -> Void) {
        cancelVisualAnimations()
        isUserInteractionEnabled = false
        clearAccessibility()
        renderedMode = .hidden
        renderedText = nil
        renderedDetail = nil
        renderedProgress = nil
        displayedPercentage = nil
        resultImage = nil

        let animation = effectiveAnimation
        guard animated, animation != .none, isPanelVisible else {
            backgroundColor = .clear
            panel.alpha = 0
            panel.transform = .identity
            completion()
            return
        }

        UIView.animate(
            withDuration: theme.animationDuration,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState],
            animations: {
                self.backgroundColor = .clear
                self.panel.alpha = 0
                self.panel.transform = animation.disappearingTransform
            },
            completion: { _ in
                self.panel.transform = .identity
                completion()
            }
        )
    }

    /// 判断转场完成后是否应清理局部宿主。
    static func shouldCleanupLocalHostAfterTransition(transitionWasCancelled: Bool, isAttachedToWindow: Bool) -> Bool {
        !transitionWasCancelled && !isAttachedToWindow
    }

    // MARK: - View Setup

    private func setupViews() {
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        addSubview(panel)
        panel.contentView.addSubview(contentStack)
        contentStack.addArrangedSubview(indicatorContainer)
        contentStack.addArrangedSubview(customContainer)
        contentStack.addArrangedSubview(textLabel)
        contentStack.addArrangedSubview(detailLabel)
        contentStack.addArrangedSubview(cancelButton)

        for view in [activityIndicator, ringView, barView, resultImageView] {
            indicatorContainer.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isAccessibilityElement = false
            view.accessibilityElementsHidden = true
        }
        panel.alpha = 0
        resetIndicators()
    }

    private func setupConstraints() {
        panel.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        indicatorContainer.translatesAutoresizingMaskIntoConstraints = false

        let centerX = panel.centerXAnchor.constraint(equalTo: centerXAnchor)
        let centerY = panel.centerYAnchor.constraint(equalTo: centerYAnchor)
        let maxWidth = panel.widthAnchor.constraint(lessThanOrEqualToConstant: theme.maximumWidth)
        let minWidth = panel.widthAnchor.constraint(greaterThanOrEqualToConstant: theme.minimumSize.width)
        let minHeight = panel.heightAnchor.constraint(greaterThanOrEqualToConstant: theme.minimumSize.height)
        panelCenterXConstraint = centerX
        panelCenterYConstraint = centerY
        panelMaxWidthConstraint = maxWidth
        panelMinWidthConstraint = minWidth
        panelMinHeightConstraint = minHeight

        let stackTop = contentStack.topAnchor.constraint(equalTo: panel.contentView.topAnchor)
        let stackBottom = panel.contentView.bottomAnchor.constraint(equalTo: contentStack.bottomAnchor)
        let stackLeading = contentStack.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor)
        let stackTrailing = panel.contentView.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor)
        stackTopConstraint = stackTop
        stackBottomConstraint = stackBottom
        stackLeadingConstraint = stackLeading
        stackTrailingConstraint = stackTrailing

        let indicatorWidth = indicatorContainer.widthAnchor.constraint(equalToConstant: theme.indicatorSize)
        indicatorWidth.priority = .defaultHigh
        let indicatorHeight = indicatorContainer.heightAnchor.constraint(equalToConstant: theme.indicatorSize)
        indicatorWidthConstraint = indicatorWidth
        indicatorHeightConstraint = indicatorHeight
        barWidthConstraint = indicatorContainer.widthAnchor.constraint(greaterThanOrEqualTo: barView.widthAnchor)

        NSLayoutConstraint.activate([
            centerX, centerY, maxWidth, minWidth, minHeight,
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            trailingAnchor.constraint(greaterThanOrEqualTo: panel.trailingAnchor, constant: 32),
            stackTop, stackBottom, stackLeading, stackTrailing,
            indicatorWidth, indicatorHeight
        ])

        for view in [activityIndicator, ringView, resultImageView] {
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: indicatorContainer.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: indicatorContainer.centerYAnchor),
                view.widthAnchor.constraint(equalTo: indicatorContainer.widthAnchor),
                view.heightAnchor.constraint(equalTo: indicatorContainer.heightAnchor)
            ])
        }
        // 进度条比指示器宽，只在垂直方向居中于容器。
        NSLayoutConstraint.activate([
            barView.centerXAnchor.constraint(equalTo: indicatorContainer.centerXAnchor),
            barView.centerYAnchor.constraint(equalTo: indicatorContainer.centerYAnchor)
        ])
    }

    private func setupAccessibilityNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceTransparencyStatusDidChange),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
    }

    // MARK: - Actions

    @objc
    private func cancelButtonTapped() {
        guard let identifier = activeIdentifierProvider?() else { return }
        cancelHandler?(identifier)
    }

    @objc
    private func reduceTransparencyStatusDidChange() {
        applyBackgroundStyle()
    }

    // MARK: - Private Methods

    private func applyTheme(_ theme: Interlude.Theme) {
        self.theme = theme
        panel.layer.cornerRadius = theme.cornerRadius
        panelCenterXConstraint?.constant = theme.offset.horizontal
        panelCenterYConstraint?.constant = theme.offset.vertical
        panelMaxWidthConstraint?.constant = theme.maximumWidth
        panelMinWidthConstraint?.constant = theme.minimumSize.width
        panelMinHeightConstraint?.constant = theme.minimumSize.height
        stackTopConstraint?.constant = theme.contentInsets.top
        stackBottomConstraint?.constant = theme.contentInsets.bottom
        stackLeadingConstraint?.constant = theme.contentInsets.leading
        stackTrailingConstraint?.constant = theme.contentInsets.trailing
        contentStack.spacing = theme.spacing
        indicatorWidthConstraint?.constant = theme.indicatorSize
        indicatorHeightConstraint?.constant = theme.indicatorSize

        activityIndicator.color = theme.indicatorColor
        ringView.lineWidth = theme.ringLineWidth
        ringView.trackColor = theme.trackColor
        ringView.progressColor = theme.indicatorColor
        barView.trackColor = theme.trackColor
        barView.progressColor = theme.indicatorColor
        textLabel.font = theme.textFont
        textLabel.textColor = theme.foregroundColor
        detailLabel.font = theme.detailFont
        detailLabel.textColor = theme.secondaryForegroundColor
        cancelButton.tintColor = theme.foregroundColor
        applyBackgroundStyle()
    }

    private func applyBackgroundStyle() {
        if UIAccessibility.isReduceTransparencyEnabled {
            panel.effect = nil
            panel.backgroundColor = theme.reduceTransparencyColor
            return
        }
        switch theme.background {
        case let .blur(style):
            panel.backgroundColor = .clear
            panel.effect = UIBlurEffect(style: style)
        case let .solid(color):
            panel.effect = nil
            panel.backgroundColor = color
        }
    }

    private var effectiveAnimation: Interlude.Animation {
        UIAccessibility.isReduceMotionEnabled ? .none : theme.animation
    }

    // MARK: 模式渲染

    private func renderLoading(text: String?, previousMode: RenderedMode, previousText: String?) {
        indicatorContainer.isHidden = false
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
        renderedMode = .loading
        renderedProgress = nil
        displayedPercentage = nil
        configureAccessibility(
            label: nonempty(text) ?? Runtime.shared.string(.loading),
            value: nil,
            traits: .staticText
        )
        if previousMode != .loading || previousText != text {
            postAnnouncement(accessibilityLabel)
        }
    }

    private func renderProgress(
        _ value: Double,
        style: Interlude.ProgressStyle,
        text: String?,
        animated: Bool,
        previousMode: RenderedMode,
        previousText: String?
    ) {
        let percentage = formattedPercentage(for: value)
        let animatesProgress = animated && effectiveAnimation != .none
        indicatorContainer.isHidden = false
        switch style {
        case .ring:
            ringView.isHidden = false
            ringView.setProgress(value, percentageText: percentage, animated: animatesProgress)
        case .bar:
            barView.isHidden = false
            barWidthConstraint?.isActive = true
            barView.setProgress(value, percentageText: percentage, animated: animatesProgress)
        }
        renderedMode = .progress(value, style)
        renderedProgress = value
        displayedPercentage = percentage
        configureAccessibility(
            label: nonempty(text) ?? Runtime.shared.string(.loading),
            value: percentage,
            traits: .updatesFrequently
        )

        let wasProgress = if case .progress = previousMode {
            true
        } else {
            false
        }
        if !wasProgress || previousText != text {
            postAnnouncement([accessibilityLabel, percentage].compactMap(\.self).joined(separator: ", "))
        }
    }

    private func renderTextOnly(text: String?) {
        indicatorContainer.isHidden = true
        renderedMode = .text
        renderedProgress = nil
        displayedPercentage = nil
        configureAccessibility(label: nonempty(text), value: nil, traits: .staticText)
        postAnnouncement(accessibilityLabel)
    }

    private func renderCustom(_ view: UIView, text: String?) {
        indicatorContainer.isHidden = true
        embedCustomView(view)
        renderedMode = .custom
        renderedProgress = nil
        displayedPercentage = nil
        configureAccessibility(
            label: nonempty(text) ?? Runtime.shared.string(.loading),
            value: nil,
            traits: .staticText
        )
        postAnnouncement(accessibilityLabel)
    }

    private func renderResult(_ result: Interlude.Result) {
        indicatorContainer.isHidden = false
        resultImageView.isHidden = false
        renderedProgress = nil
        displayedPercentage = nil

        let label: String
        switch result {
        case let .success(text):
            resultImageView.image = UIImage(systemName: "checkmark.circle.fill")
            resultImageView.tintColor = theme.successColor
            renderedMode = .success
            label = nonempty(text) ?? Runtime.shared.string(.success)
        case let .error(text):
            resultImageView.image = UIImage(systemName: "xmark.circle.fill")
            resultImageView.tintColor = theme.errorColor
            renderedMode = .error
            label = nonempty(text) ?? Runtime.shared.string(.error)
        case let .info(text):
            resultImageView.image = UIImage(systemName: "info.circle.fill")
            resultImageView.tintColor = theme.infoColor
            renderedMode = .info
            label = nonempty(text) ?? Runtime.shared.string(.info)
        case let .image(image, text):
            resultImageView.image = image
            resultImageView.tintColor = theme.foregroundColor
            renderedMode = .image
            label = nonempty(text) ?? Runtime.shared.string(.info)
        }
        resultImage = resultImageView.image
        configureAccessibility(label: label, value: nil, traits: .staticText)
        postAnnouncement(label)
    }

    private func embedCustomView(_ view: UIView) {
        if customContainer.subviews.first === view {
            customContainer.isHidden = false
            return
        }
        customContainer.subviews.forEach { $0.removeFromSuperview() }
        NSLayoutConstraint.deactivate(customSizeConstraints)
        customContainer.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false

        let intrinsic = view.intrinsicContentSize
        let width = intrinsic.width > 0 ? intrinsic.width : theme.indicatorSize
        let height = intrinsic.height > 0 ? intrinsic.height : theme.indicatorSize
        customSizeConstraints = [
            view.topAnchor.constraint(equalTo: customContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: customContainer.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: customContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: customContainer.trailingAnchor),
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height)
        ]
        NSLayoutConstraint.activate(customSizeConstraints)
        customContainer.isHidden = false
    }

    // MARK: 状态重置

    private func resetIndicators(resetProgress: Bool = true) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        ringView.isHidden = true
        barView.isHidden = true
        barWidthConstraint?.isActive = false
        if resetProgress {
            ringView.setProgress(0, percentageText: nil, animated: false)
            barView.setProgress(0, percentageText: nil, animated: false)
        }
        resultImageView.isHidden = true
        resultImageView.image = nil
        customContainer.isHidden = true
        indicatorContainer.isHidden = false
    }

    private func updateText(_ text: String?) {
        let hasText = nonempty(text) != nil
        textLabel.isHidden = !hasText
        textLabel.text = text
    }

    private func updateDetail(_ detail: String?) {
        let hasDetail = nonempty(detail) != nil
        detailLabel.isHidden = !hasDetail
        detailLabel.text = detail
    }

    private func updateCancelButton(title: String?) {
        guard let title = nonempty(title) else {
            cancelButton.isHidden = true
            return
        }
        cancelButton.isHidden = false
        var attributes = AttributeContainer()
        attributes.font = theme.buttonFont
        attributes.foregroundColor = theme.foregroundColor
        cancelButton.configuration?.attributedTitle = AttributedString(title, attributes: attributes)
    }

    private func cancelVisualAnimations() {
        layer.removeAllAnimations()
        panel.layer.removeAllAnimations()
    }

    // MARK: 动画

    private func revealPanel(animated: Bool) {
        let animation = effectiveAnimation
        guard animated, animation != .none else {
            backgroundColor = theme.dimmingColor
            panel.alpha = 1
            panel.transform = .identity
            return
        }

        backgroundColor = .clear
        panel.alpha = 0
        panel.transform = animation.appearingTransform
        UIView.animate(
            withDuration: theme.animationDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            self.backgroundColor = self.theme.dimmingColor
            self.panel.alpha = 1
            self.panel.transform = .identity
        }
    }

    // MARK: 无障碍

    private func applyVisibleInteraction(_ interaction: Interlude.Interaction) {
        isUserInteractionEnabled = interaction.blocksTouches
        isAccessibilityElement = true
        accessibilityElementsHidden = false
        accessibilityViewIsModal = interaction.blocksTouches
    }

    private func configureAccessibility(label: String?, value: String?, traits: UIAccessibilityTraits) {
        accessibilityLabel = label
        accessibilityValue = value
        accessibilityTraits = traits
    }

    private func clearAccessibility() {
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        accessibilityViewIsModal = false
        accessibilityLabel = nil
        accessibilityValue = nil
        accessibilityTraits = []
    }

    private func postAnnouncement(_ text: String?) {
        guard UIAccessibility.isVoiceOverRunning, let text = nonempty(text) else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func nonempty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private func formattedPercentage(for progress: Double) -> String {
        percentageFormatter.string(from: NSNumber(value: progress)) ?? "\(Int(progress * 100))%"
    }

    // MARK: 局部宿主退出观察

    private var owningViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }

    private func isControllerHierarchyExiting(_ owner: UIViewController) -> Bool {
        var current: UIViewController? = owner
        while let viewController = current {
            if viewController.isMovingFromParent || viewController.isBeingDismissed {
                return true
            }
            current = viewController.parent
        }
        return false
    }

    private func completeHostExitObservation(generation: Int, transitionWasCancelled: Bool) {
        guard hostExitObservationGeneration == generation,
              Self.shouldCleanupLocalHostAfterTransition(
                  transitionWasCancelled: transitionWasCancelled,
                  isAttachedToWindow: window != nil
              ) else {
            return
        }
        hostExitObservationGeneration &+= 1
        localHostExitHandler?()
    }
}

// MARK: - Interlude.Animation + Transforms

private extension Interlude.Animation {
    var appearingTransform: CGAffineTransform {
        switch self {
        case .fade, .none: return .identity
        case .zoom, .zoomOut: return CGAffineTransform(scaleX: 1.3, y: 1.3)
        case .zoomIn: return CGAffineTransform(scaleX: 0.7, y: 0.7)
        }
    }

    var disappearingTransform: CGAffineTransform {
        switch self {
        case .fade, .none: return .identity
        case .zoom, .zoomIn: return CGAffineTransform(scaleX: 0.7, y: 0.7)
        case .zoomOut: return CGAffineTransform(scaleX: 1.3, y: 1.3)
        }
    }
}
