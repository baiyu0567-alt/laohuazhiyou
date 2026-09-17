import Foundation
import Vision
import CoreGraphics
import CoreText
import AppKit

// 渲染一张模拟"药盒说明书拍摄"的测试图：
// 浅灰泛黄背景、深灰字（低对比度）、小字号、轻微模糊加噪。
// 刻意做成手持拍摄的样子，用来测苛刻条件下的识别质量。
//
// `lines` 由调用方给，因为两种版式共用这套渲染：`single` 是小标题 + 单行正文的
// 说明书，`wrapped` 是一段话折了五行。**两种版式要一起看**——段落重建有两个方向，
// 漏判段间距（该断的没断）和误判段间距（折行的句子被拆散），只测其中一种，
// 把阈值往另一边调都「通过」。

/// 药盒说明书的行：小标题 26pt，正文 15pt。刻意做成**小标题只有一行正文**的紧凑版式，
/// 因为那是行距分布最容易被误导的一种——大小行距几乎一半一半，中位数落在哪边都不稳。
let prescriptionLines: [(String, CGFloat)] = [
    ("用法用量", 26),
    ("口服。一次1片，一日3次，饭后服用。", 15),
    ("不良反应", 26),
    ("偶见皮疹、瘙痒、恶心、胃部不适。", 15),
    ("禁忌", 26),
    ("对本品成分过敏者禁用。孕妇慎用。", 15),
    ("贮藏", 26),
    ("密封，在阴凉干燥处（不超过20℃）保存。", 15),
    ("有效期", 26),
    ("24个月。请于包装所示日期前使用。", 15),
]

/// 一段话折成五行，行距均匀、没有小标题。**期望结果是整整一段**。
/// 这是上面那套判据的危险方向：阈值调松一点，这里就会被拆成五段。
let wrappedLines: [(String, CGFloat)] = [
    ("口服。成人一次1片，一日3次，饭后服用。请勿超", 15),
    ("过推荐剂量。若症状持续或加重，请停药并咨询", 15),
    ("医师。儿童用量请遵医嘱，孕妇及哺乳期妇女慎", 15),
    ("用。对本品任一成分过敏者禁用。请置于儿童不", 15),
    ("能触及的地方。密封，在阴凉干燥处保存。", 15),
]

func makeTestImage(width: Int, height: Int, lines: [(String, CGFloat)]) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    // 浅灰背景 —— 模拟拍了泛黄的说明书，不是纯白
    ctx.setFillColor(CGColor(red: 0.87, green: 0.86, blue: 0.82, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // 深灰字而非纯黑 —— 低对比度，真实照片常见
    let textColor = CGColor(red: 0.28, green: 0.27, blue: 0.25, alpha: 1)

    var y = CGFloat(height) - 70
    for (index, entry) in lines.enumerated() {
        let (text, size) = entry
        let font = CTFontCreateWithName("PingFang SC" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 60, y: y)
        CTLineDraw(line, ctx)

        // 走到下一行的基线。**用的是「下一行」的字号，不是刚画完的这一行。**
        //
        // 这里原先写的是 `y -= size * 2.6`（当前行），方向是反的：两行基线的距离由
        // **下一行**的 space-before + leading 决定——标题上方那段空白属于标题自己，
        // 不属于它上面那行正文。用当前行的字号，就把大空白放到了标题**之后**、
        // 小空白放到了标题**之前**，而真实排版恰好相反。
        //
        // 这不是审美问题，是这张图还能不能用来判事的问题：`paracheck` 的段落重建
        // 就是靠行距分布判段的，行距模式一反，它就会输出「正文和小标题粘在一起」——
        // 看起来像代码坏了，其实是图不对。合成图是拿来**标定**的，它的版式必须先
        // 是真实版式。
        if index + 1 < lines.count {
            y -= lines[index + 1].1 * 2.6
        }
    }

    guard let base = ctx.makeImage() else { return nil }
    return degraded(base)
}

/// 「手持拍摄」的那一层退化：轻微模糊 + 极轻噪声。
///
/// 抽出来是因为**每一张夹具都该过这一道**——两栏图原先没有，于是它比别的夹具干净，
/// 而 `paracheck` 拿它下结论时，那个结论就比别的夹具更乐观。
func degraded(_ base: CGImage) -> CGImage? {
    let ci = CIImage(cgImage: base)

    // 轻微模糊 —— 模拟手持拍摄的对焦不完美
    let blurred = ci.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8])
        .cropped(to: ci.extent)

    let cictx = CIContext()

    // 极轻微噪声。注意 alpha 必须压到很低（0.05），
    // 否则 CIRandomGenerator 的 alpha 为 1，composited(over:) 会把整张图盖住。
    guard let generator = CIFilter(name: "CIRandomGenerator"),
          let rawNoise = generator.outputImage else {
        return cictx.createCGImage(blurred, from: ci.extent) ?? base
    }

    let noise = rawNoise
        .cropped(to: ci.extent)
        .applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.05),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])
        .composited(over: blurred)

    return cictx.createCGImage(noise, from: ci.extent) ?? base
}

