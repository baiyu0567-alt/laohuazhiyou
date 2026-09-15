import Foundation
import Vision
import CoreGraphics

/// 一个识别出的文本块。
struct RecognizedBlock: Equatable {
    let text: String
    /// 0 = 画面顶部，1 = 画面底部。用于恢复阅读顺序。
    let topYRatio: Double
}

/// 唯一接触 Vision 的地方：把「一张图」变成「一串文本块」。
final class TextRecognitionService {

    /// 当前生效的识别语言。由调用方根据 `RecognitionLanguage.visionLanguages` 设置——
    /// 本服务不猜，猜错的代价是静默输出垃圾。
    ///
    /// **并发安全**：`prewarm()` 经 `Task.detached` 在后台线程读它，而设置页改语言时
    /// `ReaderLaunchCoordinator.updateLanguages` 在主线程写它——两者可以同时发生。
    /// 并发读写同一个 `Array` 是未定义行为：写方的赋值会连同 COW 缓冲一起换掉，
    /// 读方可能拿着被释放/半改的缓冲，**可能崩溃**，不只是取到旧值。所以用一把
    /// 独立的锁把属性访问串行化。
    ///
    /// **为什么不复用下面那把 `queue`**：`queue` 上跑的是整段 Vision 请求，
    /// 首次预热要占住它 28–34s（见 `prewarm()` 的注释）。若 getter/setter 走
    /// `queue.sync`，主线程改一次语言就会卡到那次识别结束——设置页冻住，甚至被
    /// watchdog 杀掉。那把队列是「OCR 工作」的串行化，不是「属性访问」的锁。
    /// 用独立的锁也顺带保证没有任何 `queue.sync` 会嵌在 `queue` 自己的工作里。
    var languages: [String] {
        get {
            languagesLock.lock()
            defer { languagesLock.unlock() }
            return storedLanguages
        }
        set {
            languagesLock.lock()
            defer { languagesLock.unlock() }
            storedLanguages = newValue
        }
    }

    /// 由 `languagesLock` 保护。只经上面的计算属性访问。
    private var storedLanguages: [String]

    /// 最近一次**真的跑完**预热的语言组。`nil` = 还没预热过。
    ///
    /// 同样由 `languagesLock` 保护——那是 `languages` 已经在用的那把锁，这里只是
    /// 共用它，不新开第二套同步机制：两者本来就只在预热这一个动作里一起被读写。
    /// 存取都是数组比较/赋值的 O(1)，不会像 `queue.sync` 那样被 28–34s 的预热挡住。
    private var warmedLanguages: [String]?

    private let languagesLock = NSLock()

    private let queue = DispatchQueue(label: "com.presbyfriend.ocr")

    init(languages: [String] = ["en-US"]) {
        self.storedLanguages = languages
    }

    /// 这组语言是不是已经预热过了。与 `languages` 共用 `languagesLock`。
    ///
    /// 比的是数组本身（逐元素、**含顺序**），不是数学意义上的集合：Vision 拿
    /// `recognitionLanguages` 的**第一个元素**选识别模型，顺序不同就是不同的选择。
    /// 只有逐字相同时才跳过，其余一律偏向「再热一次」——宁可白跑一趟，不可把
    /// 选中的模型晾冷。
    private func hasWarmed(_ languages: [String]) -> Bool {
        languagesLock.lock()
        defer { languagesLock.unlock() }
        return warmedLanguages == languages
    }

    /// 预热**跑完之后**才调用，记的是真的热了的那一组。
    ///
    /// 不能改成预热前先记：一次失败的预热会把根本没热的模型记成已热，之后同一组
    /// 语言每次都跳过，模型**永远冷着**——那正是这块代码要防的事。
    private func markWarmed(_ languages: [String]) {
        languagesLock.lock()
        defer { languagesLock.unlock() }
        warmedLanguages = languages
    }

    func recognize(_ source: OCRImageSource) async throws -> [RecognizedBlock] {
        try await recognize(source, languages: self.languages)
    }

