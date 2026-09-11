import UIKit

/// 水平进度条：圆角轨道 + 填充，右侧显示本地化整数百分比。
@MainActor
final class BarProgressView: UIView {
    // MARK: - Types

    private enum Constants {
        static let barHeight: CGFloat = 10
        static let barWidth: CGFloat = 168
        static let spacing: CGFloat = 8
        static let percentageWidth: CGFloat = 48
        static let percentagePriority = UILayoutPriority(999)
    }

    // MARK: - Public Properties

    private(set) var progress: Double = 0

    var usesGradient: Bool {
        fillGradient.superlayer != nil
    }

    var trackColor: UIColor = .white.withAlphaComponent(0.25) {
        didSet { trackView.backgroundColor = trackColor }
    }

    var progressColor: UIColor = .white {
        didSet {
            if !usesGradient {
                fillView.backgroundColor = progressColor
            }
            percentageLabel.textColor = progressColor
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: Constants.barWidth + Constants.spacing + Constants.percentageWidth,
            height: max(Constants.barHeight, percentageLabel.intrinsicContentSize.height)
        )
    }

    // MARK: - Private Properties

    private var fillWidthConstraint: NSLayoutConstraint?
    private var storedGradientColors: [UIColor] = []

    // MARK: - Views

    private lazy var trackView: UIView = {
        let view = UIView()
        view.backgroundColor = trackColor
        view.layer.cornerRadius = Constants.barHeight / 2
        view.clipsToBounds = true
        view.isAccessibilityElement = false
        return view
    }()

    private lazy var fillView: UIView = {
        let view = UIView()
        view.backgroundColor = progressColor
        view.layer.cornerRadius = Constants.barHeight / 2
        view.clipsToBounds = true
        view.isAccessibilityElement = false
        return view
    }()

    private lazy var fillGradient: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        return layer
    }()

    private lazy var percentageLabel: UILabel = {
        let label = UILabel()
        let baseFont = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: baseFont, maximumPointSize: 18)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = progressColor
        label.textAlignment = .right
        label.setContentCompressionResistancePriority(Constants.percentagePriority, for: .horizontal)
        label.isAccessibilityElement = false
        return label
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFillWidth()
        trackView.layoutIfNeeded()
        fillGradient.frame = fillView.bounds
        fillGradient.cornerRadius = Constants.barHeight / 2
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if usesGradient {
            fillGradient.colors = storedGradientColors.map { $0.resolvedCGColor(for: traitCollection) }
        }
    }

    // MARK: - Public Methods

    func setProgress(_ progress: Double, percentageText: String?, animated: Bool) {
        let value = HUDMode.clampProgress(progress)
        percentageLabel.text = percentageText
        setNeedsLayout()
        layoutIfNeeded()
        self.progress = value
        updateFillWidth()

        guard animated else {
            trackView.layoutIfNeeded()
            fillGradient.frame = fillView.bounds
            return
        }
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.trackView.layoutIfNeeded()
            self.fillGradient.frame = self.fillView.bounds
        }
    }

    /// 双色及以上沿填充方向渐变；否则实心填充。
    func applyProgressAppearance(gradient: [UIColor], solid: UIColor) {
        storedGradientColors = gradient
        progressColor = solid
        if gradient.count >= 2 {
            fillView.backgroundColor = .clear
            fillGradient.colors = gradient.map { $0.resolvedCGColor(for: traitCollection) }
            if fillGradient.superlayer !== fillView.layer {
                fillView.layer.insertSublayer(fillGradient, at: 0)
            }
        } else {
            fillGradient.removeFromSuperlayer()
            fillView.backgroundColor = solid
        }
        setNeedsLayout()
    }

    /// 百分比标签是否获得了完整的内在宽度，供布局验收使用。
    func percentageLabelFits() -> Bool {
        layoutIfNeeded()
        return percentageLabel.bounds.width + 0.5 >= percentageLabel.intrinsicContentSize.width
    }

    /// 实际布局尺寸，避免测试只验证约束常量。
    var laidOutTrackWidth: CGFloat {
        layoutIfNeeded()
        return trackView.bounds.width
    }

    var laidOutFillWidth: CGFloat {
        layoutIfNeeded()
        return fillView.bounds.width
    }

    // MARK: - View Setup

    private func setupViews() {
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        addSubview(trackView)
        trackView.addSubview(fillView)
        addSubview(percentageLabel)
        trackView.translatesAutoresizingMaskIntoConstraints = false
        fillView.translatesAutoresizingMaskIntoConstraints = false
        percentageLabel.translatesAutoresizingMaskIntoConstraints = false

        let fillWidth = fillView.widthAnchor.constraint(equalToConstant: 0)
        fillWidthConstraint = fillWidth
        let preferredTrackWidth = trackView.widthAnchor.constraint(equalToConstant: Constants.barWidth)
        preferredTrackWidth.priority = .defaultHigh
        let percentageMinimumWidth = percentageLabel.widthAnchor.constraint(
            greaterThanOrEqualToConstant: Constants.percentageWidth
        )
        percentageMinimumWidth.priority = Constants.percentagePriority

        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            preferredTrackWidth,
            trackView.heightAnchor.constraint(equalToConstant: Constants.barHeight),

            fillView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
            fillView.topAnchor.constraint(equalTo: trackView.topAnchor),
            fillView.bottomAnchor.constraint(equalTo: trackView.bottomAnchor),
            fillWidth,

            percentageLabel.leadingAnchor.constraint(equalTo: trackView.trailingAnchor, constant: Constants.spacing),
            percentageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            percentageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentageMinimumWidth
        ])
    }

    // MARK: - Private Methods

    private func updateFillWidth() {
        fillWidthConstraint?.constant = trackView.bounds.width * CGFloat(progress)
    }
}
