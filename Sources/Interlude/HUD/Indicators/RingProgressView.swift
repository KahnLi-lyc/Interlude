import UIKit

/// 圆环进度：轨道 + `strokeEnd` 前景，中心显示本地化整数百分比。
@MainActor
final class RingProgressView: UIView {
    // MARK: - Types

    private enum Constants {
        static let animationDuration: TimeInterval = 0.15
        static let strokeAnimationKey = "strokeEnd"
        static let locationsAnimationKey = "locations"
    }

    // MARK: - Public Properties

    private(set) var progress: Double = 0

    var usesGradient: Bool {
        !gradientLayer.isHidden
    }

    /// 当前渐变 `locations`，供验收读取。
    var gradientLocations: [Double] {
        gradientLayer.locations?.map(\.doubleValue) ?? []
    }

    /// 当前渐变颜色，供验收读取。
    var gradientColors: [CGColor] {
        (gradientLayer.colors as? [CGColor]) ?? []
    }

    /// 描边中心线半径：四周留一个 lineWidth，描边外缘距边 lineWidth / 2。
    var ringRadius: CGFloat {
        max(0, (min(bounds.width, bounds.height) - lineWidth * 2) / 2)
    }

    var lineWidth: CGFloat = 8 {
        didSet {
            trackLayer.lineWidth = lineWidth
            progressLayer.lineWidth = lineWidth
            updateLabelInsets()
            setNeedsLayout()
        }
    }

    var trackColor: UIColor = .white.withAlphaComponent(0.25) {
        didSet { trackLayer.strokeColor = trackColor.cgColor }
    }

    var progressColor: UIColor = .white {
        didSet {
            if !usesGradient {
                progressLayer.strokeColor = progressColor.cgColor
            }
            percentageLabel.textColor = progressColor
        }
    }

    // MARK: - Private Properties

    private var storedGradientColors: [UIColor] = []
    private var labelInsetConstraints: [NSLayoutConstraint] = []

    // MARK: - Views

