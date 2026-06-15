import SwiftUI
import Combine

final class ReaderViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var fontSize: CGFloat = 40
    @Published var theme: ReadingTheme = .dark
    @Published var lineHeight: Double = 1.8
    @Published var letterSpacing: CGFloat = 1.0
    @Published var rulerEnabled: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var controlsVisible: Bool = false

    private let speechManager = SpeechManager()
    private var cancellables = Set<AnyCancellable>()

    func loadSettings(from settings: SettingsModel) {
        fontSize = settings.fontSize
        theme = settings.theme
        lineHeight = settings.lineHeight
        letterSpacing = settings.letterSpacing
        rulerEnabled = settings.rulerEnabled
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
            speechManager.speak(text)
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
}
