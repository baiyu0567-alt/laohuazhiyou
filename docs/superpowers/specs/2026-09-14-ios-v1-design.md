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
实验脚本已收进仓库 `tools/ocr-bench/`（`./build.sh` 编译，`./bin/compare` 等），可随时复跑。

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
| `.accurate` | 33 种，含 `zh-Hans`/`zh-Hant`/`yue-Hans`/`ja-JP`/`ko-KR` |
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
| `project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET` 改为 16.0（2 处，均在项目级，两个 target 继承）|
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

**已查证（原「待真机验证」项已可结案）**：`UIPasteControl.Configuration` 只暴露
`displayMode` / `cornerStyle` / `cornerRadius` / `baseBackgroundColor` / `baseForegroundColor`
五个属性，**没有字号入口**。系统粘贴控件的文字尺寸不可调。

同时查证了另一条关键事实：**普通按钮里读 `UIPasteboard.general.string`，「每次点击」都会弹**，
不是只弹一次——Apple 只对系统识别的粘贴手势（`UIPasteControl`、`UIAction.Identifier.paste`
菜单、⌘V）免弹窗，代码里的自定义 button 与后台读取无法区分。

因此两个选项的真实代价是：

| 方案 | 字体 | 弹窗 |
|---|---|---|
| A 普通大字按钮 | 可做到 34pt+，清晰 | **每次粘贴都弹** |
| B `UIPasteControl` | 系统固定约 17pt，不可调 | 永不弹 |

**选定 B。** 理由：A 的「每次都弹」对这个人群是持续的打断，而 B 的按钮可以整体做大
（`frame` 给足 + `cornerStyle` 胶囊 + 自定义对比色），点击区域随之变大，只是标签字号固定。
把大字说明放在卡片上方的标题位（该处是自有文字，字号随意），系统控件作为明确的触发点。

**真机待确认**（降级为体验微调，不再影响方案选择）：大 `frame` 下控件的实际渲染是否居中、
对比度是否足够。若不满意，退路是 A。Task 11 复核：本条仍为**未验证 / 待真机**（方案本身
已决，见「真机验证清单」的 `UIPasteControl` 行）。

### OCR 返回空

不报错，返回空数组。调用方兜底显示原图（仅缩放，本次不做图像增强）。

### OCR 语言选错

**这是最危险的失败模式**——完全崩溃但不报错。缓解：

- 默认跟随系统语言（**`Locale.preferredLanguages.first`**，中文系统用 `["zh-Hans"]`，
  其余用 `["en-US"]`）
- 设置页提供手动覆盖
- `recognitionLanguages` 的构造集中在一处，不散落

> **2026-09-15 更正——本行原写的是 `Locale.current.language.languageCode`，那个 API 会让这条
> 缓解措施刚好失效，而失效的正是上面点名的那个失败模式。**
>
> `Locale.current` 是**按本 App 的本地化过滤之后**的结果，不是用户的系统语言。本 App 只出
> en/de/fr/es/it/pt 六种（六份 `.lproj` + `developmentRegion = en`，且没有
> `CFBundleLocalizations`），所以在**中文系统**的设备上它返回 `"en"`，`.system` 分支
> （`code.hasPrefix("zh") ? ["zh-Hans"] : ["en-US"]`）于是**永远选不到中文**——而 `.system`
> 正是默认值。结果：中文设备 + 默认设置 + 拍一张中文，默认跑英文模型，**完全崩溃但不报错**，
> 正是本节标题所指的那个模式。`Locale.preferredLanguages` 不被 App 本地化过滤，返回的是用户
> 真实偏好，才与「跟随系统语言」这句设计意图相符。两处独立实测记录见实现计划的对应事后更正。
>
> 注意这条错误的**形态**值得记：缓解措施本身写对了（选中文模型），只有取系统语言那一步的
> **API 选错**，而它错得很安静——非中文语言下两个 API 结果相同，所以只在中文场景暴露，
> 而中文恰恰是本 App 的主要场景。
>
> **2026-09-16 更正——上面这条「默认跟随系统语言」已作废，改为「跟随 App 语言（`.followApp`）」。**
> 作废的原因不是它错了，而是**它对用户撒了谎**：这一档读的设备语言，而实现只有两档
> （`code.hasPrefix("zh") ? ["zh-Hans"] : ["en-US"]`）。德语用户看到的一行写着「跟随系统」，
> 真实含义却是**英语**——他拍的德语文件会被英文模型识别。设置页上摆着德语界面，识别语言
> 却锁定英文，两个设置互相打脸。
>
> 现在这一档读设置页里选的那个 App 语言，字面为真。连带的三处变化：
>
> - **选项集扩到 9 档**：跟随 App 语言 + 6 种界面语言 + 简体中文 + 繁体中文（原先把中文
>   合成一档 `chinese`，繁体是个已成事实的需求缺口）。选项名用**本族名**（`Deutsch`、
>   `简体中文`），六种界面语言下写法一致，一个翻译都不用加。
> - **`Locale.preferredLanguages.first` 不再用于识别语言的日常取值**，只在存储为空时
>   预选一次（`RecognitionLanguage.initialDefault`）。**这一条是必需的**：`.followApp`
>   读的 App 语言在用户没选过时是 `"en"`（`SettingsModel.language` 的默认值），不加预选的话
>   **所有**新用户的默认识别语言都会变成英文——中文用户从「设备是中文就给中文」掉到「英文」，
>   那是一次回退。
> - **旧存储值 `system` 按设备语言迁移**，不直接映射成 `.followApp`：`SettingsView.onDisappear`
>   每次都会把当前值存回去，凡是进出过一次设置页又没改过这项的用户存的都是 `system`，
>   而 `system` 直映 `.followApp` 会让中文用户升级一次就掉到英文模型——又是本节标题那个
>   「完全崩溃但不报错」的模式。`langcheck` 里有一条专门钉死这个的回归断言。
>
> 另记一条**本 App 自身**的成因（未改，仅记录）：`LanguageManager.swift` 把 App 语言默认
> 写成 `"en"` 且不看设备语言，所以德语用户的界面首次启动是英文，`.followApp` 也就解析成
> `en-US`。让 App 语言跟随设备语言才是根上的解法，但那是更大的一次改动，不在本次范围。

