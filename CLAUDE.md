# PresbyFriend

老花眼辅助阅读 App，通过实时放大镜 + OCR + 朗读帮助老花眼用户阅读小字。

## 架构

```
laohuazhiyou/
├── android/                  # Android 原生 (Kotlin + Jetpack Compose)
│   └── app/src/main/java/com/presbyfriend/
│       ├── MainActivity.kt           # 主 Activity，导航中枢，分享接收
│       ├── PresbyFriendApp.kt        # Application，持有 SettingsDataStore
│       ├── core/
│       │   ├── i18n/L10n.kt          # 类型安全字符串引用 + locale 切换
│       │   ├── storage/SettingsDataStore.kt  # DataStore 持久化
│       │   ├── theme/ReadingTheme.kt # WHITE/SEPIA/DARK/YELLOW
│       │   ├── tts/SpeechManager.kt  # Android TTS 封装
│       │   ├── url/UrlExtractor.kt   # URL → 正文提取 (OkHttp + Jsoup)
│       │   └── capture/
│       │       ├── OcrEngine.kt      # 截图 OCR (ML Kit Chinese)
│       │       └── PositionedBlock.kt # OCR 结果：text + topYRatio
│       ├── features/
│       │   ├── magnifier/            # 实时放大镜 + OCR + 手电筒
│       │   ├── reader/               # 阅读模式：滚动/朗读/标尺/控件
│       │   ├── settings/             # 设置页 + 语言切换
│       │   └── subscription/         # 付费墙 (Google Play Billing)
│       └── service/
│           ├── PresbyFriendAccessibilityService.kt  # 无障碍悬浮按钮 + 截图 OCR
│           └── QuickSettingsTileService.kt          # 快捷设置磁贴
├── PresbyFriend/             # iOS 原生 (SwiftUI) — 尚未完整实现
│   ├── App/
│   ├── Core/  (i18n, Theme, TTS, URL)
│   └── Features/ (Magnifier, Reader, Settings, Subscription)
├── Shared/SettingsModel.swift  # iOS DataStore 等价物
└── ShareExtension/             # iOS 分享扩展
```

## 技术栈 (Android)

| 层 | 技术 |
|----|------|
| UI | Jetpack Compose + Material 3 |
| 导航 | Navigation Compose |
| 相机 | CameraX + PreviewView |
| OCR | ML Kit Text Recognition (ChineseTextRecognizerOptions) |
| TTS | Android TextToSpeech |
| 存储 | DataStore Preferences |
| 网络 | OkHttp + Jsoup (URL 正文提取) |
| 内购 | Google Play Billing 6.x |
| 无障碍 | AccessibilityService + 截图 API (Android 14+) |

## 关键约定

### 字符串资源
- 所有 UI 字符串通过 `L10n` 对象引用 (`stringResource(L10n.appName)`)
- 支持 6 种语言：en（默认）、de、fr、es、it、pt
- 新增字符串需在所有 6 个 `values-*/strings.xml` 中添加

### 状态管理
- ViewModel + StateFlow，Compose 端 `collectAsState()`
- 配置持久化通过 `SettingsDataStore` (DataStore Preferences)
- 分享意图通过 `MutableStateFlow` + `LaunchedEffect` 驱动导航

### 主题
- 全局 `darkColorScheme()`（老花眼用户刻意设计）
- 阅读页 4 种阅读主题：WHITE / SEPIA / DARK / YELLOW — 仅影响阅读区域

### 语言切换
- `L10n.applyLocale(context, code)` 立即生效
- 语言切换后调用 `Activity.recreate()` 刷新所有文本

## 当前状态 (2026-06-22)

### 已完成
- [x] 实时放大镜 + OCR + 手电筒 + 缩放
- [x] 阅读模式（字号/行高/字间距/主题/标尺/TTS 朗读）
- [x] URL 分享 → 正文提取 → 阅读
- [x] 文本分享接收（SEND / PROCESS_TEXT）
- [x] 无障碍悬浮按钮 + 截图 OCR（Android 14+）
- [x] 快捷设置磁贴
- [x] 5 种欧洲语言完整翻译（de, fr, es, it, pt）
- [x] 实时语言切换（applyLocale + recreate）
- [x] 付费墙 UI（Google Play Billing，待 Play Console 配置商品）
- [x] OCR 中文识别器（LATIN_AND_CHINESE）
- [x] 每日使用计数存储（recordUse / canUseToday）

### 待发布前完成
- [ ] 解除每日限制的注释（AccessibilityService 中两处 TODO）
- [ ] Play Console 创建订阅商品（com.presbyfriend.pro.monthly / .yearly）
- [ ] Google Play 封闭测试
- [ ] iOS 端完整实现
- [ ] 无障碍浮窗图标替换为自有设计

### 设计决策
- 每日限制 10 次，用 `canUseToday()` 检查（代码已实现，注释供测试）
- 深色主题为刻意设计——老花眼用户对亮度敏感
- fallback 价格卡片在 Play Console 商品未配置时显示（$2.99/mo, $19.99/yr）
