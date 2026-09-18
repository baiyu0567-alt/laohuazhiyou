import Foundation
import Vision
import CoreGraphics

/// 一个识别出的文本块：**文字 + 它在画面里的位置** + 置信度。
///
/// 位置从原来的「一个 `topYRatio`」扩成整个 `TextLine`（含 `minX` / `width` / `height`），
/// 因为**只留纵向一个数是不够的**——版式重建要判分栏、判缩进、判短行，全都要横向信息，
/// 而这些东西一旦在这一步丢掉，下游任何一层都再拿不回来。真机报回来的
/// 「识别的内容缺乏合理的组织」就是从这里开始的（详见 `TextLayout` 的文件头）。
///
/// `text` 与 `topYRatio` 保留成计算属性而不是字段：`ordercheck` 有两条断言直接读它们，
/// 而那两条钉的行为没有变（顺序照旧、换算照旧），不该为这次改动跟着改测试。
struct RecognizedBlock: Equatable {
    /// 这一块在画面里的位置。坐标是 `TextLayout` 那一套：**归一化、y 向下为正**。
    ///
    /// **这一份是去过斜的**（页面有可辨认的弯曲时，`blocks(from:)` 会把每条观测
    /// 沿竖直方向平移回同一视觉行的共同高度）。也就是说它描述的是**摆正之后那一页**
    /// 上的位置，不是原照片上的像素位置；两者最多差 `|斜率| × 半页宽`，实测在
    /// 0.03 的量级。拿它去原图上画框的调用方要留意这一点，目前没有这样的调用方。
    let line: TextLine

    /// Vision 给这个块的置信度（0–1）。
    ///
    /// 只用来判断「这一次识别整体可不可信」（见 `ReaderLaunchCoordinator.looksWeak`）。
    /// **不要**拿它筛块或排序：实测**正确**识别的块也会低到 0.30（合成图上「用法用量」
    /// 那一行就是），单块阈值没有意义，只有整批的统计量才分得开好坏。
    let confidence: Float

    var text: String { line.text }

    /// 0 = 画面顶部，1 = 画面底部。
    ///
    /// 就是 `line.top`——`TextLine` 用的已经是「y 向下为正」，两者是同一个数，
    /// 这里不再翻一次（换算只在 `blocks(from:)` 里做一处）。
    var topYRatio: Double { line.top }
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
                // 让 Vision 自己判脚本（拉丁 / 中文），而不是**认准清单第一项**。
                //
                // 实测（自己渲染一页英文真值 56 词，退化到「拍得有点远」那一档）：
                // 清单以 `zh-Hans` 开头时**错 44 个词**——整行的词成片消失，
                // 剩下的读成 `orse` / `tabie` / `thvee` 这种；把 `en-US` 提到第一项
                // 就只错 4 个。也就是说英文识别好坏几乎不取决于「英文模型行不行」，
                // 只取决于**第一项是谁**。而用户系统语言是中文时第一项就是 `zh-Hans`，
                // 这正是真机上「拍英文效果一般」的来源。
                //
                // 打开这个开关后，同一档退化下 `--auto` 与 `en-US` 优先**逐词相同**（4 个错），
                // 且**无视清单**——清单仍写 `zh-Hans,en-US` 也是 4 个错。
                // 中文那张真机照片上则**逐字不变**（61 条观测、61 行文本全等）：
                // 这个开关不覆盖已有判断时就是空操作，不会把中文改坏。
                //
                // 头文件里那句「advisable to set the languages, if you have domain knowledge
                // of what language to expect」正是这里保留 `recognitionLanguages` 的理由：
                // 它从「选模型的开关」降级成「判错时的倾向」，用户设的语言仍然算数。
                //
                // 唯一的保留：该开关**只在 revision 3 起有效，之前是空操作**，而 3 恰好是
                // iOS 16.0 引入的（= 本工程部署目标）。已确认当前 runtime 默认 revision = 3
                // （= `supportedRevisions` 里的最大值），但手头只有 iOS 26.5 一款 runtime，
                // 「iOS 16 上默认也是 3」是**推断**。所幸推断错了也不亏：空操作即退回今天的行为。
                request.automaticallyDetectsLanguage = true
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