> **2026-09-16 再更正——上面这条「跟随 App 语言（`.followApp`）」也已作废，改回「跟随设备
> 语言」，但这次是**真的**跟随。**
>
> 作废的原因正是上一条自己写下的那句结语：`.followApp` 读的是 App 语言，而 App 语言默认
> `"en"` 且不看设备语言——**德国用户的默认档仍然是英文**，只是这次「跟随系统」四个字换成了
> 「跟随 App 语言」，撒的谎换了个说法，没消失。上一版把根因认出来了却把它留在「不在本次
> 范围」，于是整个档位仍然是坏的。
>
> 关键区别：上一条作废「跟随系统」时，作废的是**名字**（实现只有中文/英文两档，名不副实）。
> 这一次作废的是「跟随 App 语言」这个**设计选择本身**。识别语言说的是**被拍文本的语言**，
> 与界面用什么语言无关——界面是德语的人要拍中文药盒，就该拿中文模型。所以：
>
> - **默认档 `RecognitionLanguage.followSystem` 读 `Locale.preferredLanguages.first`**
>   （不是 `Locale.current`，理由见 2026-09-15 那条），由 `systemLanguageCode` 解析成一档
>   Vision 码：`zh`/`yue` 按**文字**分档（`zh-TW`/`zh-HK`/`zh-MO` 没有文字标记也判繁体），
>   其余按语言部分取清单里第一个（`de-AT` → `de-DE`、裸 `ja` → `ja-JP`），设备语言 Vision
>   不认识则落 `en-US`。现在「跟随系统」字面为真，德语设备拿到 `de-DE`。
> - **`initialDefault` 删除**：默认档本身就是「跟随系统」，不再需要首启预选一次把中文用户
>   从英文里捞回来——那个预选是上一版为了补 `.followApp` 的窟窿才存在的。
> - **选项集不再是固定 9 档，而是运行时读 Vision 的整份清单**（`OCRSupportedLanguageCodes`，
>   本机实测 33 种）。识别语言是「要认的东西」的语言，没有理由被界面语言的六种限制住。
>   选项名用**本族名**（`Deutsch`、`简体中文`），且**刻意不进 `Localizable.strings`**：
>   它们说的是被拍文本的语言，六种界面语言下写法应当一致；翻成界面语言反而要求用户在
>   **别的语言**里认出自己的语言。只有「跟随系统」这一项需要翻译。
> - **迁移**：旧档位名（`system`/`chinese`/`english`…）由 `stored(from:supported:)` 映射；
>   `system` 与 `followApp` 都映射到 `.followSystem`（旧 `system` 语义就是「跟随设备语言」，
>   中文设备照旧得到中文，德语设备从「英文」**修正**为「德语」——那是修好，不是改变）。
>
> **两处 UI 提示**（用户要求）：
>
> - 阅读页在识别文本**最上方**插一条提示，仅当「实际用的码 ≠ 设备语言那一档」**且**这次
>   识别结果弱时出现；
> - 设置页在「识别语言」标签前加 ❗，仅当这一项与实际不一致时出现。
>
> **已知未验证项（重要）**：「识别结果弱」的判据是
> `0 个块 OR (平均置信度 < 0.5 AND 低置信块占比 > 0.8)`，这套阈值是在**两张合成图**上
> 标定的，样本极少。单阈值版本已被实测推翻（正确的 `zh-Hans` 在双栏图上均值 0.400，反而
> **低于**当时设的 0.5，而错误语言是 0.320/90%——差距 0.08，噪声量级）。真机实拍照片上是否
> 成立，需要重新标定；改动前请先读 `ReaderLaunchCoordinator` 里那三个常量上的说明。

