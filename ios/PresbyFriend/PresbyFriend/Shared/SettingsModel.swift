import Foundation
import SwiftUI
import Combine

final class SettingsModel: ObservableObject {
    @Published var fontSize: CGFloat = 40
    @Published var theme: ReadingTheme = .dark
    @Published var lineHeight: Double = 1.8
    @Published var letterSpacing: CGFloat = 1.0
    @Published var rulerEnabled: Bool = false
    @Published var language: String = "en"
    @Published var recognitionLanguage: RecognitionLanguage = .followSystem

    /// Set by the main app when a URL is opened from another app. Reset to nil after handling.
    @Published var pendingURL: URL?

    private let defaults = UserDefaults(suiteName: "group.com.presbyfriend")!
    private let cloudStore = NSUbiquitousKeyValueStore.default

    func load() {
        fontSize = defaults.cgFloat(forKey: "fontSize") ?? 40
        theme = ReadingTheme(rawValue: defaults.string(forKey: "theme") ?? "dark") ?? .dark
        lineHeight = defaults.doubleOrNil(forKey: "lineHeight") ?? 1.8
        letterSpacing = defaults.cgFloat(forKey: "letterSpacing") ?? 1.0
        rulerEnabled = defaults.bool(forKey: "rulerEnabled")
        language = defaults.string(forKey: "language") ?? "en"
        // 存储为空时得到「跟随系统」——**这里不需要知道设备语言**：跟随发生在真正构造
        // Vision 语言数组的那一刻（`RecognitionLanguage.systemLanguageCode`），
        // 不是在读设置时算一次冻住。所以在用户动过这项设置之前，改设备语言是会生效的；
        // 一旦进过设置页（`SettingsView.onDisappear` 会 `save()`），就以用户的选择为准。
        //
        // 旧分支写下的档位名（`system`/`chinese`/`english`…）由 `stored(from:supported:)`
        // 映射过来，不会因为改了档位名就被静默重置。
        //
        // `supported` 要传：一个本机识别不了的档位等于把「语言选错」固化下来，
        // 所以认不出来的存储值一律返回 nil，落到默认档。
        recognitionLanguage = RecognitionLanguage.stored(
            from: defaults.string(forKey: "recognitionLanguage"),
            supported: OCRSupportedLanguageCodes.all) ?? .followSystem
    }

    func save() {
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(lineHeight, forKey: "lineHeight")
        defaults.set(letterSpacing, forKey: "letterSpacing")
        defaults.set(rulerEnabled, forKey: "rulerEnabled")
        defaults.set(language, forKey: "language")
        defaults.set(recognitionLanguage.stored, forKey: "recognitionLanguage")
        syncToCloud()
    }

    private func syncToCloud() {
        cloudStore.set(fontSize, forKey: "fontSize")
        cloudStore.set(theme.rawValue, forKey: "theme")
        cloudStore.set(lineHeight, forKey: "lineHeight")
        cloudStore.set(letterSpacing, forKey: "letterSpacing")
        cloudStore.synchronize()
    }

    func listenForCloudChanges() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }
    }

    func reset() {
        fontSize = 40
        theme = .dark
        lineHeight = 1.8
        letterSpacing = 1.0
        rulerEnabled = false
        // 「重置」回到的正是全新安装会得到的那一档——现在两者都是 `.followSystem`，
        // 不再需要各算各的。
        recognitionLanguage = .followSystem
        save()
    }
}

private extension UserDefaults {
    func cgFloat(forKey key: String) -> CGFloat? {
        guard double(forKey: key) != 0 || object(forKey: key) != nil else { return nil }
        return CGFloat(double(forKey: key))
    }

    func doubleOrNil(forKey key: String) -> Double? {
        guard object(forKey: key) != nil else { return nil }
        return double(forKey: key)
    }

    func cgFloatSet(_ value: CGFloat, forKey key: String) {
        set(Double(value), forKey: key)
    }
}