// ── 两栏的两种图，用途不同，别混 ──

/// 一张「说明书页」的空白画布：泛黄浅灰底 + 深灰字。
func pageContext(width: Int, height: Int) -> CGContext? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 0.87, green: 0.86, blue: 0.82, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx
}

let pageTextColor = CGColor(red: 0.28, green: 0.27, blue: 0.25, alpha: 1)

/// 画一行，**返回它的排版宽度**——题头要居中就得先知道宽度，不能靠估。
@discardableResult
func drawLine(_ text: String, size: CGFloat, x: CGFloat, baseline: CGFloat,
              in ctx: CGContext, color: CGColor = pageTextColor) -> CGFloat {
    let font = CTFontCreateWithName("PingFang SC" as CFString, size, nil)
    let attr = NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: color,
    ])
    let line = CTLineCreateWithAttributedString(attr)
    ctx.textPosition = CGPoint(x: x, y: baseline)
    CTLineDraw(line, ctx)
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// 两栏**同基线平局**的图：左右各一个标题，画在同一个 y 上。
///
/// 用途只有一个：给人用 `./bin/ocr` 看**真实的 Vision 会不会给出完全相等的 `origin.y`**
/// （`ordercheck` 断言的是「**若**相等则左栏在前」这条规则，规则本身不依赖谁产生这些块）。
/// **这不是两栏版式**——它每栏只有一行，测不了分栏。要看分栏请用下面那张。
/// x 坐标与 ordercheck 驱动里的归一化坐标对应：60/1200 = 0.05，660/1200 = 0.55。
func makeColumnTieImage(width: Int, height: Int) -> CGImage? {
    guard let ctx = pageContext(width: width, height: height) else { return nil }
    let y = CGFloat(height) / 2
    drawLine("左栏标题", size: 26, x: 60, baseline: y, in: ctx)
    drawLine("右栏标题", size: 26, x: 660, baseline: y, in: ctx)
    return ctx.makeImage()
}

