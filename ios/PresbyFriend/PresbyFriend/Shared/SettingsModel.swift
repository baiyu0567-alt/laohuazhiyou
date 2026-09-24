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

    private let defaults = UserDefaults(suiteName: "group.35MJ76582H.com.presbyfriend")!

    /// iCloud 键值存储**不是无条件可用的**：它要求 App 签了
    /// `com.apple.developer.ubiquity-kvstore-identifier`。
    ///
    /// 本工程两份 entitlements（app 与扩展）都**只有 App Group，没有这一项**，于是
    /// `NSUbiquitousKeyValueStore.default` 只要被碰到就往控制台吐
    /// `BUG IN CLIENT OF KVS: Trying to initialize NSUbiquitousKeyValueStore without a store identifier`
    /// ——2026-09-23 真机跑出来的就是这条。它不崩，但「设置云同步」这件事**根本不存在**。
    ///
    /// 所以先查权限再决定碰不碰。注意这里**不能**改成 `lazy var` 了事：那只是把同一条抱怨
    /// 从启动推迟到第一次 `save()`，功能一样是假的。
    ///
    /// 将来在开发者后台给 App ID 开 iCloud 并补上该 entitlement 后，这里会自动开始工作，
    /// 不需要再改代码。
    private static let cloudStore: NSUbiquitousKeyValueStore? = {
        // 判据用 `ubiquityIdentityToken`：没签 iCloud entitlement、或用户没登录 iCloud，
        // 它都返回 nil，而这两种情况下 KVS 本来也用不了，跳过就对了。
        //
        // **不要**换成 `SecTaskCopyValueForEntitlement` ——SecTask 那一套只在 macOS 上有，
        // iOS 上连符号都找不到（实测两个 target 都是 `cannot find in scope`）。
        guard FileManager.default.ubiquityIdentityToken != nil else { return nil }
        return .default
    }()

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
        guard let cloudStore = Self.cloudStore else { return }
        cloudStore.set(fontSize, forKey: "fontSize")
        cloudStore.set(theme.rawValue, forKey: "theme")
        cloudStore.set(lineHeight, forKey: "lineHeight")
        cloudStore.set(letterSpacing, forKey: "letterSpacing")
        cloudStore.synchronize()
    }

    /// ⚠️ **这条目前即使云同步可用也是无效的**：回调里只调 `load()`，而 `load()` 读的是
    /// 本地 `defaults`（App Group），**不是 `cloudStore`**。也就是说别的设备改过来的值
    /// 不会经这里落到本机——这个通知白挂。
    ///
    /// 没顺手改，是因为「云端的值和本机刚改的值谁赢」是个要定的策略（离线改过之后
    /// 再收到云变更，直接采用云端＝丢掉用户刚做的设置），不属于缺陷修复的范围。
    /// 等 entitlement 补上、这条路真的跑起来时再定。
    func listenForCloudChanges() {
        guard let cloudStore = Self.cloudStore else { return }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }
    }

    /// 只重置**外观与识别**这几项，刻意不含订阅状态。
    ///
    /// 订阅那边的键（`isProCached` / `dailyUseCount` / `lastUseDate`，见
    /// `SubscriptionManager`）与这里用的键**不相交**，所以「重置设置」不会把已付费的
    /// 用户打回免费——那会是让用户白花钱。将来往 `save()` 里加键时留意这条。
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
