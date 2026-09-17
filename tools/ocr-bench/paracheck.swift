import Foundation
import Vision
import ImageIO
import CoreGraphics

// 端到端：**真图片 → Vision → `blocks(from:)`（含坐标翻转）→ `TextLayout.paragraphs`**。
//
// ## 它补的是哪条缝
//
// 上下游各自都有断言，但它们的输入都是**手造数据**：
//
// - `ordercheck` 喂的是合成的 `VNRecognizedTextObservation`——它钉住了比较器和
//   `topYRatio` 的换算，但那些包围盒是我们自己摆的；
// - `layoutcheck` 喂的是手造的 `TextLine`——它钉住了版式重建，但那些几何也是我们自己摆的。
//
// **两头都绿推不出「真照片进去、成段的文字出来」。** 中间那一段——Vision 在真实
// 图像上给出的包围盒究竟有多高、行距多大、字宽多少——谁都没有量过，而这一段恰恰是
// 这个项目返工过两轮的地方：上一轮那套置信度阈值就是在合成图上标的，真机行为与标定不符。
//
// 这个工具把缝合上：读一张**真图**，全程走**生产代码**（`TextRecognitionService.blocks`、
// `TextLayout.paragraphs`），把识别出的视觉行和重建出来的段落并排打出来。
//
// ## 它不能证明什么
//
// 它读的是 `gen-image` 造的合成图，不是用户拍的照片。合成图的行距、字宽都太规整，
// 所以它**证明不了阈值在真实照片上够用**——那要真机（见 README「真机验证」）。
// 它能证明的是更弱但更基础的一件事：这条链子在真 Vision 输出上**跑得通**，
// 翻转没反、分栏没把单栏切碎、折行没被断成一段一句。
//
// ## 怎么跑
//
// 和 `ordercheck` 一样是 iOS 模拟器产物（`OCRImageSource` 依赖 UIKit），
// 必须经 `simctl spawn`，不能直接跑。build.sh 末尾会自动跑一遍。

var args = Array(CommandLine.arguments.dropFirst())

// `--expect N` 给了期望段数，就把它变成一道闸：对不上退非零。不给就只打印。
//
// 有个数才谈得上「验过」——只打印的话，一段正文被拆成五段、五个小节粘成一段，
// 输出看起来都差不多，没人会逐行去数。而这两个方向正是段落重建唯一的两种错法。
var expected: Int?
if let flag = args.firstIndex(of: "--expect") {
    guard flag + 1 < args.count, let value = Int(args[flag + 1]) else {
        print("❌ --expect 后面要跟一个整数")
        exit(1)
    }
    expected = value
    args.removeSubrange(flag...(flag + 1))
}

guard !args.isEmpty else {
    print("用法: paracheck [--expect N] <图片路径> [语言码...]   （默认 zh-Hans en-US）")
    exit(1)
}
let path = args[0]
let languages = args.count > 1 ? Array(args.dropFirst()) : ["zh-Hans", "en-US"]

// **方向必须走生产代码，不能在这里自己拼。** 这个工具原先直接用
// `CGImageSourceCreateImageAtIndex` 拿 `CGImage`、再传 `VNImageRequestHandler(cgImage:options:)`
// ——**没有方向**。而 iPhone 拍出来的照片几乎都带 EXIF 方向（传感器是横向的），
// `CGImageSourceCreateImageAtIndex` **不应用**它，于是这里量到的是一张**躺倒的图**：
// 每个「视觉行」的包围盒变成又高又窄的竖条，分栏判据拿到的是旋转了 90° 的几何。
//
// 后果是这一层**测的不是 App 做的事**：App 走 `OCRImageSource.from(data:)` 读方向、再
// `VNImageRequestHandler(cgImage:orientation:)` 交给 Vision，而这里漏了那一步。
// 一张真实的两栏照片在这上面跑出 29 段，看着像分栏彻底坏了——其实坏的是这个工具。
// 现在直接调生产函数，方向这件事就只有一个实现，不会再分家。
guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let source = OCRImageSource.from(data: data) else {
    print("❌ 无法读取图片: \(path)")
    exit(1)
}
let image = source.image