/// **一条通栏标题 + 左右两栏正文**——真实的说明书背面版式。
///
/// 这一张是补出来的，因为**旧的「两栏图」根本不是两栏版式**（见上面那张）。于是
/// 「分栏在真图上到底成不成立」这一环，`paracheck` 从来没有量过，而真机报回来的
/// 正是分栏失败：正文左右跳（左栏第一行、右栏第一行、左栏第二行……）。
///
/// **通栏标题是必需的，不是装饰。** 它横跨栏间距，把所有行的横向并集连成一片——
/// 而「按并集空档找栏缝」正是 `TextLayout.columns` 当时的做法，于是它一条缝都找不到，
/// 整页退回单栏，再按基线排就必然左右跳。真实说明书恰恰都有这样一条标题：
/// **夹具里少了它，就等于绕开了唯一会出问题的那种形状。**
func makeTwoColumnImage(width: Int, height: Int) -> CGImage? {
    guard let ctx = pageContext(width: width, height: height) else { return nil }

    // 左栏 x=60（0.05）、右栏 x=660（0.55），与 ordercheck 的合成坐标同一组数，
    // 栏间距留在 0.40–0.55 之间。
    let leftColumn = [
        "口服。成人一次1片，一日3次，饭后服用。",
        "请勿超过推荐剂量，若症状持续或加重，",
        "请停药并咨询医师。儿童用量请遵医嘱，",
        "孕妇及哺乳期妇女慎用。对本品任一成分",
        "过敏者禁用。请置于儿童不能触及处。",
    ]
    let rightColumn = [
        "不良反应：偶见皮疹、瘙痒、恶心、胃部",
        "不适等，一般停药后可自行恢复。若出现",
        "严重不良反应请立即就医。贮藏：密封，",
        "在阴凉干燥处（不超过20℃）保存。有效",
        "期：24个月，请于包装所示日期前使用。",
    ]

    // 题头先量宽再居中——**必须真的跨过栏间距**（0.40–0.55），否则这张图测不到要测的东西。
    let titleSize: CGFloat = 26
    let titleText = "复方氨酚烷胺片说明书（请仔细阅读）"
    let titleFont = CTFontCreateWithName("PingFang SC" as CFString, titleSize, nil)
    let titleAttr = NSAttributedString(string: titleText, attributes: [
        .font: titleFont,
        .foregroundColor: pageTextColor,
    ])
    let titleWidth = CGFloat(CTLineGetTypographicBounds(
        CTLineCreateWithAttributedString(titleAttr), nil, nil, nil))

    let bodySize: CGFloat = 15
    let bodyStep = bodySize * 2.6          // 与单栏夹具同一条行距规则
    let titleBaseline = CGFloat(height) - 70
    let firstBodyBaseline = titleBaseline - titleSize * 2.6

    // 题头：居中
    drawLine(titleText, size: titleSize,
             x: (CGFloat(width) - titleWidth) / 2, baseline: titleBaseline, in: ctx)

    // 两栏：同一条水平基准线起步，行距相同
    for (index, text) in leftColumn.enumerated() {
        drawLine(text, size: bodySize, x: 60,
                 baseline: firstBodyBaseline - CGFloat(index) * bodyStep, in: ctx)
    }
    for (index, text) in rightColumn.enumerated() {
        drawLine(text, size: bodySize, x: 660,
                 baseline: firstBodyBaseline - CGFloat(index) * bodyStep, in: ctx)
    }

    guard let base = ctx.makeImage() else { return nil }
    return degraded(base)
}

// ── 报告两档各自支持的语言 ──

func reportLanguages() {
    for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        let name = level == .accurate ? ".accurate" : ".fast"
        print("═══ \(name) 档支持的语言 ═══")
        guard let langs = try? request.supportedRecognitionLanguages() else {
            print("  (无法获取)\n")
            continue
        }
        print("  \(langs.joined(separator: ", "))")
        let hasChinese = langs.contains { $0.hasPrefix("zh") }
        print("  含中文? \(hasChinese ? "✅ 是" : "❌ 否")\n")
    }
}

// ── main ──

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
// 第二个参数选版式：
//   single      单栏说明书（小标题 + 单行正文），默认
//   wrapped     一段话折五行、无小标题 —— 段落重建**危险方向**的对照图
//   two-column  两栏同基线，给人工用 ./bin/ocr 验（ordercheck 用的是同几何的合成坐标，不读它）
let layout = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "single"
reportLanguages()

let W = 1200, H = 900
let fileName: String
let img: CGImage
switch layout {
case "single":
    fileName = "test_image.png"
    guard let made = makeTestImage(width: W, height: H, lines: prescriptionLines) else {
        print("❌ 测试图生成失败")
        exit(1)
    }
    img = made
case "wrapped":
    fileName = "test_image_wrapped.png"
    guard let made = makeTestImage(width: W, height: H, lines: wrappedLines) else {
        print("❌ 测试图生成失败")
        exit(1)
    }
    img = made
case "two-column":
    fileName = "test_image_two_column.png"
    guard let made = makeTwoColumnImage(width: W, height: H) else {
        print("❌ 测试图生成失败")
        exit(1)
    }
    img = made
case "column-tie":
    fileName = "test_image_column_tie.png"
    guard let made = makeColumnTieImage(width: W, height: H) else {
        print("❌ 测试图生成失败")
        exit(1)
    }
    img = made
default:
    print("❌ 未知版式: \(layout)（可选 single / wrapped / two-column / column-tie）")
    exit(1)
}

let outPath = (outDir as NSString).appendingPathComponent(fileName)
if let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outPath) as CFURL, "public.png" as CFString, 1, nil) {
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("测试图已保存: \(outPath) (\(W)x\(H))")
    print("用 ./bin/ocr \(outPath) 或 ./bin/compare \(outPath) 检验识别结果")
} else {
    print("❌ 写入失败: \(outPath)")
    exit(1)
}
