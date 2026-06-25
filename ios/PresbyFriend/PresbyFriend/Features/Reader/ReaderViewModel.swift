import SwiftUI
import Combine

final class ReaderViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var paragraphs: [String] = []
    @Published var fontSize: CGFloat = 40
    @Published var theme: ReadingTheme = .dark
    @Published var lineHeight: Double = 1.8
    @Published var letterSpacing: CGFloat = 1.0
    @Published var rulerEnabled: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var controlsVisible: Bool = false
    @Published var language: String = "en"

    private let speechManager = SpeechManager()

    func loadSettings(from settings: SettingsModel) {
        fontSize = settings.fontSize
        theme = settings.theme
        lineHeight = settings.lineHeight
        letterSpacing = settings.letterSpacing
        rulerEnabled = settings.rulerEnabled
        language = settings.language
    }

    func saveToSettings(_ settings: SettingsModel) {
        settings.fontSize = fontSize
        settings.theme = theme
        settings.lineHeight = lineHeight
        settings.letterSpacing = letterSpacing
        settings.save()
    }

    func adjustFontSize(by delta: CGFloat) {
        fontSize = max(24, min(72, fontSize + delta * 4))
    }

    func adjustLineHeight(by delta: Double) {
        lineHeight = max(1.0, min(3.0, (lineHeight + delta * 0.2 * 10).rounded() / 10))
    }

    func adjustLetterSpacing(by delta: CGFloat) {
        letterSpacing = max(0, min(5, letterSpacing + delta * 0.5))
    }

    func toggleSpeaking() {
        if isSpeaking {
            speechManager.stop()
            isSpeaking = false
        } else {
            let textToSpeak = paragraphs.isEmpty ? text : paragraphs.joined(separator: "\n\n")
            speechManager.speak(textToSpeak, language: language)
            isSpeaking = true
            speechManager.onFinish = { [weak self] in
                self?.isSpeaking = false
            }
        }
    }

    func stopSpeaking() {
        speechManager.stop()
        isSpeaking = false
    }

    /// Parse incoming text into paragraphs (split on double-newline).
    /// Called when text might be multi-paragraph (e.g., from accessibility service).
    func setParagraphs(from raw: String) {
        let parts = raw
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count > 1 {
            paragraphs = parts
            text = raw
        } else {
            paragraphs = []
            text = raw
        }
    }
}
