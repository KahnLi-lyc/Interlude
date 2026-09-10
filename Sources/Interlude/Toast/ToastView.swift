import UIKit

/// 单条 Toast 的视图：图标 + 标题 / 正文 + 可选按钮，或调用方的自定义视图。
@MainActor
final class ToastView: UIView {
    // MARK: - Public Properties

    let toast: Interlude.Toast
    let theme: Interlude.Theme
    /// `toast.animation` 与主题默认值合并后的结果，尚未按位置解析 `.automatic`。
    let resolvedAnimation: Interlude.Toast.Animation

    /// 点按整体（不含按钮）时回调。
    var tapHandler: (@MainActor () -> Void)?

    /// 沿允许方向滑动时回调。
    var swipeHandler: (@MainActor () -> Void)?

    /// 点击 action 按钮时回调。
    var actionHandler: (@MainActor () -> Void)?

    var isActionButtonVisible: Bool {
        toast.customView == nil && toast.action != nil
    }

    // MARK: - Private Properties

    private var swipeRecognizers: [UISwipeGestureRecognizer] = []

    // MARK: - Views

    private lazy var effectView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: nil)
        view.clipsToBounds = true
        view.layer.cornerRadius = theme.toast.cornerRadius
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = theme.toast.spacing
        return stack
    }()

    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = theme.toast.foregroundColor
        imageView.isAccessibilityElement = false
        return imageView
    }()

    private lazy var textStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = theme.toast.titleFont
        label.textColor = theme.toast.foregroundColor
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 2
        label.isAccessibilityElement = false
        return label
    }()

    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.font = theme.toast.messageFont
        label.textColor = theme.toast.foregroundColor
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 4
        label.isAccessibilityElement = false
        return label
    }()

    private lazy var actionButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 0)
        let button = UIButton(configuration: configuration)
        button.tintColor = theme.toast.actionTintColor
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        recognizer.delegate = self
        recognizer.isEnabled = false
        return recognizer
    }()

    // MARK: - Initialization

    init(toast: Interlude.Toast, theme: Interlude.Theme, animation: Interlude.Toast.Animation) {
        self.toast = toast
        self.theme = theme
        resolvedAnimation = animation
        super.init(frame: .zero)
        setupViews()
        setupConstraints()
        setupContent()
        setupAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func layoutSubviews() {
        super.layoutSubviews()
        if theme.toast.shadow != nil {
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: theme.toast.cornerRadius).cgPath
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyBackgroundStyle()
    }

    // MARK: - Public Methods

    /// 按配置启用点按与滑动手势。
    func configureGestures(tapToDismiss: Bool, swipeDirections: [UISwipeGestureRecognizer.Direction]) {
        tapRecognizer.isEnabled = tapToDismiss
        swipeRecognizers.forEach(removeGestureRecognizer)
        swipeRecognizers = swipeDirections.map { direction in
            let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
            recognizer.direction = direction
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
            return recognizer
        }
    }

    // MARK: - View Setup

    private func setupViews() {
        backgroundColor = .clear
        addSubview(effectView)
        addGestureRecognizer(tapRecognizer)

        if let shadow = theme.toast.shadow {
            layer.shadowColor = shadow.color.cgColor
            layer.shadowOpacity = shadow.opacity
            layer.shadowRadius = shadow.radius
            layer.shadowOffset = shadow.offset
        }
        applyBackgroundStyle()
    }

    private func setupConstraints() {
        effectView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func setupContent() {
        let insets = theme.toast.contentInsets
        if let customView = toast.customView {
            effectView.contentView.addSubview(customView)
            customView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                customView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
                customView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
                customView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
                customView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor)
            ])
            return
        }

        effectView.contentView.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: effectView.contentView.topAnchor, constant: insets.top),
            effectView.contentView.bottomAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: insets.bottom),
            contentStack.leadingAnchor.constraint(
                equalTo: effectView.contentView.leadingAnchor,
                constant: insets.leading
            ),
            effectView.contentView.trailingAnchor.constraint(
                equalTo: contentStack.trailingAnchor,
                constant: insets.trailing
            )
        ])

        if let image = iconImage(for: toast.icon) {
            iconImageView.image = image
            iconImageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconImageView.widthAnchor.constraint(equalToConstant: theme.toast.iconSize),
                iconImageView.heightAnchor.constraint(equalToConstant: theme.toast.iconSize)
            ])
            contentStack.addArrangedSubview(iconImageView)
        }

        contentStack.addArrangedSubview(textStack)
        if let title = toast.title, !title.isEmpty {
            titleLabel.text = title
            textStack.addArrangedSubview(titleLabel)
        }
        if let message = toast.message, !message.isEmpty {
            messageLabel.text = message
            textStack.addArrangedSubview(messageLabel)
        }
        if toast.title == nil || toast.message == nil {
            // 只有一行文字时居中对齐更自然。
            titleLabel.textAlignment = toast.icon.isNone && toast.action == nil ? .center : .natural
            messageLabel.textAlignment = titleLabel.textAlignment
            textStack.alignment = titleLabel.textAlignment == .center ? .center : .leading
        }

        if let action = toast.action {
            var attributes = AttributeContainer()
            attributes.font = theme.toast.actionFont
            attributes.foregroundColor = theme.toast.actionTintColor
            actionButton.configuration?.attributedTitle = AttributedString(action.title, attributes: attributes)
            contentStack.addArrangedSubview(actionButton)
        }
    }

    private func setupAccessibility() {
        let label = [toast.title, toast.message].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: ", ")
        if isActionButtonVisible {
            isAccessibilityElement = false
            textStack.isAccessibilityElement = true
            textStack.accessibilityLabel = label
            textStack.accessibilityTraits = .staticText
            actionButton.accessibilityLabel = toast.action?.title
            accessibilityElements = [textStack, actionButton]
        } else if toast.customView == nil {
            isAccessibilityElement = true
            accessibilityLabel = label
            accessibilityTraits = .staticText
        }
    }

    // MARK: - Actions

    @objc
    private func handleTap() {
        tapHandler?()
    }

    @objc
    private func handleSwipe() {
        swipeHandler?()
    }

    @objc
    private func actionButtonTapped() {
        actionHandler?()
    }

    // MARK: - Private Methods

    private func applyBackgroundStyle() {
        if UIAccessibility.isReduceTransparencyEnabled {
            effectView.effect = nil
            effectView.backgroundColor = theme.toast.reduceTransparencyColor
            return
        }
        switch theme.toast.background {
        case let .blur(style):
            effectView.backgroundColor = .clear
            effectView.effect = UIBlurEffect(style: style)
        case let .solid(color):
            effectView.effect = nil
            effectView.backgroundColor = color
        }
    }

    private func iconImage(for icon: Interlude.Toast.Icon) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(weight: .semibold)
        switch icon {
        case .none:
            return nil
        case .success:
            iconImageView.tintColor = theme.successColor
            return UIImage(systemName: "checkmark.circle.fill", withConfiguration: configuration)
        case .error:
            iconImageView.tintColor = theme.errorColor
            return UIImage(systemName: "xmark.circle.fill", withConfiguration: configuration)
        case .info:
            iconImageView.tintColor = theme.infoColor
            return UIImage(systemName: "info.circle.fill", withConfiguration: configuration)
        case .warning:
            iconImageView.tintColor = .systemOrange
            return UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: configuration)
        case let .system(name):
            return UIImage(systemName: name, withConfiguration: configuration)
        case let .image(image):
            return image
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ToastView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // 按钮自己处理点击，不让整体点按手势抢走。
        guard isActionButtonVisible, let touchedView = touch.view else { return true }
        return !touchedView.isDescendant(of: actionButton)
    }
}

private extension Interlude.Toast.Icon {
    var isNone: Bool {
        if case .none = self { return true }
        return false
    }
}
