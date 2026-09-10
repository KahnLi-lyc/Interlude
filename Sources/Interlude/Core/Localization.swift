import Foundation

/// 内置文案读取：优先 `Configuration.strings` 覆盖，其次库资源包，最后英文兜底。
enum Localization {
    // MARK: - Types

    enum Key: String, CaseIterable {
        case loading = "interlude.loading"
        case success = "interlude.success"
        case error = "interlude.error"
        case info = "interlude.info"
        case timeout = "interlude.timeout"
        case cancel = "interlude.cancel"
        case toastDismissHint = "interlude.toast.dismiss_hint"

        var fallback: String {
            switch self {
            case .loading: return "Loading"
            case .success: return "Success"
            case .error: return "Error"
            case .info: return "Information"
            case .timeout: return "Request timed out"
            case .cancel: return "Cancel"
            case .toastDismissHint: return "Double tap to dismiss"
            }
        }
    }

    // MARK: - Public Methods

    /// 返回指定键的最终文案。
    static func string(_ key: Key, overrides: Interlude.Strings) -> String {
        if let override = overrides.value(for: key), !override.isEmpty {
            return override
        }
        return resourceBundle.localizedString(forKey: key.rawValue, value: key.fallback, table: nil)
    }

    /// 库资源包。SwiftPM 使用 `Bundle.module`；直接把源码拖入工程等非 SwiftPM 场景回退到类所在 bundle。
    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
            return Bundle.module
        #else
            let containing = Bundle(for: BundleLocator.self)
            if let url = containing.url(forResource: "Interlude", withExtension: "bundle"),
               let bundle = Bundle(url: url) {
                return bundle
            }
            return containing
        #endif
    }
}

/// 仅用于定位资源包的空类型。
private final class BundleLocator {}

private extension Interlude.Strings {
    func value(for key: Localization.Key) -> String? {
        switch key {
        case .loading: return loading
        case .success: return success
        case .error: return error
        case .info: return info
        case .timeout: return timeout
        case .cancel: return cancel
        case .toastDismissHint: return toastDismissHint
        }
    }
}
