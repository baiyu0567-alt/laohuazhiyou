# ocr-bench

验证 Apple Vision (`VNRecognizeTextRequest`) 文字识别行为的命令行工具集。

## 为什么存在

PresbyFriend 的 iOS 版用 Vision 做图片 OCR。它的失败模式很隐蔽：

**`recognitionLanguages` 数组的第一个元素决定用哪个识别模型。选错则完全崩溃，
但不报错、不崩溃、不抛异常——只是安静地输出垃圾。**

实测（macOS，与 iOS 同一套 API）：

| 配置 | 中文图 | 英文图 |
|---|---|---|
| `["zh-Hans", "en-US"]` | ✅ 10/10 块正确 | ⚠️ `Tuesday` → `Tuesaay` |
| `["en-US", "zh-Hans"]` | ❌ `用法用量` → `mzms` | ✅ 正确 |
| `["en-US"]` | ❌ 同上，4 块乱码 | ✅ 正确 |
| `["zh-Hans"]` | ✅ 10/10 块正确 | ⚠️ 同第一行 |

中文模型能勉强认拉丁字母，**英文模型遇汉字直接崩**。

历史上两次「OCR 乱七八糟」都是这个成因：

- PWA MVP（`503c920`）用 Tesseract.js `chi_sim`，中文质量本就差
- Android 早期用 Latin-only 识别器硬啃中文（`4126a57` 才换成 `ChineseTextRecognizerOptions`）

**两次都是引擎选错，不是 OCR 不可行。**

另外 `.fast` 档**不支持中文**（只有 en/fr/it/de/es/pt），对中文图返回 0 个结果。
所以没有「降档换速度」的余地——必须用 `.accurate`。

设计依据见 `docs/superpowers/specs/2026-09-14-ios-v1-design.md`。

## 构建

```sh
./build.sh          # 编译到 bin/
```

需要 Xcode 命令行工具。产物在 `bin/`，不进版本库。

`ordercheck` 例外：它编的是 iOS 模拟器目标（原因见下），运行时需要一台已启动的模拟器。
没有 booted 模拟器时 `build.sh` 会明确跳过它并打印提示，不算构建失败。

## 工具

### `gen-image` — 生成中文测试图

渲染一张模拟药盒说明书的图：浅灰泛黄背景、深灰字（低对比度）、小字号、轻微模糊加噪。
刻意做成"手持拍摄"的样子，用来测苛刻条件下的识别质量。

```sh
./bin/gen-image /tmp              # 单栏说明书 → test_image.png
./bin/gen-image /tmp two-column   # 两栏同基线 → test_image_two_column.png（给 ordercheck 用）
```

第二个参数选版式，默认 `single`。同时会打印 `.accurate` 与 `.fast` 两档各自支持的语言清单。

### `ocr` — 对任意图片跑 OCR

```sh
./bin/ocr photo1.jpg photo2.jpg
```

按纵向位置排序输出文本块，附置信度和在画面中的高度百分比。用来测真实照片。

### `compare` — 对比语言配置

```sh
./bin/compare photo.jpg
```

同一张图跑 5 种语言/校正配置，并排输出，用来确认哪种配置对当前素材最好。

### `cold` — 冷启动计时

```sh
./bin/cold photo.jpg zh-Hans
```

测量某个语言首次使用的耗时（含模型准备）。**每次要用全新进程测**，否则测的是缓存。

已知行为：首次约 28–34s，之后 0.1–0.35s；按语言分别准备。

### `langcheck` — 断言识别语言规则

```sh
./bin/langcheck
```

不需要图片。它把 `RecognitionLanguage.swift` 的生产代码原文件直接编进来（见 `build.sh`），
断言 `.system` 在 zh-Hans / zh-Hant / **ZH-Hans** / zh-CN 下都返回 `["zh-Hans"]`，其余返回
`["en-US"]`，并含一条「中文场景首位不是 en-US」的回归断言。全部通过时退出码为 0。

### `ordercheck` — 断言文本块阅读顺序

```sh
./bin/ordercheck
```

不需要图片，也不需要 OCR。它把 `TextRecognitionService.blocks(from:)` 这个生产比较器
原文件直接编进来，断言：同一基线上（`origin.y` 相等）的两个块按 `minX` 升序——**左栏在前**；
把输入顺序倒过来结果不变；主序（画面自上而下）不被平局分支盖掉；同一输入重排 200 次结果一致。

为什么不能像别的工具一样编成 macOS 可执行：比较器的输入类型是 `VNRecognizedTextObservation`，
只有 iOS SDK 有。所以 `build.sh` 把它编成 `arm64-apple-ios16.0-simulator`，
用 `xcrun simctl spawn booted ./bin/ordercheck` 跑。

对应的测试图是 `gen-image` 的两栏版式：

```sh
./bin/gen-image /tmp two-column   # 写出 /tmp/test_image_two_column.png
```

两个栏目标题画在同一条基线上，正是平局分支要处理的形状。

## 用途：回归测试

`compare` 的固定配置输出可直接用于断言。建议固化的两条：

1. 中文图 + `["zh-Hans"]` → 识别率达标
2. **中文图 + `["en-US"]` → 必须失败**

第 2 条是把已知陷阱钉死，防止将来有人「优化」语言列表顺序时静默搞坏。

## 局限

- 跑在 macOS 上。Vision 在 iOS 和 macOS 是同一套 API，**但结果不保证逐字相同**，
  设备端仍应复验。
- `gen-image` 产出的是合成图，不含真实照片的透视畸变、光照不均、反光、复杂版式。
  真实素材请用 `ocr` / `compare` 直接喂照片。
- 无法区分「首次 28s 是网络下载还是本地编译」——两者都会写文件缓存。
  需真机断网实测。
