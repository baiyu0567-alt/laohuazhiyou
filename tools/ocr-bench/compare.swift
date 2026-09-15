import Foundation
import Vision
import ImageIO
import CoreGraphics

// 同一张图跑 5 种语言配置并排输出，用来确认哪种配置对当前素材最好，
// 也用来固化回归断言（中文图 + ["en-US"] 必须失败）。

struct Config {
    let name: String
    let langs: [String]
    let correct: Bool
}

let configs: [Config] = [
    Config(name: "zh-Hans+en-US, 校正",   langs: ["zh-Hans", "en-US"], correct: true),
    Config(name: "en-US+zh-Hans, 校正",   langs: ["en-US", "zh-Hans"], correct: true),
    Config(name: "en-US only, 校正",       langs: ["en-US"],           correct: true),
    Config(name: "zh-Hans only, 校正",     langs: ["zh-Hans"],         correct: true),
    Config(name: "en-US only, 不校正",     langs: ["en-US"],           correct: false),
]

func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func run(_ img: CGImage, _ cfg: Config) -> (blocks: Int, time: Double, text: [String]) {
    let r = VNRecognizeTextRequest()
    r.recognitionLevel = .accurate
    r.recognitionLanguages = cfg.langs
    r.usesLanguageCorrection = cfg.correct

    let h = VNImageRequestHandler(cgImage: img, options: [:])
    let t0 = Date()
    try? h.perform([r])
    let dt = Date().timeIntervalSince(t0)

    let sorted = (r.results ?? []).sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
    let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
    return (lines.count, dt, lines)
}

let images = CommandLine.arguments.dropFirst()
guard !images.isEmpty else { print("用法: compare <图...>"); exit(1) }

for path in images {
    guard let img = load(path) else { print("❌ \(path)"); continue }
    print("\n\n██████████████████████████████████████████████████████")
    print("  \((path as NSString).lastPathComponent)")
    print("██████████████████████████████████████████████████████")

    for cfg in configs {
        let res = run(img, cfg)
        print("\n───── \(cfg.name)  ──  \(res.blocks) 块, \(String(format: "%.2f", res.time))s ─────")
        for line in res.text {
            print("  \(line)")
        }
    }
}
