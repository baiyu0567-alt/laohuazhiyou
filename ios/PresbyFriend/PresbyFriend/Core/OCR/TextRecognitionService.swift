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

    private let languagesLock = NSLock()

    private let queue = DispatchQueue(label: "com.presbyfriend.ocr")

    init(languages: [String] = ["en-US"]) {
        self.storedLanguages = languages
    }

    func recognize(_ source: OCRImageSource) async throws -> [RecognizedBlock] {
        // 快照一次：本次请求实际拿去选模型的就是这一个值，中途用户在设置页改了语言
        // 也不影响这次已经在跑的请求。
        let languages = self.languages
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
    /// 抛错静默吞掉：预热是尽力而为，失败就让第一次按快门去承担那 28–34s。
    ///
    /// **本函数不自带幂等**（曾经有一份 `warmedLanguages` 记忆，已删除）：重复调用只会
    /// 多跑一次模型已热之后的 0.1–0.35s，不会重复准备模型——那点代价不值得一套按语言组
    /// 记忆的机制。真正保证「冷启动只热一遍」的是 `PresbyFriendApp.swift` 里 `.task`
    /// 顶部那次 `settings.load()` 与 `appliedRecognitionLanguage` 那道闸。
    ///
    /// 已知局限：这是尽力而为，失败静默吞掉；且「首次慢到底是网络下载还是本地编译」
    /// 尚未验证（见设计文档「已决事项 2」），若依赖网络则无网时会退化为按快门才等。
    func prewarm() async {
        let size = 8
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let blank = ctx.makeImage() else { return }
        _ = try? await recognize(OCRImageSource(image: blank))
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
