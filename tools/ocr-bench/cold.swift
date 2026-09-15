import Foundation
import Vision
import ImageIO
import CoreGraphics

// 测量某语言首次使用的耗时（含模型准备）。
// 必须在全新进程里跑，否则测到的是缓存。

let args = CommandLine.arguments.dropFirst()
guard args.count >= 2 else {
    print("用法: cold <图片路径> <语言代码>")
    print("例:   cold /tmp/test_image.png zh-Hans")
    exit(1)
}

let path = args[args.startIndex]
let lang = args[args.startIndex + 1]

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("❌ 无法读取: \(path)")
    exit(1)
}

let t0 = Date()
let r = VNRecognizeTextRequest()
r.recognitionLevel = .accurate
r.recognitionLanguages = [lang]
r.usesLanguageCorrection = true
let h = VNImageRequestHandler(cgImage: img, options: [:])
try? h.perform([r])
print(String(format: "  [%@] 首次(含模型加载): %.2fs, %d 块",
             lang, Date().timeIntervalSince(t0), r.results?.count ?? 0))
