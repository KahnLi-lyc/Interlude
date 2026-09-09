import UIKit

/// 圆环进度：轨道 + `strokeEnd` 前景，中心显示本地化整数百分比。
@MainActor
final class RingProgressView: UIView {
    // MARK: - Public Properties

    private(set) var progress: Double = 0

    var lineWidth: CGFloat = 3 {
        didSet {
            trackLayer.lineWidth = lineWidth
            progressLayer.lineWidth = lineWidth
            setNeedsLayout()
        }
    }

    var trackColor: UIColor = .white.withAlphaComponent(0.25) {
        didSet { trackLayer.strokeColor = trackColor.cgColor }
    }

    var progressColor: UIColor = .white {
        didSet {
            progressLayer.strokeColor = progressColor.cgColor
            percentageLabel.textColor = progressColor
        }
    }

    // MARK: - Views

    private lazy var trackLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = trackColor.cgColor
        layer.lineWidth = lineWidth
        return layer
    }()

    private lazy var progressLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = progressColor.cgColor
        layer.lineWidth = lineWidth
        layer.lineCap = .round
        layer.strokeEnd = 0
        return layer
    }()

    private lazy var percentageLabel: UILabel = {
        let label = UILabel()
        let baseFont = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        label.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont, maximumPointSize: 11)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = progressColor
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
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
        let inset = lineWidth
        let radius = (min(bounds.width, bounds.height) - inset * 2) / 2
        let path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: max(0, radius),
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        )
        trackLayer.frame = bounds
        progressLayer.frame = bounds
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // CGColor 不随动态颜色自动更新，界面风格变化后重新解析。
        trackLayer.strokeColor = trackColor.cgColor
        progressLayer.strokeColor = progressColor.cgColor
    }

    // MARK: - Public Methods

    /// 更新完成比例与中心文字。
    func setProgress(_ progress: Double, percentageText: String?, animated: Bool) {
        let value = HUDMode.clampProgress(progress)
        let currentStrokeEnd = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
        self.progress = value
        percentageLabel.text = percentageText

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = CGFloat(value)
        CATransaction.commit()

        progressLayer.removeAnimation(forKey: "strokeEnd")
        guard animated else { return }

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = currentStrokeEnd
        animation.toValue = value
        animation.duration = 0.15
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        progressLayer.add(animation, forKey: "strokeEnd")
    }

    // MARK: - View Setup

    private func setupViews() {
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        layer.addSublayer(trackLayer)
        layer.addSublayer(progressLayer)

        addSubview(percentageLabel)
        percentageLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            percentageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            percentageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            percentageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
