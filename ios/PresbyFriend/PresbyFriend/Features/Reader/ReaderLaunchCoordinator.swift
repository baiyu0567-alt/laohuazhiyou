import SwiftUI
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

    /// OCR **抛错**，而不是「这张图里确实没有文字」。
    ///
    /// 两者都会走 `fallbackImage` 兜底，但文案必须分开：识别失败却告诉用户
    /// 「没有文字」是在说谎。用最小的 `Bool` 表达这个二值信号，和 `isPreparing`
    /// / `isPresenting` 保持同一种风格。
    @Published var recognitionFailed = false

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
        // 文本路径没有识别动作，失败标志必须归零，否则会继承上一次 OCR 的状态。
        recognitionFailed = false
        fallbackImage = nil
        self.text = trimmed
        isPresenting = true
    }

    func open(image source: OCRImageSource) async {
        generation += 1
        let token = generation

        // 清掉上一次残留的内容。`isPresenting` 在这里**故意不动**：它可能还挂着上一次的
        // 展示，而 `readerContent` 的第三个分支（PresbyFriendApp.swift 兜底那段黑底 +
        // Close）正是为「isPresenting 为真但两条内容路径都为空」准备的出口。
        //
        // 不清的后果：`text`/`fallbackImage` 留着上一次的值，OCR 那 28–34s 里
        // `readerContent` 会按**上一次**的内容选分支——字幕就会是上一篇的
        // `ocr_no_text` / `ocr_fail`，而不是这一次的。今天够不到：两条 `open(image:)`
        // 调用点（放大镜快门、读取 tab 的相册选择）都在全屏阅读页**底下**，阅读页开着时
        // 点不到它们。但没有任何东西在保证这一点。
        text = nil
        fallbackImage = nil

        isPreparing = true
        recognitionFailed = false
        // 只有仍然是「当前这一次」时才由自己收尾，否则会把后来者的转圈关掉。
        defer { if token == generation { isPreparing = false } }

        // 这里不能再用 `try?`：它把 Vision 的抛错折成 `[]`，和「这张图真的没有文字」
        // 撞成同一个值，于是失败会被当成空结果报给用户。两种结果必须留下不同的痕迹。
        let blocks: [RecognizedBlock]
        var failed = false
        do {
            blocks = try await ocr.recognize(source)
        } catch {
            blocks = []
            failed = true
        }
        let joined = blocks.map(\.text).joined(separator: "\n")

        // 等待期间用户可能已经关掉、或又开了别的。过期的结果一律不许放行。
        guard token == generation else { return }

        recognitionFailed = failed
        if !failed, !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = joined
            fallbackImage = nil
        } else {
            // 空结果不算错误（图里确实没文字），识别失败也不算：两者都兜底显示原图，
            // 让用户自己放大看。区别只在文案，交给 UI 按 `recognitionFailed` 选。
            text = nil
            fallbackImage = source
        }
        isPresenting = true
    }

    func close() {
        // 作废在途的 OCR，并收掉它的转圈——否则被取消的那次会把「正在准备」留在屏幕上。
        generation += 1
        isPresenting = false
        isPreparing = false
        recognitionFailed = false
        text = nil
        fallbackImage = nil
    }
}