> **2026-09-16 三更正——上面那两处 UI 提示的**触发条件**作废，两条都换成同一个新判据。**
>
> 真机报回来：中文系统语言、拍英文文本，英文识别得一般，而**提示一条都没出现**——阅读页
> 没有，设置页的 ❗ 也没有。这不是阈值太严，是**问错了问题**：
>
> - 原判据是「实际用的码 ≠ 设备语言那一档」。这句话描述的是**用户手动偏离了设备语言**。
>   报这个问题的用户没有偏离——设置一直是最初的「跟随系统」，`usedCode` 与
>   `systemLanguageCode` 都是 `zh-Hans`，第一个 `guard` 直接返回 nil。**在默认档上，
>   这个触发条件结构上就不可能成立**，调阈值永远调不出来。
> - 把闸门拿掉也不行，因为**置信度在这件事上没有分辨力**，两个方向都是坏的。实测（中文
>   模型读英文图）：三条错行（句号认成逗号、丢句号、全角括号）置信度**全是 0.500**，
>   而判据是**严格小于** 0.5；整批均值 0.700、低置信占比 0%。反方向：中文图上**正确**的
>   「不良反应」只有 **0.300**，是整批最低的。错的 0.500、对的 0.300。
>
> **新判据问的是「认出来的这段文字，像不像我们递进去的那门语言」**：把整段识别结果交给
> `NLLanguageRecognizer`，看我们递交的语言一共占了多少概率质量（`RecognitionLanguageAudit`）。
> 实测八种情况，该提示的一律 **0.00**、不该提示的最低 **0.92**，中间是空的：
>
> | 情况 | 占比 | 该提示 |
> |---|---|---|
> | 英文图 / `zh-Hans` ← 真机报的就是这一种 | **0.00** | ✅ |
> | 英文图 / `en-US` | **1.00** | — |
> | 德文图 / `en-US`（同为拉丁字母，最难） | **0.00**（判为 `de` 1.00） | ✅ |
> | 中文图 / `zh-Hans` | **1.00** | — |
> | 中文图 / `en-US`（输出是垃圾） | **0.00** | ✗ 见下 |
> | 英文 2 行 / `zh-Hans` | **0.00** | ✅ |
> | 中文 2 行 / `zh-Hans` | **0.92** | — |
> | 只有 6 字「DOSAGE」 | 0.00（**误判成法语 0.60**） | 靠字数门槛挡掉 |
>
> 它**完全不看设备语言**，所以界面德语、设备德语的人拍中文也照样判得出来——这正是上面
> 「识别语言说的是被拍文本的语言」那句设计意图第一次真正落到判据上。两条 UI 提示
> **本身保留**（阅读页顶部卡片、设置页 ❗），只是不再按旧条件出现。
>
> **两道门槛，以及一次自己抓到自己：**
>
> - **字数** ≥ 30 才判。`NLLanguageRecognizer` 在很短的文字上自己就不可靠（`DOSAGE`
>   6 字判成法语 0.60；`用法用量` 4 字判成 zh-Hant 0.44，文字都判反了）。代价说清楚：
>   只拍一两行字的照片不会得到提示。
> - **建议的那一档，识别器自己也得有把握**（≥ 0.8）。**这一条是被一条断言抓出来的**，
>   而它原本不在设计里：我先前假设「判成波兰语，但波兰语不在 Vision 清单里，所以不会
>   提示」——**这是假的，`pl-PL` 就在那 33 条里**。真按原样发布，「英文模型读中文」那种
>   输出垃圾的场合会建议用户改用**波兰语**，照做只会更糟。真判出来的场合第一名是
>   1.00 / 1.00 / 0.99，垃圾场合只有 0.44，中间空着，门槛取 0.8。
>
> **仍然够不到的地方（写清楚，不假装覆盖）**：英文设备 + 跟随系统 + 拍中文文件，
> 现在**仍不提示**——那是上面那个场景的镜像，输出同样是垃圾，最高项 `pl 0.44`、
> 后面 `pt 0.26`、`nl 0.14`，没有任何一条建议是对的。这一头真的坏了而 App 保持沉默，
> 用户得自己想到「哦这是中文」。要覆盖它得靠别的手段（识别结果里汉字占比、或拿两门语言
> 各跑一遍比谁认得更像话），不是把门槛调低——调低只会把波兰语那种建议放出来。
>
> **未验证项**：30 字 / 0.2 占比 / 0.8 置信度这三个门槛是在**两张合成图**上标定的，
> 与上面那条「已知未验证项」同性质。真机实拍照片上是否成立，需要重新标定。

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
| `UIPasteControl` 字号不可调 | 标签文字偏小，对老花眼不友好 | 点击区域靠 `frame` 做大，说明文字放自有标题位；退路是普通按钮 + 每次弹窗 |
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