    /// 按纵向位置排序（画面上方到下方），恢复阅读顺序。顺带走一遍**页面去斜**。
    ///
    /// 比较器必须是全序：`sorted(by:)` 不保证稳定，同一行内被 Vision 拆开的块
    /// （字号混排、表格、带上标的标题）若纵向位置相等，顺序会逐次运行而变。
    /// 所以位置相等时再按 `minX` 升序（左栏在前）打破平局。
    ///
    /// **主序比的是观测盒的竖直中点，不是基线（`origin.y`）。**
    /// 页面倾斜时轴对齐的观测盒会被撑高（`盒高 = 真行高 + |斜率| × 盒宽`），
    /// 基线于是带着碎片**右端**的横向位置，宽碎片和窄碎片之间不可比——真机上
    /// 会把一行靠左的窄碎片排到它上面那一行靠右的宽碎片之前。
    /// 中点把宽度项减掉，宽窄碎片回到同一个尺度。完整推导见
    /// `TextLayout.readingOrder`：**两处的键是同一条，改一处就得改另一处。**
    /// 这里写的 `line.center` 与原来的 `boundingBox.midY` 是同一个数的两种坐标
    /// （`center = 1 − midY`，降序 `midY` 就是升序 `center`），换写法只是为了让
    /// 下面那步去斜能顺带把它挪对。
    ///
    /// **这个顺序是「一栏之内」的正确顺序，不是「整页」的。** 跨栏用它就会逐行交错
    /// （真实照片上左右两栏的行不落在同一个 y 上）。整页的阅读顺序要先把栏切开再排，
    /// 那一步在 `TextLayout.blocks` + `readingOrder` 里做——本函数**不做分栏**，
    /// 因为 `ShareView` 与 `RecognitionLanguageAudit` 都在用它，而它们不需要分栏。
    static func blocks(from observations: [VNRecognizedTextObservation]) -> [RecognizedBlock] {
        // 整页的弯曲量一次，再逐条应用。`nil` = 这一页没有可辨认的弯曲，
        // 下面一个像素都不动——`ShareView` 与 `RecognitionLanguageAudit` 因此在
        // 平的照片上拿到的是与从前逐位相同的盒。
        let field = slopeField(from: observations)
        return observations
            .compactMap { observation -> (line: TextLine, confidence: Float)? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                // Vision 的包围盒是「原点左下、y 向上」的归一化坐标；`TextLine` 要的是
                // 「原点左上、y 向下」。**翻转只在这一处做**，这样 `TextLayout` 和它的
                // 断言都不必每处都记得 y 是反的——那种「每处都记得」的约定迟早会漏。
                let line = TextLine(text: candidate.string,
                                    minX: Double(box.minX),
                                    top: 1.0 - Double(box.origin.y + box.height),
                                    width: Double(box.width),
                                    height: Double(box.height))
                let rectified = field.map {
                    TextLayout.deskewed(line, by: $0, referenceX: TextLayout.deskewReferenceX)
                } ?? line
                return (rectified, candidate.confidence)
            }
            .sorted { a, b in
                if a.line.center != b.line.center { return a.line.center < b.line.center }
                return a.line.minX < b.line.minX
            }
            .map { RecognizedBlock(line: $0.line, confidence: $0.confidence) }
    }

    /// 这一页的斜率场；样本不够或拟合不可信时返回 `nil`。
    private static func slopeField(from observations: [VNRecognizedTextObservation]) -> SlopeField? {
        TextLayout.slopeField(samples: tiltSamples(from: observations))
    }