print("══════════════════════════════════════════")
print("文件: \((path as NSString).lastPathComponent)  (\(image.width)x\(image.height))")
print("语言: \(languages.joined(separator: ", "))")
// 方向要**打出来**：它是「同一张照片看起来完全不同」的开关，出问题时第一个要排除的变量。
// 归一化坐标只在方向被正确应用之后才有意义，所以这一行不是装饰。
print("方向: \(source.orientation.rawValue)  （EXIF，1 = 像素已正立）")
print("══════════════════════════════════════════")

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = languages
request.usesLanguageCorrection = true

let start = Date()
do {
    try VNImageRequestHandler(cgImage: source.image,
                              orientation: source.orientation,
                              options: [:]).perform([request])
} catch {
    print("❌ 识别失败: \(error)")
    exit(1)
}

// 走生产代码，不在这里抄一遍排序或翻转。
let blocks = TextRecognitionService.blocks(from: request.results ?? [])

print("\n识别到 \(blocks.count) 个视觉块，耗时 \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
print("（几何按 `TextLine` 的约定打印：归一化、y 向下为正，top=0 是画面顶边）")
print("──────────────────────────────────────────")
for block in blocks {
    let l = block.line
    print(String(format: "[top%5.1f%% x%5.1f%% w%5.1f%% h%4.1f%%] %@",
                 l.top * 100, l.minX * 100, l.width * 100, l.height * 100, l.text))
}

let paragraphs = TextLayout.paragraphs(from: blocks.map(\.line))
print("\n重建出 \(paragraphs.count) 段。")
print("──────────────────────────────────────────")
for (index, paragraph) in paragraphs.enumerated() {
    print("【第 \(index + 1) 段】\(paragraph)")
}

// 顺便把「本页自己的统计量」打出来。阈值全是相对的，所以这几个数就是这套判据
// 在这张图上的全部依据——真机行为不对时，先看这几个数是不是离谱。
//
// **必须按「块」算，不能拿整页所有行一起算。** 判段是在块内做的（`TextLayout.blocks`
// 切出来的每一栏各自成段），而分栏之后整页的行里左右两栏是**并排**的：同一条基线上
// 并排的两行，间距算出来是**负的**，于是「正常行距」会打出一个负数。那看着像代码坏了，
// 其实是这个诊断算错了范围——而它恰恰是出问题时第一个要看的数，不能是错的。
let layoutBlocks = TextLayout.blocks(in: blocks.map(\.line))
if layoutBlocks.count > 1 {
    print("\n（整页被切成 \(layoutBlocks.count) 块：分栏或通栏行所致，逐块列统计量）")
}
for (index, block) in layoutBlocks.enumerated() where block.count > 1 {
    let metrics = TextLayout.Metrics(of: TextLayout.readingOrder(block))
    let label = layoutBlocks.count > 1 ? "第 \(index + 1) 块" : "本页"
    print("\n\(label)统计量（判段依据全部取自这三个数，没有任何绝对值）：")
    print(String(format: "  正常行距 normalGap      %.4f", metrics.normalGap))
    print(String(format: "  平均字宽 characterWidth %.4f", metrics.characterWidth))
    print(String(format: "  典型右界 typicalRight   %.4f", metrics.typicalRightEdge))
}

// 断言放在最后：先让人看到几何和段落，再看到结论——对不上时上面的输出就是诊断材料。
if let expected {
    print("")
    if paragraphs.count == expected {
        print("✅ 段数 \(paragraphs.count)，与期望一致")
    } else {
        print("❌ 段数 \(paragraphs.count)，期望 \(expected)")
        if paragraphs.count > expected {
            print("   多出来的段：多半是折行的句子被判成了段间距（阈值太松）。")
        } else {
            print("   少掉的段：多半是真正的段间距没被认出来（阈值太紧，或行距分布本身歧义）。")
        }
        exit(1)
    }
}