    /// 同上，但用调用方给的快照。
    ///
    /// `prewarm()` 需要「实际拿来预热的语言」和「跑完记下的语言」是同一个值：
    /// 分别在两处读 `languages`，中间用户可能正好在设置页改了语言，于是预热的是 A、
    /// 记下的是 B——B 热着却被记成没热（下次白跑），A 没热却被记成热了（永远冷着）。
    /// 所以快照只取一次，一路传到底。
    private func recognize(_ source: OCRImageSource, languages: [String]) async throws -> [RecognizedBlock] {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let request = VNRecognizeTextRequest()
                // 必须 .accurate：.fast 档不支持中文（只有 en/fr/it/de/es/pt），
                // 对中文图返回 0 个结果，没有「降档换速度」的余地。
                request.recognitionLevel = .accurate
                request.recognitionLanguages = languages
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: source.image,
                                                    orientation: source.orientation,
                                                    options: [:])
                do {
                    try handler.perform([request])
                    continuation.resume(returning: Self.blocks(from: request.results ?? []))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 启动时后台调用，避免用户第一次按快门要等模型准备。
    ///
    /// 实测：某个语言模型首次使用约 28–34s（一次性），之后 0.1–0.35s，按语言分别准备。
    /// 这里喂一张 8×8 的空白图——目的是触发模型加载，不指望识别出东西。
    /// 已知局限：这是尽力而为，失败静默吞掉；且「首次慢到底是网络下载还是本地编译」
    /// 尚未验证（见设计文档「已决事项 2」），若依赖网络则无网时会退化为按快门才等。
    ///
    /// **按语言组幂等**：同一组语言重复请求不再重复预热。这盖住的是「**同一份**数组
    /// 被请求两次」这一类重复——`ContentView` 因 `.id(languageManager.current)`
    /// （`PresbyFriendApp.swift:37`）重建时整个子树会重跑一遍 `.task`，以及将来任何
    /// 新加的调用点，都不必再靠调用顺序去躲。
    ///
    /// **它不覆盖「两份不同的数组」**：语言真的不一样就必然各热一次，这正是「绝不把
    /// 选中的模型晾冷」所要求的（A→B→A 三次都要热）。所以启动路径上「只热一遍」不是
    /// 这里保证的——那是 `ContentView.task` 先做 `settings.load()` 保证的。
    /// 判据是「和上次真的热过的那一组逐字相同」，其余一律偏向再热一次。
    func prewarm() async {
        // 快照一次：这次拿来预热的、以及跑完记下的，必须是同一个值。
        let languages = self.languages
        guard !hasWarmed(languages) else { return }

        let size = 8
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let blank = ctx.makeImage() else { return }
        // 抛错照旧静默吞掉，但**绝不记成「已热」**：没法像 `try?` 那样顺手——
        // `try?` 把抛错折成 `nil` 之后照样往下走，下面那行 `markWarmed` 会执行，
        // 于是没热成的模型被记成已热，之后同一组语言次次跳过，模型**永远冷着**。
        // 「记成已热」的代价比「白跑一次」大得多，所以这里显式分开处理。
        do {
            _ = try await recognize(OCRImageSource(image: blank), languages: languages)
        } catch {
            return
        }
        markWarmed(languages)
    }

    /// 按纵向位置排序（画面上方到下方），恢复阅读顺序。
    ///
    /// 比较器必须是全序：`sorted(by:)` 不保证稳定，同一行内被 Vision 拆开的块
    /// （字号混排、表格、带上标的标题）若 `origin.y` 相等，顺序会逐次运行而变。
    /// 所以 y 相等时再按 `minX` 升序（左栏在前）打破平局。
    /// 真正的两栏重排需要行聚类，不在本任务范围内。
    static func blocks(from observations: [VNRecognizedTextObservation]) -> [RecognizedBlock] {
        observations
            .sorted { a, b in
                if a.boundingBox.origin.y != b.boundingBox.origin.y {
                    return a.boundingBox.origin.y > b.boundingBox.origin.y
                }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            .compactMap { obs in
                guard let top = obs.topCandidates(1).first else { return nil }
                let box = obs.boundingBox
                return RecognizedBlock(text: top.string,
                                       topYRatio: 1.0 - Double(box.origin.y + box.height))
            }
    }
}
