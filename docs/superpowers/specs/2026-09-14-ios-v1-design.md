# PresbyFriend iOS v1 设计

日期：2026-09-14
状态：待实现

## 背景

Android 版已接近发布（v9，target SDK 36，每日限制已启用，Play Store 素材齐备）。
iOS 版有一个可用但不完整的骨架（1484 行 Swift），本次目标是把核心链路补齐。

Android 的核心能力是「在任何 app 里读字」，靠 `AccessibilityService` + `takeScreenshot()`
实现全局悬浮按钮。**iOS 没有公开 API 能做这件事**，因此 iOS 不是 Android 的平移，
必须换一套触达模型。

## 现状核实

### 工具链（已验证）

| 项 | 版本 |
|---|---|
| Xcode | 27.0 (27A266a) |
| Swift | 6.4 |
| iOS SDK | 27.0 |
| 模拟器 runtime | iOS 26.5 |
| 部署目标 | 26.5 → **改为 16.0**（见「已决事项 1」） |
| 构建 | ✅ BUILD SUCCEEDED，模拟器安装启动截图正常 |

工程使用 Xcode 16+ 的 `PBXFileSystemSynchronizedRootGroup`：新增 `.swift` 文件
自动被工程收录，**不需要改 `project.pbxproj`**。

### Android 入口（从代码核实，共 6 个）

