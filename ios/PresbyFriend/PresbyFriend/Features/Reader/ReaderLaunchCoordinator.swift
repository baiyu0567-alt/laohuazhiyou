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

    /// 每次发起或取消都自增。OCR 完成时对不上就说明这次结果已经过期。
    ///
    /// OCR 期间阅读页并没有展示（只有 `isPreparing` 为真），所以放大镜页上任何
    /// 取消操作都会落在这个窗口里：`close()` 之后，在途的 `open(image:)` 恢复执行。
    /// 没有这道闸，它会把已经被用户关掉的阅读页重新推上来。
    private var generation = 0

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
        // 文本直接有了，不需要等 OCR：作废在途的那次，别让它回来覆盖。
        generation += 1
        isPreparing = false
        fallbackImage = nil
        self.text = trimmed
        isPresenting = true
    }

    func open(image source: OCRImageSource) async {
        generation += 1
        let token = generation

        isPreparing = true
        // 只有仍然是「当前这一次」时才由自己收尾，否则会把后来者的转圈关掉。
        defer { if token == generation { isPreparing = false } }

        let blocks = (try? await ocr.recognize(source)) ?? []
        let joined = blocks.map(\.text).joined(separator: "\n")

        // 等待期间用户可能已经关掉、或又开了别的。过期的结果一律不许放行。
        guard token == generation else { return }

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
        // 作废在途的 OCR，并收掉它的转圈——否则被取消的那次会把「正在准备」留在屏幕上。
        generation += 1
        isPresenting = false
        isPreparing = false
        text = nil
        fallbackImage = nil
    }
}
