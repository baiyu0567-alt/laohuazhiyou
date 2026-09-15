import Foundation
import Vision
import CoreGraphics
import CoreText
import AppKit

// 渲染一张模拟"药盒说明书拍摄"的测试图：
// 浅灰泛黄背景、深灰字（低对比度）、小字号、轻微模糊加噪。
// 刻意做成手持拍摄的样子，用来测苛刻条件下的识别质量。

func makeTestImage(width: Int, height: Int) -> CGImage? {
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

    let lines: [(String, CGFloat)] = [
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

    var y = CGFloat(height) - 70
    for (text, size) in lines {
        let font = CTFontCreateWithName("PingFang SC" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 60, y: y)
        CTLineDraw(line, ctx)
        y -= size * 2.6
    }

    guard let base = ctx.makeImage() else { return nil }

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
reportLanguages()

let W = 1200, H = 900
guard let img = makeTestImage(width: W, height: H) else {
    print("❌ 测试图生成失败")
    exit(1)
}

let outPath = (outDir as NSString).appendingPathComponent("test_image.png")
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
