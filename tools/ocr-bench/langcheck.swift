import Foundation

// 独立编译 RecognitionLanguage.swift 并断言其构造规则。
// 编译命令见 build.sh —— 它把生产代码原文件直接编进来，测的是真代码，不是副本。

var failures = 0

func expect(_ actual: [String], _ expected: [String], _ label: String) {
    if actual == expected {
        print("  ✅ \(label) → \(actual)")
    } else {
        print("  ❌ \(label) → 实际 \(actual)，期望 \(expected)")
        failures += 1
    }
}

// .system：按系统语言码决定
expect(RecognitionLanguage.visionLanguages(systemLanguageCode: nil,      preference: .system), ["en-US"],   "system/nil")
expect(RecognitionLanguage.visionLanguages(systemLanguageCode: "en-US",  preference: .system), ["en-US"],   "system/en-US")
expect(RecognitionLanguage.visionLanguages(systemLanguageCode: "de-DE",  preference: .system), ["en-US"],   "system/de-DE")
expect(RecognitionLanguage.visionLanguages(systemLanguageCode: "zh-Hans",preference: .system), ["zh-Hans"], "system/zh-Hans")
expect(RecognitionLanguage.visionLanguages(systemLanguageCode: "zh-Hant",preference: .system), ["zh-Hans"], "system/zh-Hant")

// 手动覆盖优先于系统
expect(RecognitionLanguage.visionLanguages(systemLanguageCode: "en-US",  preference: .chinese), ["zh-Hans"], "override/中文")
expect(RecognitionLanguage.visionLanguages(systemLanguageCode: "zh-Hans",preference: .english), ["en-US"],   "override/英文")

// 回归：中文场景绝不能把 en-US 放第一位。
// 英文模型遇汉字会静默输出垃圾（实测 "用法用量" → "mzms"），这是本 App 最容易踩的坑。
if let first = RecognitionLanguage.visionLanguages(systemLanguageCode: "zh-Hans", preference: .chinese).first,
   first == "en-US" {
    print("  ❌ 回归失败：中文场景把 en-US 放在了第一位")
    failures += 1
} else {
    print("  ✅ 回归：中文场景首位不是 en-US")
}

if failures == 0 {
    print("\n全部通过")
} else {
    print("\n失败 \(failures) 项")
    exit(1)
}
