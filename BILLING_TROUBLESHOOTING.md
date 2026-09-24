# 计费 / 订阅排障笔记

两端共用同一组商品 ID，改一端就得改另一端：

| 商品 ID | 价格 | 类型 |
|---|---|---|
| `com.presbyfriend.pro.monthly` | $2.99/mo | 自动续期订阅 |
| `com.presbyfriend.pro.yearly` | $19.99/yr | 自动续期订阅 |

- Android：Google Play Billing 6.x。**Play Console 里的商品尚未创建**（CLAUDE.md 待办），
  所以现在两端都只跑得通「本地测试配置」这一条路。
- iOS：StoreKit 2 + 仓库里的 `ios/PresbyFriend/PresbyFriend.storekit`。

---

## 1. iOS：本地 `.storekit` 是怎么接上的（2026-09-24 跑通，提交 `3ef2501`）

四个文件咬合，**缺任何一个都退回失败态**：

| 文件 | 作用 |
|---|---|
| `ios/PresbyFriend/PresbyFriend.storekit` | 配置本体（两个订阅） |
| `PresbyFriend.xcodeproj/project.pbxproj` | 一条正式 `PBXFileReference` 挂到 mainGroup |
| `PresbyFriend.xcodeproj/xcshareddata/xcschemes/PresbyFriend.xcscheme` | `StoreKitConfigurationFileReference`，identifier = `../PresbyFriend.storekit` |
| `PresbyFriend.xcodeproj/PresbyFriend.storekit` | **软链** → `../PresbyFriend.storekit` |

（另：`project.xcworkspace/contents.xcworkspacedata` 已纳入版本控制，`.gitignore` 里单独开了口子。
下面 1.1 这段结论在 `.gitignore:10-19` 也有一份简写，那里是为了解释那条 `!` 例外为什么必须存在——
**改动其中一处时另一处也要跟着改**。）

### 1.1 为什么要有那条软链 —— identifier 的解析基准

**基准是 `<工程>.xcodeproj/project.xcworkspace/`，不是 `.xcodeproj` 包本身。**
所以 `../PresbyFriend.storekit` 解析出来是 `<.xcodeproj>/PresbyFriend.storekit`——
正是 Xcode 报「StoreKit Configuration file for scheme … can't be found」时点名的那个路径。
软链负责让这个路径真的存在。

三次运行对照（同机同会话，2026-09-24）：

| identifier | 软链 | 结果 |
|---|---|---|
| `../PresbyFriend.storekit` | 无 | 报找不到 `<.xcodeproj>/PresbyFriend.storekit` |
| `PresbyFriend.storekit`（去掉 `../`） | 有 | Xcode **不启用**测试配置，storekitd 回落 `Sandbox` |
| `../PresbyFriend.storekit` | 有 | **成功**（商品列出、订阅成功） |

→ `../` 是让 Xcode 肯启用测试配置的**书写形式**，软链负责补路径。**两条都承重。**

> ⚠️ **别把这条当普适规律。** 机器上两份 Xcode 亲写的样例（Flutter 的
> `in_app_purchase_storekit-0.4.11+1`）按「`.xcodeproj` 包为基准」2/2 命中，与本工程观测
> **矛盾**，差异原因未查明（怀疑与「工程是经由 `.xcworkspace` 还是 `.xcodeproj` 打开」有关，
> **未证实**）。**换新工程要重新实测。**

### 1.2 改完 pbxproj / scheme 必须 `⌘Q` 完全退出 Xcode

只关窗口不算——Xcode 不重读 pbxproj，会一直拿着旧项目模型。这条**犯过两次**，两次结论都作废。

### 1.3 `.storekit` 为什么不能放在同步文件夹里

`PresbyFriend/` 是 `PBXFileSystemSynchronizedRootGroup`，**同步文件夹不产生
`IDEFileReference`**，而 `IDEStoreKitEditor` 需要它 → 双击任何 `.storekit` 都报
`IDEStoreKitEditorConfigurationError error 0`（连 Xcode 自己 `⌘N` 生成的空白模板也一样）。
所以配置放在**项目根层**（与 `PresbyFriend.storekit`、`PresbyFriend.xcodeproj` 平级）。

