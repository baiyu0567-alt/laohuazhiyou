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
    }

    func save() {
        defaults.set(fontSize, forKey: "fontSize")
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(lineHeight, forKey: "lineHeight")
        defaults.set(letterSpacing, forKey: "letterSpacing")
        defaults.set(rulerEnabled, forKey: "rulerEnabled")
        defaults.set(language, forKey: "language")
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
