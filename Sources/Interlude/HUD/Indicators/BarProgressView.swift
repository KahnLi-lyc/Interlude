import UIKit

/// 水平进度条：圆角轨道 + 填充，右侧显示本地化整数百分比。
@MainActor
final class BarProgressView: UIView {
    // MARK: - Types

    private enum Constants {
        static let barHeight: CGFloat = 6
        static let barWidth: CGFloat = 140
        static let spacing: CGFloat = 8
        static let percentageWidth: CGFloat = 40
    }

    // MARK: - Public Properties

    private(set) var progress: Double = 0

    var trackColor: UIColor = UIColor.white.withAlphaComponent(0.25) {
        didSet { trackView.backgroundColor = trackColor }
    }

    var progressColor: UIColor = .white {
        didSet {
            fillView.backgroundColor = progressColor
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
        view.isAccessibilityElement = false
        return view
    }()

    private lazy var percentageLabel: UILabel = {
        let label = UILabel()
        let baseFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: baseFont, maximumPointSize: 15)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = progressColor
        label.textAlignment = .right
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

    // MARK: - Public Methods

    func setProgress(_ progress: Double, percentageText: String?, animated: Bool) {
        let value = HUDMode.clampProgress(progress)
        self.progress = value
        percentageLabel.text = percentageText
        fillWidthConstraint?.constant = Constants.barWidth * CGFloat(value)

        guard animated else {
            trackView.layoutIfNeeded()
            return
        }
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.trackView.layoutIfNeeded()
        }
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

        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackView.widthAnchor.constraint(equalToConstant: Constants.barWidth),
            trackView.heightAnchor.constraint(equalToConstant: Constants.barHeight),

            fillView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor),
            fillView.topAnchor.constraint(equalTo: trackView.topAnchor),
            fillView.bottomAnchor.constraint(equalTo: trackView.bottomAnchor),
            fillWidth,

            percentageLabel.leadingAnchor.constraint(equalTo: trackView.trailingAnchor, constant: Constants.spacing),
            percentageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            percentageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.percentageWidth)
        ])
    }
}
