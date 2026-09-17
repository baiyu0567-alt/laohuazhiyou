import SwiftUI
import Combine

/// 送进阅读模式的内容。
enum ReaderContent {
    case text(String)
    case image(OCRImageSource)
}

/// 「识别语言可能选错了」这条提示的内容。两个码都交给 UI 去取名，
/// 这里不碰 `L10n`——文案属于视图层。
struct LanguageHint: Equatable {
    /// 这次实际用的识别语言码。
    let usedCode: String
    /// 设备语言解析出来的那一档。
    let systemCode: String
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

    /// 识别语言可能不对。nil = 不显示。判定见 `hint(for:failed:)`。
    @Published var languageHint: LanguageHint?

    private let ocr = TextRecognitionService()

    /// 这次 OCR 实际用的语言码（`updateLanguages` 里从数组首项取）。
    private var usedLanguageCode = "en-US"
    /// 设备语言解析出来的那一档。两者不同才可能出提示。
    private var systemLanguageCode = "en-US"

    /// 每次发起或取消都自增。OCR 完成时对不上就说明这次结果已经过期。
    ///
    /// OCR 期间阅读页并没有展示（只有 `isPreparing` 为真），所以放大镜页上任何
    /// 取消操作都会落在这个窗口里：`close()` 之后，在途的 `open(image:)` 恢复执行。
    /// 没有这道闸，它会把已经被用户关掉的阅读页重新推上来。
    private var generation = 0