**Task 11 复核（2026-09-15）**：上列行号是 Task 1 审计时的位置，之后各 Task 增删代码已使其漂移
（例如 `MagnifierView.swift:71` 现为 `:76`，`PresbyFriendApp.swift:115/119` 现为 `:181/:182`，
且该文件因 Task 10 新增 `recognitionLanguage` 监听变为 4 处）。**结论未变**：全树 14 处
`onChange(of:)` 逐处检查，**均为单参数形式**，无一处使用 iOS 17+ 的
`onChange(of:initial:_:)`；本机 `grep` 亦未检出其他 iOS 17+ API 用量。当前各点位置：
`PresbyFriendApp.swift:44/165/181/182`（4 处）、`ReadTabView.swift:26`、`ReaderView.swift:56`、
`MagnifierView.swift:76`、`SettingsView.swift:143-149`（7 处，老式单参数）——
4+1+1+1+7 = 14，与上句的总数相符。

### 2. 首次 28s 是下载还是本地编译：**留待真机验证**

未能在 macOS 上验证。已知证据：

- `/System/Library/AssetsV2/com_apple_MobileAsset_LinguisticData` 下 68 个资产目录属主为
  `_nsurlsessiond`（后台下载守护进程），且 `LinguisticAssetType => Optional`
- `ar-SA` 首次 34.20s，之后 0.24s
- **但新文件产生 ≠ 一定是下载**，本地编译同样会写缓存。从文件系统无法区分

区分方法只有断网实测，而 Mac 的资产状态与 iPhone 完全不同，**Mac 上测出来不能代表手机**。

**验证方式**：真机 + 全新安装 + 飞行模式 + 首次 OCR。

设计上无论结果如何都需要 `prewarm()`；若确认依赖网络，还需为首次无网场景加明确提示。

**Task 11 复核（2026-09-15）：仍未验证。** 收尾验证这台机器没有模拟器 GUI、没有摄像头
（同「真机验证清单」一节），跑不了「全新安装 + 飞行模式 + 首次 OCR」，所以本条维持未验证，
不补写结论。结论只能在真机上取得。

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

以下只能在真机上确认，模拟器无法覆盖。**状态**列由 Task 11（收尾验证）填写：

| 项 | 方法 | 状态 |
|---|---|---|
| 首次 OCR 是否依赖网络 | 全新安装 + 飞行模式 + 第一次 OCR | **未验证 / 待真机**（Task 11 无法执行，见下） |
| `UIPasteControl` 大 `frame` 下的实际渲染 | 真机运行，看标签是否居中、对比度是否够 | **已决**（计划阶段结案，见下；仅剩渲染微调） |
| 剪贴板粘贴是否真的不弹系统对话框 | 从微信复制文本 → 切到 App → 观察 | 未验证 / 待真机 |
| `DataScannerViewController` 不可用时的降级 | 老设备（A12 以前）上确认 Live Text UI 隐藏而非静默失效 | 静态核验通过；真机未验证 |

**`UIPasteControl` 条：已决（计划阶段结案）。** 依据见上文「剪贴板」一节，此处只留结论：
`UIPasteControl.Configuration` 只暴露 `displayMode` / `cornerStyle` / `cornerRadius` /
`baseBackgroundColor` / `baseForegroundColor`，**没有字号入口**，系统控件的文字尺寸不可调；
而退路「普通大字按钮」的代价比原先估计高得多——自定义按钮里读
`UIPasteboard.general.string`，**每次点击都弹**系统粘贴确认（不是只弹一次）。故选定
`UIPasteControl`，把大字说明放在卡片标题位（该处是自有文字，字号随意），系统控件只作触发点。
真机仅剩「大 `frame` 下渲染是否居中、对比度是否够」一项体验微调，*不满意就退到普通按钮* 这条
退路依然有效，但已不影响方案选择。

**首次 OCR 联网问题：未验证 / 待真机。** Task 11 复核时本机**不具备**执行条件——没有模拟器
GUI（`open -a Simulator` 报 `Unable to find application named 'Simulator'`，exit 1），也没有
摄像头，无法做「全新安装 + 飞行模式 + 首次快门」实测。因此本条**不写结论**，保持未验证；
判据、已知证据与验证方式见上文 §2。