    private lazy var trackLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = trackColor.cgColor
        layer.lineWidth = lineWidth
        return layer
    }()

    private lazy var gradientLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.type = .conic
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 0.5, y: 0)
        layer.isHidden = true
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
        let baseFont = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: baseFont, maximumPointSize: 18)
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
        let path = UIBezierPath(
            arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: ringRadius,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        )
        trackLayer.frame = bounds
        progressLayer.frame = bounds
        gradientLayer.frame = bounds
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // CGColor 不随动态颜色自动更新，界面风格变化后重新解析。
        trackLayer.strokeColor = trackColor.cgColor
        applyStrokeColors()
    }

    // MARK: - Public Methods

    /// 更新完成比例与中心文字。
    func setProgress(_ progress: Double, percentageText: String?, animated: Bool) {
        let value = HUDMode.clampProgress(progress)
        let currentStrokeEnd = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
        let currentLocations = gradientLayer.presentation()?.locations ?? gradientLayer.locations
        self.progress = value
        percentageLabel.text = percentageText
        let locations = Self.gradientStops(for: value, colorCount: storedGradientColors.count)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = CGFloat(value)
        gradientLayer.locations = locations
        CATransaction.commit()

        progressLayer.removeAnimation(forKey: Constants.strokeAnimationKey)
        gradientLayer.removeAnimation(forKey: Constants.locationsAnimationKey)
        guard animated else { return }

        let strokeAnimation = CABasicAnimation(keyPath: "strokeEnd")
        strokeAnimation.fromValue = currentStrokeEnd
        strokeAnimation.toValue = value
        strokeAnimation.duration = Constants.animationDuration
        strokeAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        progressLayer.add(strokeAnimation, forKey: Constants.strokeAnimationKey)

        // 渐变终点与弧线终点同步推进，视觉上色带始终铺满整段弧。
        let locationsAnimation = CABasicAnimation(keyPath: "locations")
        locationsAnimation.fromValue = currentLocations
        locationsAnimation.toValue = locations
        locationsAnimation.duration = Constants.animationDuration
        locationsAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(locationsAnimation, forKey: Constants.locationsAnimationKey)
    }

    /// 双色及以上使用圆锥渐变；否则实心描边。
    func applyProgressAppearance(gradient: [UIColor], solid: UIColor) {
        storedGradientColors = gradient
        progressColor = solid
        if gradient.count >= 2 {
            gradientLayer.isHidden = false
            gradientLayer.colors = Self.gradientCGColors(from: gradient, traits: traitCollection)
            gradientLayer.locations = Self.gradientStops(for: progress, colorCount: gradient.count)
            progressLayer.strokeColor = UIColor.white.cgColor
            if progressLayer.superlayer !== nil, progressLayer.superlayer !== gradientLayer {
                progressLayer.removeFromSuperlayer()
            }
            gradientLayer.mask = progressLayer
        } else {
            gradientLayer.mask = nil
            gradientLayer.isHidden = true
            if progressLayer.superlayer !== layer {
                layer.addSublayer(progressLayer)
            }
            progressLayer.strokeColor = solid.cgColor
        }
        setNeedsLayout()
    }

    /// 中心百分比的文字矩形四角是否全部落在描边内圆里，避免 `100%` 压到圆环。
    func percentageLabelFitsInsideStroke() -> Bool {
        layoutIfNeeded()
        let labelFrame = percentageLabel.convert(percentageLabel.bounds, to: self)
        let textRect = percentageLabel.textRect(
            forBounds: percentageLabel.bounds,
            limitedToNumberOfLines: 1
        ).offsetBy(dx: labelFrame.minX, dy: labelFrame.minY)
        let innerRadius = ringRadius - lineWidth / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let corners = [
            CGPoint(x: textRect.minX, y: textRect.minY),
            CGPoint(x: textRect.maxX, y: textRect.minY),
            CGPoint(x: textRect.minX, y: textRect.maxY),
            CGPoint(x: textRect.maxX, y: textRect.maxY)
        ]
        return corners.allSatisfy { corner in
            hypot(corner.x - center.x, corner.y - center.y) <= innerRadius
        }
    }

    // MARK: - View Setup

    private func setupViews() {
        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        layer.addSublayer(trackLayer)
        layer.addSublayer(gradientLayer)
        layer.addSublayer(progressLayer)

        addSubview(percentageLabel)
        percentageLabel.translatesAutoresizingMaskIntoConstraints = false
        updateLabelInsets()
    }

    private func updateLabelInsets() {
        NSLayoutConstraint.deactivate(labelInsetConstraints)
        // 描边占一个 lineWidth，再留一个 lineWidth 的呼吸空间，让文字落在内圆里。
        let inset = lineWidth * 2
        labelInsetConstraints = [
            percentageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            percentageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            percentageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
        NSLayoutConstraint.activate(labelInsetConstraints)
    }

    private func applyStrokeColors() {
        if usesGradient {
            gradientLayer.colors = Self.gradientCGColors(from: storedGradientColors, traits: traitCollection)
            progressLayer.strokeColor = UIColor.white.cgColor
        } else {
            progressLayer.strokeColor = progressColor.cgColor
        }
    }

    /// 色带末色重复一次，配合 `locations` 让渐变只铺在 `[0, progress]` 区间。
    private static func gradientCGColors(from colors: [UIColor], traits: UITraitCollection) -> [CGColor] {
        guard let last = colors.last else { return [] }
        return (colors + [last]).map { $0.resolvedCGColor(for: traits) }
    }

    /// 渐变随进度铺展：原始色带均匀落在 `[0, progress]`，重复的末色补到 1；
    /// 完成态把整段色带收成纯末色，避免 12 点方向出现色缝。
    static func gradientStops(for progress: Double, colorCount: Int) -> [NSNumber] {
        let stopCount = max(colorCount, 2)
        let sweep = progress < 1 ? progress : 0
        var stops = (0 ..< stopCount).map { index in
            NSNumber(value: sweep * Double(index) / Double(stopCount - 1))
        }
        stops.append(1)
        return stops
    }
}
