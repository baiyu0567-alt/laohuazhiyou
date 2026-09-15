import Foundation
import Vision

// 断言 `TextRecognitionService.blocks(from:)` 的阅读顺序。
//
// 这是本工具集里**第二个**直接编生产代码原文件、不复制不镜像的测试（第一个是 langcheck）。
// build.sh 把 `TextRecognitionService.swift` 和它依赖的 `OCRImageSource.swift` 原样编进来，
// 所以这里测的是真比较器，不是复刻的一份。
//
// 为什么必须在 iOS 上跑：比较器的输入类型是 `VNRecognizedTextObservation`，UIKit/Vision
// 的这部分只有 iOS SDK 有。所以 build.sh 把它编成 `arm64-apple-ios16.0-simulator`，
// 运行时用 `xcrun simctl spawn booted`。
//
// 为什么用子类而不是直接 `VNRecognizedTextObservation(boundingBox:)`：
// 那个初始化器能建出对象、boundingBox 也对，但 `topCandidates(_:)` 返回空数组
// （文字挂在私有的 `CRImageReaderOutput` 上，没有任何公开或 KVC 的入口能塞进去）。
// 比较器最后一步是 `compactMap { $0.topCandidates(1).first }`，候选为空就会被整个丢掉，
// 结果恒为 `[]`——顺序根本没得断言。所以这里用子类覆写 `boundingBox` 和 `topCandidates`，
// 造出**形状与真实观测一致**的输入；被测的仍然只有生产比较器本身。
//
// 几何与 gen-image 的 `two-column` 版式对应：左栏 x=60/1200=0.05，右栏 x=660/1200=0.55，
// 两条标题画在同一条基线上（同一个 y）。

final class FakeText: VNRecognizedText {
    private let s: String
    init(_ s: String) { self.s = s; super.init() }
    required init?(coder: NSCoder) { fatalError() }
    override var string: String { s }
}

final class FakeObservation: VNRecognizedTextObservation {
    private let t: String
    private let box: CGRect
    init(text: String, box: CGRect) { self.t = text; self.box = box; super.init() }
    required init?(coder: NSCoder) { fatalError() }
    override var boundingBox: CGRect { box }
    override func topCandidates(_ maxCandidateCount: Int) -> [VNRecognizedText] { [FakeText(t)] }
}

// ── 断言脚手架 ──

var failures = 0

func expect(_ actual: [String], _ expected: [String], _ label: String) {
    if actual == expected {
        print("  ✅ \(label) → \(actual)")
    } else {
        print("  ❌ \(label) → 实际 \(actual)，期望 \(expected)")
        failures += 1
    }
}

func order(_ observations: [VNRecognizedTextObservation]) -> [String] {
    TextRecognitionService.blocks(from: observations).map(\.text)
}

/// 同一条基线上的两栏标题。`box` 的 y 完全相同，是这条测试的全部意义所在。
func sameBaselinePair(reversed: Bool = false) -> [VNRecognizedTextObservation] {
    let left = FakeObservation(text: "左栏标题",
                              box: CGRect(x: 0.05, y: 0.60, width: 0.30, height: 0.05))
    let right = FakeObservation(text: "右栏标题",
                                box: CGRect(x: 0.55, y: 0.60, width: 0.30, height: 0.05))
    return reversed ? [right, left] : [left, right]
}

let pairY = sameBaselinePair().map { $0.boundingBox.origin.y }
print("  （两条标题的 origin.y：\(pairY[0]) / \(pairY[1]) — 相等才算测到平局分支）")
if pairY[0] == pairY[1] {
    print("  ✅ 前置：两条标题 origin.y 相等")
} else {
    print("  ❌ 前置：两条标题 origin.y 不相等，这条测试没有意义")
    failures += 1
}

// 1. 平局时左栏在前（gen-image 的 two-column 版式断言的就是这条）
expect(order(sameBaselinePair()), ["左栏标题", "右栏标题"], "同基线：左栏在前")

// 2. 把输入顺序倒过来，结果必须一样——顺序是排出来的，不是碰巧留下的
expect(order(sameBaselinePair(reversed: true)), ["左栏标题", "右栏标题"],
       "同基线（输入反向）：左栏仍在前")

// 3. 主序仍然是「上到下」：y 大的在前，平局分支不得把它盖掉
let top = FakeObservation(text: "上", box: CGRect(x: 0.05, y: 0.80, width: 0.30, height: 0.05))
let bottom = FakeObservation(text: "下", box: CGRect(x: 0.05, y: 0.30, width: 0.30, height: 0.05))
expect(order([bottom, top]), ["上", "下"], "主序：y 大的在前")

// 4. 三个同 y 的块给乱序，必须排成 minX 升序（左 → 中 → 右）
let triple = [
    FakeObservation(text: "右", box: CGRect(x: 0.70, y: 0.45, width: 0.20, height: 0.05)),
    FakeObservation(text: "左", box: CGRect(x: 0.05, y: 0.45, width: 0.20, height: 0.05)),
    FakeObservation(text: "中", box: CGRect(x: 0.38, y: 0.45, width: 0.20, height: 0.05)),
]
expect(order(triple), ["左", "中", "右"], "三个同 y：按 minX 升序")

// 5. 两遍排序结果相同——`sorted(by:)` 不保证稳定，比较器若不是严格弱序，
//    同一批输入每次的顺序都可能不同。这条钉的是确定性本身。
let first = order(sameBaselinePair(reversed: true))
var stable = true
for _ in 0..<200 where order(sameBaselinePair(reversed: true)) != first { stable = false }
if stable {
    print("  ✅ 确定性：200 次重排结果一致 → \(first)")
} else {
    print("  ❌ 确定性：同一输入重排后顺序变了")
    failures += 1
}

// 6. 混排：上下的块 + 一条同 y 的平局，确认平局只影响平局的那两个
let mixed = [
    FakeObservation(text: "底部", box: CGRect(x: 0.05, y: 0.20, width: 0.30, height: 0.05)),
    FakeObservation(text: "右栏标题", box: CGRect(x: 0.55, y: 0.60, width: 0.30, height: 0.05)),
    FakeObservation(text: "左栏标题", box: CGRect(x: 0.05, y: 0.60, width: 0.30, height: 0.05)),
    FakeObservation(text: "顶部", box: CGRect(x: 0.05, y: 0.90, width: 0.30, height: 0.05)),
]
expect(order(mixed), ["顶部", "左栏标题", "右栏标题", "底部"], "混排：主序 + 局部平局")

// 7. 顺带钉住 topYRatio 的换算（1 在画面顶部，0 在底部）
let ratios = TextRecognitionService.blocks(from: [top, bottom]).map(\.topYRatio)
if ratios == [1.0 - (0.80 + 0.05), 1.0 - (0.30 + 0.05)] {
    print("  ✅ topYRatio：\(ratios)")
} else {
    print("  ❌ topYRatio：实际 \(ratios)")
    failures += 1
}

if failures == 0 {
    print("\n全部通过")
} else {
    print("\n失败 \(failures) 项")
    exit(1)
}
