import SwiftUI
import CoreGraphics
import Combine

/// 送进阅读模式的内容。
enum ReaderContent {
    case text(String)
    case image(OCRImageSource)
}

/// 承载「某段内容 → 打开阅读模式」这一个动作，三个入口共用。
@MainActor
final class ReaderLaunchCoordinator: ObservableObject {

    /// 是否展示阅读模式。
    @Published var isPresenting = false
    /// 正在 OCR。UI 用它显示「正在准备」而不是卡住。
    @Published var isPreparing = false
    /// 待阅读的文本。OCR 成功后由识别结果填入。
    @Published var text: String?
    /// OCR 没认出文字时的兜底：直接显示原图（只支持缩放）。
    @Published var fallbackImage: OCRImageSource?

    private let ocr = TextRecognitionService()

    /// 语言数组的构造在 `RecognitionLanguage` 里，这里只是转发给 OCR 服务。
    func updateLanguages(_ languages: [String]) {
        ocr.languages = languages
    }

    /// 启动时后台预热识别模型，避免用户第一次按快门要等很久。
    func prewarm() {
        let service = ocr
        Task.detached(priority: .utility) {
            await service.prewarm()
        }
    }

    func open(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        fallbackImage = nil
        self.text = trimmed
        isPresenting = true
    }

    func open(image source: OCRImageSource) async {
        isPreparing = true
        defer { isPreparing = false }

        let blocks = (try? await ocr.recognize(source)) ?? []
        let joined = blocks.map(\.text).joined(separator: "\n")

        if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 空结果不算错误：兜底显示原图，让用户自己放大看。
            text = nil
            fallbackImage = source
        } else {
            text = joined
            fallbackImage = nil
        }
        isPresenting = true
    }

    func close() {
        isPresenting = false
        text = nil
        fallbackImage = nil
    }
}