---

## 2. 怎么判断测试配置**真的**被推进设备了

**别靠看价格**：`.storekit` 里的 `2.99` / `19.99` 与付费墙**兜底卡片**上的数字一模一样，
肉眼分不出来。

**✅ 可靠判据 = storekitd 的 `com.apple.storekit:XcodeTest` 子系统日志：**

```bash
xcrun simctl spawn <UDID> log show --last 6h \
  --predicate 'subsystem == "com.apple.storekit" AND category == "XcodeTest"' --style compact
```

有配置被推进去 → 这个子系统会有对应记录（如
`Requesting Media API product batch [...]` → `Parsing 2 products in response`）。
若**只有一条 `Starting Xcode Test Service`**（模拟器里 storekitd 每次启动都起这个服务，
属常态），就是**从来没收到过任何配置**。

配套的第二条判据（区分「测试配置」与「走 App Store」）：没走测试配置时，storekitd 把 App
当**普通沙盒客户端**，日志里会出现
`Initialized with server Sandbox bundle ID …` 与
`Failed to sync transactions for app install: accountMissing`。

### ⚠️ 兜底价签 vs 真实商品列表

两者**价格数字相同**，只能看文案：

| | 兜底卡片（`PayloadView` 的 `products.isEmpty` 分支） | 真实列表 |
|---|---|---|
| 名称 | `PresbyFriend Pro Monthly`（`L10n.proMonthly`） | `PresbyFriend Pro (Monthly)`（`.storekit` 里的 `displayName`） |
| 价格 | `$2.99/mo`（`L10n.proMonthlyPrice`） | `$2.99` |

有括号、价格不带周期后缀的那一组，才是 StoreKit 真列出来的。

---

## 3. 测试购买状态存在**两处**，清回免费态必须两处都清

| 位置 | 作用 |
|---|---|
| `<dev>/data/Containers/Data/System/<uuid>/Documents/Persistence/store.db` | **真源**。属主 `com.apple.ASOctaneSupportXPCService`；表 `octane_transaction` / `new_octane_transaction`。同目录 `cheddar-key` / `cheddar-cert` 给它签名，**别删** |
| `<dev>/data/Containers/Shared/AppGroup/<ag-uuid>/Library/Caches/storeUser.db` | **storekitd 给 App 读的缓存**（`iap_receipts_v2` / `iap_subscription_status_v2` / `iap_pending_transactions`）。App Group 是 `group.com.apple.storekit` |

**⚠️ 只清源库不够**：源库清空后缓存**不会自己删**，`currentEntitlements` 继续读缓存里的收据
→ App 一直判自己 Pro。

症状很有迷惑性：storekitd 日志里同时出现 `Query returned 0` 和 `Query returned 1`
（`unfinished` 与 `currentEntitlements` 两个查询**同毫秒、同线程**，日志分不出归属）。

**正确顺序：**

1. `xcrun simctl terminate <UDID> com.presbyfriend`
2. 杀 storekitd（`xcrun simctl spawn <UDID> launchctl list | grep storekitd` 取 PID，宿主 `kill -9`）
   ——它开着这两个库，不杀就是白删
3. 删 `store.db*` 里 `bundle_id='com.presbyfriend'` 的行，**并**删 App Group 的 `storeUser.db*` 三个文件
4. `xcrun simctl launch <UDID> com.presbyfriend`

**先备份再删**（如 `/tmp/storekit-backup/`），要恢复 Pro 态就拷回去。

> 顺带得到的正面证据：清干净后重启 App，`isProCached` 由 `true` 翻成 `false`——实证
> `apply(entitled:)` **能 true 也能 false**（没有照抄 Android「一旦 true 永不回落」那个缺陷）。

---

## 4. 判「App 现在是不是 Pro」的可靠判据

```bash
xcrun simctl get_app_container <UDID> com.presbyfriend data
plutil -p <上面那个路径>/Library/Preferences/com.presbyfriend.plist
```

看 `isProCached`。它是 `UserDefaults.standard`
（`SubscriptionManager.swift` 的 `private let defaults = UserDefaults.standard`），
**不是** App Group suite（那个 `group.35MJ76582H.com.presbyfriend` 是 `SettingsModel` 的）。

