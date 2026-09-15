import SwiftUI
import Combine

final class SettingsViewModel: ObservableObject {
    @Published var fontSize: CGFloat = 40
    @Published var theme: ReadingTheme = .dark
    @Published var lineHeight: Double = 1.8
    @Published var letterSpacing: CGFloat = 1.0
    @Published var rulerEnabled: Bool = false
    @Published var selectedLanguage: String = "en"
    @Published var recognitionLanguage: RecognitionLanguage = .system

    let availableLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("de", "Deutsch"),
        ("it", "Italiano"),
        ("fr", "Français"),
        ("es", "Español"),
        ("pt", "Português"),
    ]

    func load(from settings: SettingsModel) {
        fontSize = settings.fontSize
        theme = settings.theme
        lineHeight = settings.lineHeight
        letterSpacing = settings.letterSpacing
        rulerEnabled = settings.rulerEnabled
        selectedLanguage = settings.language
        recognitionLanguage = settings.recognitionLanguage
    }

    func save(to settings: SettingsModel) {
        settings.fontSize = fontSize
        settings.theme = theme
        settings.lineHeight = lineHeight
        settings.letterSpacing = letterSpacing
        settings.rulerEnabled = rulerEnabled
        settings.language = selectedLanguage
        settings.recognitionLanguage = recognitionLanguage
        settings.save()
    }
}
