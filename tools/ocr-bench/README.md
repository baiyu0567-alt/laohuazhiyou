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

`ordercheck` 例外：它编的是 iOS 模拟器目标（原因见下），运行时需要一台已启动的 iOS 模拟器。
没有可用的 iOS 模拟器时 `build.sh` 会明确跳过它并打印原因，不算构建失败。

## 工具

### `gen-image` — 生成中文测试图

渲染一张模拟药盒说明书的图：浅灰泛黄背景、深灰字（低对比度）、小字号、轻微模糊加噪。
刻意做成"手持拍摄"的样子，用来测苛刻条件下的识别质量。

```sh
./bin/gen-image /tmp              # 单栏说明书 → test_image.png
./bin/gen-image /tmp two-column   # 两栏同基线 → test_image_two_column.png（给人工验，ordercheck 不读它）
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

不需要图片。它把 `RecognitionLanguage.swift` 与 `RecognitionLanguageAudit.swift` 的生产代码
原文件直接编进来（见 `build.sh`），共 176 条断言，覆盖八组规则。**「本机 Vision 支持清单」
以参数注入**，用的是真机实测的 33 种那份固定清单，所以这套断言不依赖跑它的机器。

1. **设备语言 → Vision 码 `systemLanguageCode`**：`de-AT` → `de-DE`、裸 `ja` → `ja-JP`、
   大小写不敏感；中文/粤语**按文字分档**——**显式的 `-Hans`/`-Hant` 子标签压过地区**
   （`zh-Hans-HK` / `zh-Hans-MO` / `zh-Hans-TW` 都是简体，`zh-Hant-CN` / `zh-Hant-MY` 都是
   繁体），只有没写文字时才拿地区推断（`zh-TW`/`zh-HK`/`zh-MO` 判繁体）；把清单倒序结果
   不变（证明分档不靠 `hasPrefix` 撞对）；设备清单里没有繁体时落简体；设备语言 Vision
   不认识（冰岛语）落英文，而不是递一个不存在的码
   > `zh-Hans-HK` / `zh-Hans-MO` 这几条是**补一个真出过的缺陷**：`Locale.availableIdentifiers`
   > 里确实有 `zh_Hans_HK` / `zh_Hans_MO`，iOS 上用户选「中文（简体）」加香港或澳门地区给的
   > 就是它们，而只看地区的实现会把它们判成繁体。补之前那 142 条里没有这两条，所以那个缺陷
   > 是**全绿通过**的——这也说明这套断言只覆盖它想到的情况。
2. **`visionLanguages`**：跟随系统取设备那一档；手动档与设备语言**完全无关**
   （德语设备 + 手动中文 → `zh-Hans`）；手动码本机不支持时落 `["en-US"]`
3. **`effectiveLanguageCode` 与 `visionLanguages` 一致**：两者分家的话，设置页的 ❗
   和阅读页的提示会描述一件实际没发生的事
4. **旧存储值迁移 `stored(from:supported:)`**：`chinese`/`english`/`german`… 那批档位名
   映射到码，`system`/`followApp` 都映射到 `.followSystem`；来路不明的码（`is-IS`）返回 nil。
   另含一条「旧档位名不查 `supported`」——它固定给出自己的码，能不能用由使用那一刻兜底
5. **往返**：33 个码逐个存得下、读得回、且真的喂给 Vision
6. **选项名 `displayName(for:)`**：5 个手工覆盖断言字面值；其余靠 `Locale` 生成，
   只断言性质（无空名、两两不撞名）——**不断言字面值**，那取决于系统 locale 数据，
   写死会让测试换台机器就假报错
7. **回归**：10 个中文/粤语设备语言都不许把 `en-US` 放首位（英文模型遇汉字静默输出垃圾，
   实测 `用法用量` → `mzms`）；德语设备不再拿到英文（改动前的默认档就是那样）

全部通过时退出码为 0。

### `ordercheck` — 断言文本块阅读顺序

```sh
./bin/ordercheck
```

不需要图片，也不需要 OCR。它把 `TextRecognitionService.blocks(from:)` 这个生产比较器
原文件直接编进来，断言：同一基线上（`origin.y` 相等）的两个块按 `minX` 升序——**左栏在前**；
把输入顺序倒过来结果不变；主序（画面自上而下）不被平局分支盖掉；同一输入重排 200 次结果一致。

它必须编成 iOS 模拟器目标（比较器的输入类型是 `VNRecognizedTextObservation`），所以跑不了
就不能直接执行——见 `build.sh` 里那套按 UDID `simctl spawn` 的逻辑。
`RecognitionLanguage.swift` 也在它的编译清单里：`TextRecognitionService` 的语言码目录
（`OCRSupportedLanguageCodes.sorted`）要调 `displayName(for:)`，少了这个文件整个编译不过。

为什么不能像别的工具一样编成 macOS 可执行：比较器的输入类型是 `VNRecognizedTextObservation`，
只有 iOS SDK 有。所以 `build.sh` 把它编成 `arm64-apple-ios16.0-simulator`，
用 `xcrun simctl spawn <已启动的 iOS 模拟器 UDID> ./bin/ordercheck` 跑。它是**模拟器产物，
不能在 shell 里直接执行**（会报 `DYLD_ROOT_PATH not set for simulator program`）。
UDID 由 `build.sh` 按运行时分组自己挑，**只认 iOS**——`simctl spawn booted` 会把 watchOS /
tvOS / visionOS 的设备一起列为候选，挑错了就是一次假失败（编出来的东西跑不起来）。
没有可用的 iOS 模拟器时 `build.sh` 会明确跳过并说明原因，不算构建失败。

平局分支对应的测试图是 `gen-image` 的两栏版式，**但 ordercheck 不读它**：上面几条断言喂的是
与那张图几何一致的合成坐标（左栏 x=0.05、右栏 x=0.55），不碰像素、不碰 Vision——这正是它能
离线跑的原因。图是给**人工**验的：

```sh
./bin/gen-image /tmp two-column   # 写出 /tmp/test_image_two_column.png
./bin/ocr /tmp/test_image_two_column.png   # 看真实 Vision 给两个标题各报什么 origin.y
```

两个栏目标题画在同一条基线上，正是平局分支要处理的形状。ordercheck 断言的是「**若**两个块
`origin.y` 相等，则左栏在前」这条规则；真实 Vision 是否真会给出完全相等的 `origin.y`，本仓库
没有测过（也不需要——规则本身跟谁产生这些块无关）。

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
