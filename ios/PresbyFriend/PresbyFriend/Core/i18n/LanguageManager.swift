import Foundation
import Combine

/// Stores the current app language and overrides Bundle.main to load
/// localized strings from the correct .lproj folder at runtime.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var current: String {
        didSet {
            UserDefaults.standard.set(current, forKey: "app_language")
        }
    }

    private init() {
        current = UserDefaults.standard.string(forKey: "app_language") ?? "en"
    }
}

// MARK: - Bundle override for runtime language switching

private var bundleKey: UInt8 = 0

final class LanguageAwareBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let lang = LanguageManager.shared.current
        guard let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
              let langBundle = Bundle(path: path) else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return langBundle.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Call once at app startup to enable runtime language switching
    static func enableLanguageSwitching() {
        object_setClass(Bundle.main, LanguageAwareBundle.self)
    }
}