    /// 语言数组的构造在 `RecognitionLanguage` 里，这里只是转发给 OCR 服务。
    ///
    /// 同时记下「设备语言是哪一档」，供 `hint(for:failed:)` 判断不一致——
    /// 两者必须来自同一个 `RecognitionLanguage.systemLanguageCode` 调用，不能各算各的。
    func updateLanguages(_ languages: [String], systemCode: String) {
        ocr.languages = languages
        usedLanguageCode = languages.first ?? "en-US"
        systemLanguageCode = systemCode
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
        // 同上：这条路径没有识别动作，也就无从谈起「识别语言可能不对」。
        languageHint = nil
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
        languageHint = nil

        // 把这一档固定在发请求的这一刻，理由见 `hint(for:failed:usedCode:)`。
        // 只快照它、不快照 `systemLanguageCode`：那一档是**设备**属性，改它要进系统设置，
        // 而那会让 App 退到后台、这次识别早就结束了；能在这个窗口里变的只有设置页那一项。
        let usedForThisRequest = usedLanguageCode

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
        languageHint = hint(for: blocks, failed: failed, usedCode: usedForThisRequest)
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

    /// 「识别语言可能选错了」要不要提示。**两个条件同时成立**才给：
    ///
    /// 1. 这次实际用的识别语言 ≠ 设备语言解析出来的那一档；
    /// 2. 这次的结果确实弱——一个字都没认出来，**或**整批置信度都低。
    ///
    /// 为什么非要第 2 条：手动选一门外语是**故意的**。一个在德语设备上拍中文药盒的人，
    /// 正是主动去选了中文——少了第 2 条，他每次识别成功都会被念一句「可能识别不佳」，
    /// 而他做对了。提示要给的是「认不出来」这个事实，不是「不一致」这个状态。
    ///
    /// 引擎抛错时也不提示：那是 Vision 自己失败了，跟语言选得对不对无关，
    /// 兜底文案已经在说这件事。
    /// - Parameter usedCode: **这一次识别实际用的**那一档，由调用方在发请求那一刻取好。
    ///   不能用 `usedLanguageCode` 这个活的值：`ocr.recognize` 在请求开始时就快照了语言
    ///   数组，而设置页一改语言 `updateLanguages` 就会把它换掉，于是跑完的这次识别会被
    ///   归因到**没有参与过它**的那一档上，提示里写的语言名是错的。
    private func hint(for blocks: [RecognizedBlock], failed: Bool, usedCode: String) -> LanguageHint? {
        guard !failed, usedCode != systemLanguageCode else { return nil }
        guard Self.looksWeak(blocks) else { return nil }
        return LanguageHint(usedCode: usedCode, systemCode: systemLanguageCode)
    }

    /// 这次识别是不是整体不可信。
    ///
    /// 阈值是**实测标定**的，样本是 `tools/ocr-bench` 的两张合成图 × 3 种语言：
    ///
    /// | 配置 | 块数 | 平均置信度 | 低置信度占比 |
    /// |---|---|---|---|
    /// | `zh-Hans` ✅ | 10 | 0.640 | 30% |
    /// | `zh-Hans` ✅（两栏图） | 2 | **0.400** | **50%** |
    /// | `en-US` ❌ | 4 | 0.300 | 100% |
    /// | `ja-JP` ❌ | 10 | 0.320 | 90% |
    ///
    /// **单看平均置信度分不开**：识别正确的两栏图低到 0.400，识别错误的 ja-JP 高到 0.320，
    /// 只差 0.08，那是噪声级的差距。两个条件取「且」才把六个样本全部分对——
    /// 正例靠占比那一半挡住，反例两条都满足。
    ///
    /// **块数少到统计没有意义时不做判断**（`minBlocksForStatistics`）。上表里那行正确的
    /// 两栏图是**只有 2 个块**、均值 0.400——它没有误报，靠的仅仅是两块里有一块高于 0.5，
    /// 于是占比停在 50%、没越过 0.8。两块都低一点就会翻过去：均值仍 < 0.5、占比 100%，
    /// 两条都满足，提示就会去指责一个**做对了**的用户。这不是假想的边缘情况，它是表里
    /// 那一行再走半步。而两个真阳性（4 块 / 10 块）都在门槛之上，所以这条门槛把两个真阳性
    /// 全留下，同时把那半步结构性挡住。
    ///
    /// **代价写清楚**：短文本（1–3 个块）用错语言时不再提示。这是故意换的——只有一两行字
    /// 时，「语言选错」和「这张照片本身就糊」在统计上分不开，而误报是当着做对了的人的面
    /// 说他错了，比少说一句更坏。这类用户仍然有设置页那个 ❗ 常驻提醒他偏离了系统语言。
    ///
    /// **误报与漏报的代价不对称**：误报是当着一个做对了的用户的面说他可能错了，
    /// 漏报只是少显示一句提示。所以这里宁漏不误，宁可把阈值定紧。
    ///
    /// ⚠️ 样本只有两张**合成图**，而 `tools/ocr-bench/README.md`「局限」一节写明合成图
    /// 不含真实照片的透视畸变、光照不均、反光，且合成图上正确识别本身就只有 0.400。
    /// 真机上拿真实药盒照片复验过再定这三个阈值。
    private static func looksWeak(_ blocks: [RecognizedBlock]) -> Bool {
        // 一个字都没认出来——最强的信号，且与样本量无关，所以它排在块数门槛**之前**：
        // 一张图里零个块，本身就是「这次白拍了」，不需要统计。
        guard !blocks.isEmpty else { return true }
        guard blocks.count >= minBlocksForStatistics else { return false }

        let confidences = blocks.map(\.confidence)
        let count = Float(confidences.count)
        let mean = confidences.reduce(0, +) / count
        let lowFraction = Float(confidences.filter { $0 < lowConfidence }.count) / count
        return mean < weakMeanConfidence && lowFraction > weakLowFraction
    }

    /// 块数少于它就不做统计判断。取 4 的理由见 `looksWeak` 的文档：这是能同时留下
    /// 标定表里两个真阳性（4 块 / 10 块）的最小值。
    private static let minBlocksForStatistics = 4
    /// 单个块低于它算「低置信度」。
    private static let lowConfidence: Float = 0.5
    /// 整批平均低于它、且低置信度块占比高于 `weakLowFraction`，才判为弱。
    private static let weakMeanConfidence: Float = 0.5
    private static let weakLowFraction: Float = 0.8

    func close() {
        // 作废在途的 OCR，并收掉它的转圈——否则被取消的那次会把「正在准备」留在屏幕上。
        generation += 1
        isPresenting = false
        isPreparing = false
        recognitionFailed = false
        languageHint = nil
        text = nil
        fallbackImage = nil
    }
}