| # | 入口 | 实现 |
|---|---|---|
| 1 | 放大镜 | 相机 + 缩放 + 手电筒（纯数字放大，无 OCR） |
| 2 | 悬浮按钮 | `AccessibilityService` + `takeScreenshot()` → OCR |
| 3 | 分享 | `ACTION_SEND` text/plain、text/* |
| 4 | 选中文字 | `ACTION_PROCESS_TEXT` |
| 5 | 剪贴板 | 悬浮按钮触发后读取 |
| 6 | 快捷设置磁贴 | `QuickSettingsTileService` |

### iOS 入口现状

| 入口 | 状态 |
|---|---|
| 放大镜 | ✅ 已有（`AVCaptureSession` + `DataScannerViewController` Live Text） |
| 分享 | ⚠️ 只有 text/URL，**图片未接** |
| 剪贴板 | ⚠️ 已有但触发系统弹窗（见下） |
| 拍照 / 选图 | ❌ 无 |
| Siri 快捷指令 | ⚠️ 半成品（`SiriActivity` 只做了 donate） |
| 控制中心 / 主屏快捷指令 | ❌ 无 |

## 关键实证发现

这些结论来自本次在 macOS 上对 `VNRecognizeTextRequest` 的实测（iOS 与 macOS 同一套 API）。
实验脚本保留在 `/tmp/ocrtest/`（`compare.swift`、`cold.swift`、`ocr.swift`），可复跑。

### 发现 1：语言模型的第一个元素决定用哪个模型，选错则完全崩溃

`recognitionLanguages` 数组的第一个元素选中主模型。实测同一张图：

| 配置 | 中文图 | 英文图 |
|---|---|---|
| `["zh-Hans", "en-US"]` | ✅ 10/10 块正确 | ⚠️ `Tuesday` → `Tuesaay` |
| `["en-US", "zh-Hans"]` | ❌ `用法用量` → `mzms` | ✅ 正确 |
| `["en-US"]` | ❌ 同上，4 块乱码 | ✅ 正确 |
| `["zh-Hans"]` | ✅ 10/10 块正确 | ⚠️ 同第一行 |

**中文模型能勉强认拉丁字母，英文模型遇汉字直接崩。**

失败代价是「完全不可用」而非「略差」，且**不报错、不崩溃，只安静输出垃圾**。

这解释了历史上两次「OCR 乱七八糟」的成因：
- PWA MVP（`503c920`）用 Tesseract.js `chi_sim`，中文质量本就差
- Android 早期用 Latin-only 识别器硬啃中文，`4126a57` 才换成 `ChineseTextRecognizerOptions`

**两次都是引擎选错，不是 OCR 不可行。**

### 发现 2：`.fast` 档不支持中文

| 档位 | 支持语言 |
|---|---|
| `.accurate` | 32 种，含 `zh-Hans`/`zh-Hant`/`yue-Hans`/`ja-JP`/`ko-KR` |
| `.fast` | 只有 en/fr/it/de/es/pt |

实测 `.fast` 对中文图返回 **0 个结果**。因此任何「为实时性降档」的方案在中文场景直接失效。

### 发现 3：性能

| 情况 | 耗时 |
|---|---|
| 首次使用某语言模型（一次性） | 约 28–34s |
| 之后每次 | 0.1–0.35s |

按语言分别准备：实测本机上 ja-JP/ko-KR/th-TH 冷启动 0.2–0.4s（模型已在本地），
`ar-SA` 冷启动 34.20s 后降为 0.24s。

`/System/Library/AssetsV2/com_apple_MobileAsset_LinguisticData` 下 68 个资产目录的属主是
`_nsurlsessiond`（后台下载守护进程），说明**部分语言模型是按需获取的**。

**未验证**：那 34 秒是网络下载还是本地编译。若为下载，首次使用需联网。

### 发现 4：置信度不可靠

中文模型误识英文得到的 `Tuesaay` 置信度为 0.50，与正确结果同档。
**因此不能用「跑两遍按置信度选」来自动判定语言。**

## 明确不做的事（YAGNI）

| 不做 | 理由 |
|---|---|
| 放大镜内实时 OCR | Android 已实证否决（`3fb291a`：未对焦帧产生垃圾且干扰放大）；iOS 上 `DataScannerViewController` 有 A12 硬件门槛；`.fast` 档不支持中文，无降档空间 |
| 悬浮按钮 | iOS 无公开 API |
| 跑两遍 OCR 按置信度选语言 | 发现 4：置信度不可靠，会选错 |
| 图像对比度/亮度增强 | 本次范围外；若后续需要「看图」能力再评估 |
| Siri 快捷指令完善 | v1 已有半成品 `SiriActivity`，不扩展 |
| 控制中心 / 主屏快捷指令 | v1 不做 |
| Safari 扩展 | v1 不做 |
| 内购相关改动 | StoreKit 2 已在，本次不动 |

## 功能框架

### 入口层（3 个）

| # | 入口 | 触发 | 处理 |
|---|---|---|---|
| 1 | 剪贴板 | App 内大字按钮 | 文本 → 阅读模式 |
| 2 | 分享 | 任意 app 分享面板 | 文本 / URL / 图片 → 阅读模式 |
| 3 | 拍照 / 选图 | App 内（快门 + 相册） | 图片 → OCR → 阅读模式 |

### 处理层（两条管线，不混）

```
文本 / URL  ──→ 重排阅读（字号/行高/字间距/主题/标尺）──→ 朗读
图片 ────────→ Vision OCR ──→ 同一套阅读模式 ──→ 朗读
```

### 共用的阅读模式

`ReaderView` 已存在，三个入口复用。需收拢现有分叉：
分享扩展目前套了自己的 `NavigationStack` 和自己的 `SettingsModel`（且从不调用 `load()`，
导致分享进来永远用默认字号/主题，与 App 内设置不一致）。

## 组件设计

### 新增

**`Core/OCR/TextRecognitionService.swift`**

职责：把「一张图」变成「一段文本」。唯一接触 Vision 的地方。

```swift
struct RecognizedBlock {
    let text: String
    let topYRatio: Double   // 0=顶部 1=底部，用于保持阅读顺序
}

final class TextRecognitionService {
    /// 当前生效的识别语言，由 SettingsModel 驱动
    var languages: [String]

    func recognize(_ image: CGImage) async throws -> [RecognizedBlock]

    /// 启动时后台预热，避免首次快门等 28s
    func prewarm() async
}
```

要点：
- 固定用 `.accurate`（`.fast` 不支持中文）
- `languages` 由调用方决定，服务本身不猜
- 结果按 `topYRatio` 排序后返回，保证阅读顺序
- 空结果不算错误，返回空数组，由调用方决定兜底

**`Core/OCR/OCRImageSource.swift`**

职责：把不同来源的图片统一成 `CGImage`。

来源：`NSExtensionItem` 附件（分享扩展）、`PhotosPicker`（读取 tab 选图）、
`AVCapturePhotoOutput`（放大镜 tab 快门）。

统一入口的意义是让 `TextRecognitionService` 不需要知道图从哪来。

**`Features/Reader/ReaderLaunchCoordinator.swift`**

职责：承载「某段内容 → 打开阅读模式」这一个动作，三个入口共用。

```swift
@MainActor
final class ReaderLaunchCoordinator: ObservableObject {
    @Published var content: ReaderContent?

    func open(text: String)
    func open(image: CGImage) async   // 内部调 TextRecognitionService
}
```

这样做是为了避免「拍完照怎么跳到阅读页」这段逻辑在三个入口里各写一遍。
放大镜 tab 的快门和读取 tab 的相册选图都只调 `open(image:)`，不关心后续。

`ReaderContent` 是一个简单的枚举，承载「要么是一段文本，要么是一张待 OCR 的图」：

```swift
enum ReaderContent {
    case text(String)
    case image(CGImage)
}
```

**不新增独立的拍照页。** 快门复用放大镜页已有的相机预览（`AVCaptureSession` 已在运行），
相册选图用系统的 `PhotosPicker`，两者都只是「产出一张 `CGImage`」然后交给上面的 coordinator。

**`Features/Reader/ReadTabView.swift`**

职责：读取 tab 的界面——两张大字卡片（「粘贴并放大」/「从相册选图」）。
卡片的字号、间距按老花眼标准做大，是这一屏的全部意义。

### 信息架构

现有是 2 个 tab（放大镜 + 设置）。三个入口需要落位，提议改成 3 个 tab：

| Tab | 内容 |
|---|---|
| 1 · 放大镜 | 相机预览 + 缩放 + 手电筒 + **快门** |
| 2 · 读取 | 两个大字卡片：**「粘贴并放大」**、**「从相册选图」** |
| 3 · 设置 | 现有设置页 + **识别语言**覆盖项 |

把「读取」独立成一个 tab，是因为它承载的是老花眼用户最高频的动作，
值得一整屏、值得把按钮做大。分享入口不需要 UI——它在系统分享面板里。

### 修改

| 文件 | 改动 |
|---|---|
| `App/PresbyFriendApp.swift` | 移除自动读剪贴板；TabView 改为 3 个 tab；接入读取页 |
| `Features/Magnifier/MagnifierView.swift` | 加快门按钮；Live Text 不可用时明确隐藏而非静默失效 |
| `Features/Reader/ReaderView.swift` | 接受 OCR 来源的内容 |
| `shareextention/ShareView.swift` | 加图片 OCR 分支；补 `settings.load()`；去掉多余的 `NavigationStack` |
| `shareextention/Info.plist` | 加 `NSExtensionActivationSupportsImageWithMaxCount` |
| `project.pbxproj` | 加 `INFOPLIST_KEY_NSPhotoLibraryUsageDescription`；`IPHONEOS_DEPLOYMENT_TARGET` 改为 16.0 |
| `App/PresbyFriendApp.swift`、`ReaderView.swift`、`MagnifierView.swift` | 改写 5 处两参数 `onChange`（iOS 17+ → 兼容 16） |
| 6 个 `Localizable.strings` | 新增字符串（en/de/fr/es/it/pt） |

`ReadTabView.swift`（读取 tab 的界面）是新增文件，不列在上表。

### 不修改

| 文件 | 说明 |
|---|---|
| 根目录 `PresbyFriend/`、`Shared/`、`ShareExtension/` | 已确认构建不依赖，按决定保留（见「已决事项 3」） |
| `ios/add_share_extension.rb` | 已失效的一次性脚本，本次不动。它引用的路径已过时，若将来仍需使用需先修正 |

## 数据流

### 剪贴板入口

```
用户点「粘贴并放大」
  → UIPasteControl（系统控件，不触发粘贴弹窗）
  → 拿到的文本 → ReaderView
```

**不自动读取剪贴板。** 原因见「错误处理」节。

### 分享入口

```
任意 app → 分享
  → ShareExtension 启动
  → 按优先级尝试附件类型：
      1. 纯文本     → 直接进 ReaderView
      2. URL        → URLExtractor 提取正文 → ReaderView
      3. 图片       → OCRImageSource → TextRecognitionService → ReaderView
  → ReaderView（带「关闭」回到原 app）
```

### 拍照 / 选图入口

```
快门（放大镜 tab）或 相册选图（读取 tab）
  → CGImage
  → ReaderLaunchCoordinator.open(image:)
  → TextRecognitionService.recognize()
  → 非空 → ReaderView
  → 空   → 兜底显示原图（仅缩放）
```

## 错误处理

### 剪贴板系统弹窗（现存 bug，必须修）

现状 `PresbyFriendApp.swift:114-118`：

```swift
.onAppear { checkClipboard() }
.onChange(of: scenePhase) { _, phase in
    if phase == .active  { checkClipboard() }
    if phase == .background { lastClipboardText = "" }
}
private func checkClipboard() {
    let text = UIPasteboard.general.string ?? ""   // ← 触发系统弹窗
```

iOS 16 起，程序化读 `UIPasteboard.general` 会弹系统对话框
（「PresbyFriend」想要粘贴自「微信」/ 不允许 · 允许粘贴）。因为第 117 行重置了
`lastClipboardText`，**每次回到前台都会弹**。

危害：

- 恰好命中核心场景——内容来自别的 app 时必弹，而老人用这个 App 主要就是从别的 app 复制
- 弹窗文案与按钮由 iOS 控制，无法自定义
- 无 API 可查询用户选择，程序无法处理
- 弹窗字号不受 App 控制——对一个帮人看清小字的 App，先弹一个看不清的框

**方案**：改用 `UIPasteControl`（iOS 16+ 系统控件）。用户主动点击即构成「用户意图」，
不触发弹窗。同时把自动读取整个移除。

**待真机验证**：`UIPasteControl` 的外观与字号能否自定义。若不能，退到「普通按钮 + 接受一次弹窗」。

### OCR 返回空

不报错，返回空数组。调用方兜底显示原图（仅缩放，本次不做图像增强）。

### OCR 语言选错

**这是最危险的失败模式**——完全崩溃但不报错。缓解：

- 默认跟随系统语言（`Locale.current.language.languageCode`），中文系统用 `["zh-Hans"]`，
  其余用 `["en-US"]`
- 设置页提供手动覆盖
- `recognitionLanguages` 的构造集中在一处，不散落

### 首次使用模型准备

启动时后台调 `prewarm()`。若未完成用户就按了快门，显示准备中的进度而非卡住。

## 测试策略

**OCR 质量**（最重要，因为失败是静默的）

- 建立一组固定测试图：中文（小字、低对比度、药盒类型）、英文、中英混排
- 断言语言配置正确时识别率达标
- **回归测试**：断言 `["en-US"]` 在中文图上会失败——把这个已知陷阱固化成测试，
  防止将来有人「优化」语言列表顺序

**入口链路**

- 三个入口各自：文本 → 阅读模式可读、可朗读
- 分享图片 → OCR → 阅读模式
- 剪贴板 → 不出现系统弹窗

**设备差异**

- `DataScannerViewController.isSupported == false` 时，Live Text 相关 UI 不出现
- 真机验证 `UIPasteControl` 外观

## 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| `UIPasteControl` 外观不可定制 | 按钮做不大，对老花眼不友好 | 真机先验证；退路是普通按钮 |
| 首次 OCR 需联网（未验证） | 首次使用体验 | `prewarm()`；若无网则明确提示 |
| 部署目标下调到 16.0 后，需改写 5 处 `onChange` | 改写引入回归 | 改动机械（两参数 → 单参数），逐处核对 |
| 根目录与 `ios/` 两份副本漂移 | 改了没生效，难排查 | 保留决定已定；建议加 README 说明 |
| 根目录重复文件被误删 | 可能删错 | 清理前单独确认 |

## 已决事项

### 1. 部署目标：26.5 → **16.0**

原为 26.5，等于只支持最新系统。Android `minSdk = 26` 对应 Android 8.0（**2017 年**设备），
两边覆盖面对老花眼人群严重不对称——而这个人群恰恰多用旧手机。

| 候选 | 设备覆盖 | 代价 |
|---|---|---|
| **iOS 16.0（选定）** | iPhone 8 / X（2017 年） | 改 5 处 `onChange` |
| iOS 17.0 | iPhone XS / XR（2018 年） | 0 |
| iOS 15.0 | — | 丢 `UIPasteControl` / `PhotosPicker` / `DataScannerViewController` / `NavigationStack` |

选 16.0 使两边设备覆盖对齐（都是 2017 年）。Xcode 27 支持的部署目标下限是 15.0，
16.0 离边界有余量。

**需要改写的 5 处**（两参数 `onChange(of:initial:_:)` 为 iOS 17+）：

- `App/PresbyFriendApp.swift:45`、`:115`、`:119`
- `Features/Reader/ReaderView.swift:56`
- `Features/Magnifier/MagnifierView.swift:71`

`Features/Settings/SettingsView.swift` 里的 6 处用的是老式单参数形式，无需改动。

其余 iOS 17+ API 用量为 0。

### 2. 首次 28s 是下载还是本地编译：**留待真机验证**

未能在 macOS 上验证。已知证据：

- `/System/Library/AssetsV2/com_apple_MobileAsset_LinguisticData` 下 68 个资产目录属主为
  `_nsurlsessiond`（后台下载守护进程），且 `LinguisticAssetType => Optional`
- `ar-SA` 首次 34.20s，之后 0.24s
- **但新文件产生 ≠ 一定是下载**，本地编译同样会写缓存。从文件系统无法区分

区分方法只有断网实测，而 Mac 的资产状态与 iPhone 完全不同，**Mac 上测出来不能代表手机**。

**验证方式**：真机 + 全新安装 + 飞行模式 + 首次 OCR。

设计上无论结果如何都需要 `prewarm()`；若确认依赖网络，还需为首次无网场景加明确提示。

### 3. 根目录 26 个重复 iOS 文件：**保留不清理**

已实测确认构建不依赖它们：

| 证据 | 结果 |
|---|---|
| pbxproj 当前引用 | 仅 `path = PresbyFriend` 与 `path = shareextention`，解析到 `ios/PresbyFriend/` 下 |
| pbxproj **历史上**是否引用过根目录 | **从未** |
| 挪走这三个目录 + 清空 DerivedData 全量重编 | **BUILD SUCCEEDED** |

"这些文件是必需的"这一印象的可能来源是 `ios/add_share_extension.rb`——一个一次性脚本，
写着 `EXTENSION_SOURCE_DIR = '../../ShareExtension'`、`new_group('Shared', '../../Shared')`。
但该脚本已经跑完（扩展已存在于 `ios/PresbyFriend/shareextention/`），且工程后来改用
synchronized group，不经过脚本创建的 group 引用，脚本内的路径也已过时。

保留成本为零，故保留。

**副作用需记录**：根目录那份与 `ios/` 那份**会各自漂移**，改一边不影响另一边。
将来若出现"改了没生效"，先怀疑这里。建议在根目录放一份 README 说明其为遗留副本、
构建实际使用 `ios/` 下那份。

## 真机验证清单

以下只能在真机上确认，模拟器无法覆盖：

| 项 | 方法 |
|---|---|
| 首次 OCR 是否依赖网络 | 全新安装 + 飞行模式 + 第一次 OCR |
| `UIPasteControl` 外观/字号能否自定义 | 真机运行，检查能否做成大字按钮 |
| 剪贴板粘贴是否真的不弹系统对话框 | 从微信复制文本 → 切到 App → 观察 |
| `DataScannerViewController` 不可用时的降级 | 老设备（A12 以前）上确认 Live Text UI 隐藏而非静默失效 |
