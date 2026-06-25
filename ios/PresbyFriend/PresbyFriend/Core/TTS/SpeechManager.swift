import AVFoundation

final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Short code → BCP-47 tag for AVSpeechSynthesisVoice
    private let languageMap: [String: String] = [
        "en": "en-US", "de": "de-DE", "fr": "fr-FR",
        "es": "es-ES", "it": "it-IT", "pt": "pt-PT",
        "zh": "zh-CN",
    ]

    /// Detect the dominant language of text to pick an appropriate voice
    private func voiceFor(text: String, preferredLanguage: String) -> AVSpeechSynthesisVoice {
        // 1. Detect text language — Chinese gets zh-CN voice first
        let hasChinese = text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value)
        }
        if hasChinese, let zhVoice = AVSpeechSynthesisVoice(language: "zh-CN") {
            return zhVoice
        }
        // 2. Try user's preferred language
        let prefTag = languageMap[preferredLanguage] ?? preferredLanguage
        if let voice = AVSpeechSynthesisVoice(language: prefTag) {
            return voice
        }
        // 3. Fallback to en-US
        return AVSpeechSynthesisVoice(language: "en-US")!
    }

    func speak(_ text: String, language: String = "en", rate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.9) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.voice = voiceFor(text: text, preferredLanguage: language)
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }
}