    /// 逐观测取它**自己**的局部倾斜：首字符盒中心 → 末字符盒中心。
    ///
    /// 这是本工程里唯一一处用 `VNRecognizedText.boundingBox(for:)`（**字符**级包围盒）
    /// 的地方。为什么要用它、以及为什么必须由它来做，推导在 `TextLayout.TiltSample`
    /// 的文件注释里——一句话：**它不需要判断「哪两段属于同一行」**，而那件事在页面
    /// 弯曲下是量级上不可辨识的（实测页宽上的倾斜量≈一个行距）。
    ///
    /// 两道过滤都是实测出来的，不是估的：`tiltDegenerateEpsilon` 挡 Vision 沿水平线
    /// 切片（IMG_0003 的 57 条里占 25 条），`minimumTiltSpan` 挡 1/跨度 放大的噪声。
    private static func tiltSamples(from observations: [VNRecognizedTextObservation]) -> [TiltSample] {
        var samples: [TiltSample] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            guard text.count >= TextLayout.minimumTiltCharacters else { continue }

            let afterFirst = text.index(text.startIndex, offsetBy: 1)
            let lastIndex = text.index(text.endIndex, offsetBy: -1)
            guard let firstBox = try? candidate.boundingBox(for: text.startIndex..<afterFirst),
                  let lastBox = try? candidate.boundingBox(for: lastIndex..<text.endIndex) else { continue }
            let first = firstBox.boundingBox
            let last = lastBox.boundingBox

            let dy = Double(last.midY - first.midY)
            guard abs(dy) > TextLayout.tiltDegenerateEpsilon else { continue }
            let dx = Double(last.midX - first.midX)
            guard abs(dx) >= TextLayout.minimumTiltSpan else { continue }

            let box = observation.boundingBox
            let line = TextLine(text: text,
                                minX: Double(box.minX),
                                top: 1.0 - Double(box.origin.y + box.height),
                                width: Double(box.width),
                                height: Double(box.height))
            // Vision 的 y 向上、`TextLayout` 的 y 向下：斜率的符号在这里翻一次。
            samples.append(TiltSample(y: line.center,
                                                 slope: -dy / dx,
                                                 span: abs(dx)))
        }
        return samples
    }
}

/// 本机 Vision 实际支持的识别语言码。
///
/// **运行时查询，不硬编码一份清单。** 硬编码的话，一旦某台设备或某个系统版本的清单比
/// 我们写的那份少，用户就能在设置页里选中一个本机根本不存在的模型——Vision 不会报错，
/// 只会安静地用别的模型识别，正是 `RecognitionLanguage` 一直在防的那个失败模式。
/// 查询还有个附带好处：系统以后加语言，我们自动跟上。
///
/// 取的是**本进程真正会用的那个 revision**（`VNRecognizeTextRequest()` 的默认值），
/// 而不是写死的 `VNRecognizeTextRequestRevision3`：真机默认 revision 若随系统升级，
/// 这份清单跟着走，写死的那个不会。
enum OCRSupportedLanguageCodes {

    /// 本机 `.accurate` 档支持的全部语言码。本机实测 33 种。
    ///
    /// 用 `.accurate` 而不是 `.fast`：`.fast` 只有 en/fr/it/de/es/pt 六种、**没有中文**，
    /// 对中文图返回 0 个结果，而中文正是本 App 的主要场景。
    static let all: [String] = {
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = .accurate
        // 用**实例方法**，不用类方法 `supportedRecognitionLanguages(for:revision:)`：
        // 后者从 iOS 15 起已废弃，且要求调用方把 level 和 revision 再抄一遍——抄错任何
        // 一处就得到另一份清单，而清单错了不会报错。实例方法直接读这个请求自己的
        // level/revision，上面两行怎么配、清单就跟着怎么变。
        let codes = (try? probe.supportedRecognitionLanguages()) ?? []
        // 查询失败也得给一份能用的：设置页的列表、以及「跟随系统」的解析都靠它，
        // 空清单会让默认档退化成英文。
        return codes.isEmpty ? ["en-US"] : codes
    }()

    /// 按本族名排序，给设置页的列表用。Vision 返回的顺序既不是字母序也不是语言序。
    static let sorted: [String] = all.sorted {
        RecognitionLanguage.displayName(for: $0) < RecognitionLanguage.displayName(for: $1)
    }
}
