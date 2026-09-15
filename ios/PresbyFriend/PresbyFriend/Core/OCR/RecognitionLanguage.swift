import Foundation

/// 识别语言偏好。三种取值，`system` 为默认。
///
/// 刻意只 `import Foundation`、不引用 `L10n` 或任何 UI 类型——这样它可以被
/// `tools/ocr-bench/langcheck` 单独编出来跑断言。显示用的文案在设置页里给。
enum RecognitionLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese
    case english

    var id: String { rawValue }

    /// 构造 Vision 的 `recognitionLanguages`。
    ///
    /// **数组的第一个元素决定用哪个识别模型。** 选错不会报错、不会崩溃，只会
    /// 安静地输出垃圾（实测：中文图 + `["en-US"]` 把「用法用量」识别成 `mzms`）。
    /// 中文模型能勉强认拉丁字母，英文模型遇汉字直接崩，所以中文场景必须把
    /// `zh-Hans` 放在第一位。
    ///
    /// - Parameters:
    ///   - systemLanguageCode: 系统语言码，如 `"zh-Hans"`、`"de-DE"`。可为 nil。
    ///   - preference: 用户在设置页的选择；`.system` 表示跟随系统。
    static func visionLanguages(systemLanguageCode: String?,
                                preference: RecognitionLanguage) -> [String] {
        switch preference {
        case .chinese:
            return ["zh-Hans"]
        case .english:
            return ["en-US"]
        case .system:
            let code = systemLanguageCode?.lowercased() ?? ""
            return code.hasPrefix("zh") ? ["zh-Hans"] : ["en-US"]
        }
    }
}