- `plutil` 比 `defaults read <path>` 可靠。
- cfprefsd 异步落盘：**写完要等一次刷盘**，文件 mtime 前进才算数。

---

## 5. CLI 做不到的事（省得重查）

1. **`xcrun simctl` 没有 storekit 子命令**，无法把配置注入模拟器。
2. **注入本身是 IDE 独有的**：`-[DVTDevice handleStoreKitConfigurationSyncForBundleID:configurationFilePath:runsOnProxy:]`
   走 XPC（`com.apple.storekit.configuration.xpc`）把配置**同步进设备**，不是启动参数。
   宿主侧日志不记录这件事（`log show --process Xcode` 全空）。
3. `xcodebuild` 构建时**不输出**那条 `StoreKit Configuration file … can't be found` 警告——
   它只在 IDE 里出现，所以 **CLI 给不了验证闭环**。
4. `SKTestSession(contentsOf:)` 是唯一能真正解码 `.storekit` 的 API，但它**在非 XCTest 进程里
   直接 `abort()`**（SIGABRT，退出码 134，连异常都抛不出来；stdout 缓冲还会吞掉已打印内容，
   要 `setvbuf(stdout,nil,_IONBF,0)` 才看得见死在哪一行）。工程没有测试 target。
5. **别拿「搜设备文件系统」当判据**：`grep -rl "com.presbyfriend.pro.monthly" <dev>/data`
   只会在**剪贴板缓存**里命中。配置走 XPC 送进 storekitd，**不一定落盘**，「搜不到」证明不了什么。

→ **运行时那一步的 `⌘R` 绕不过去。**

---

## 6. 判「这一轮 ⌘R 到底跑了没有」

**先看 App 进程的启动时间，别信 Xcode 控制台**——控制台会一直留着旧输出，
`⌘R` 没跑（或构建失败没重启）时看起来和跑过一模一样：

```bash
ps -eo pid,lstart,etime,comm | grep "PresbyFriend.app/PresbyFriend" | grep -v grep
```

实测踩过一次：用户贴来的控制台里带着「商品列表为空且未抛错」，但 App 进程启动于 21:38:59、
`.storekit` 改于 21:43:12——那次启动根本没用到新文件。

---

## 7. 每日额度语义（两端对齐，除一处有意不一致）

- 免费用户每天 **10 次**，Pro 无限。
- **检查在入口，计数在真正呈现时**：超额时**不计**（第 11 次点下去不会把计数推到 11）；
  被后来者顶掉的那次也**不计**（用户没拿到内容，不该扣）。
- iOS 的闸收口在 `ReaderLaunchCoordinator` 两个入口（`open(text:)` / `open(image:)`），
  四个调用方（放大镜快门、相册选图、粘贴文本、URL 提取）全汇到这里。
  `open(image:)` 的检查必须在 `ocr.recognize` **之前**（首次识别实测要 28–34s，超额不该白跑）。
- **跨天用本地时区**（`Calendar.current.isDate(inSameDayAs:)`）。
  ⚠️ **这一条有意与 Android 不一致**：Android 用 `millis / 86400000`（UTC 日界），
  对 UTC+8 的用户等于**早上 8 点换天**，是错的。属已知缺陷，**尚未修**。
- **分享扩展这条路径有意不设闸**（iOS）。理由见 `shareextention/ShareView.swift` 里的长注释：
  扩展里卖不了东西、Android 侧同样没闸；而「只计数不提示」这种折中也补不了——
  卡住的是存储域（`SubscriptionManager` 用 `UserDefaults.standard`，不是共享 suite）。

---

## 8. Android 侧

- 商品 ID 与 iOS 一致（见文首表格）。
- **Play Console 尚未创建订阅商品**，发布前必须做，否则购买流程跑不通。
- 免费额度闸只有一处：`SettingsDataStore.kt:65` 定义 `canUseToday()`，
  `PresbyFriendAccessibilityService.kt:132` 是唯一调用点。
  `ACTION_SEND` / `ACTION_PROCESS_TEXT` 直达阅读页，**不计数**——iOS 的分享扩展对齐的就是这个。
