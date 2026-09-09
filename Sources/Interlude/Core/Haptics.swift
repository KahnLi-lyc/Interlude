import UIKit

/// 触感播放抽象，测试中可替换以验证是否触发。
@MainActor
protocol HapticsPlayer: AnyObject {
    func play(_ type: UINotificationFeedbackGenerator.FeedbackType)
}

/// 使用 `UINotificationFeedbackGenerator` 的默认实现。
@MainActor
final class SystemHapticsPlayer: HapticsPlayer {
    // MARK: - Private Properties

    private lazy var generator = UINotificationFeedbackGenerator()

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    func play(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        generator.notificationOccurred(type)
    }
}
