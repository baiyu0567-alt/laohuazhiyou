import Foundation
import Vision
import ImageIO
import CoreGraphics

// 对任意图片跑一次 OCR，按纵向位置输出文本块 + 置信度 + 高度百分比。
// 用来测真实照片（合成图请用 gen-image）。

let args = CommandLine.arguments.dropFirst()
guard !args.isEmpty else {
    print("用法: ocr <图片路径...>")
    exit(1)
}

for path in args {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        print("❌ 无法读取: \(path)")
        continue
    }

    print("\n══════════════════════════════════════════")
    print("文件: \((path as NSString).lastPathComponent)  (\(img.width)x\(img.height))")
    print("══════════════════════════════════════════")

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    // 中英混排：两个都放进去。第一个元素选模型，所以中文在前。
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: img, options: [:])
    let start = Date()
    do {
        try handler.perform([request])
    } catch {
        print("❌ 识别失败: \(error)")
        continue
    }
    let elapsed = Date().timeIntervalSince(start)

    guard let results = request.results else { continue }

    print("识别到 \(results.count) 个文本块，耗时 \(String(format: "%.2f", elapsed))s")
    print("──────────────────────────────────────────")

    // 按纵向位置排序（画面上方到下方）——辨认阅读顺序
    let sorted = results.sorted { a, b in
        a.boundingBox.origin.y > b.boundingBox.origin.y
    }
    for obs in sorted {
        guard let top = obs.topCandidates(1).first else { continue }
        let box = obs.boundingBox
        let yPct = Int((1 - box.origin.y - box.height) * 100)
        print(String(format: "[y%3d%% c%.2f] ", yPct, top.confidence) + top.string)
    }
}
