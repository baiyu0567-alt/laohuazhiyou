import Foundation

/// 识别语言偏好。
///
/// 这些选项说的是**被拍文本的语言**——既不是界面语言，也不是用户的语言。界面是德语的人
/// 要拍中文药盒，就该选中文。所以：
///
/// - 默认档是**跟随系统**：设备是中文就给中文、是德语就给德语，覆盖绝大多数场景；
/// - 手动档**不限于本 App 出翻译的那六种**，而是运行时读 Vision 实际支持的整份清单
///   （本机实测 33 种）。识别语言是「要认的东西」的语言，没有理由被界面语言限制。
///
/// 选项名用**本族名**（`Deutsch`、`日本語`、`简体中文`），由 `displayName(for:)` 生成，
/// 见那里的说明。
///
/// 本文件刻意只 `import Foundation`，不引用 `L10n`、`Vision` 或任何 UI 类型——这样它能被
/// `tools/ocr-bench/langcheck` 单独编出来跑断言。需要的「本机支持清单」由调用方以参数
/// `supported` 注入，测试里就能喂一份固定清单，不必依赖设备。
enum RecognitionLanguage: Hashable {
    /// 跟随**设备语言**（`Locale.preferredLanguages.first`），不是 App 的界面语言。
    ///
    /// 这一档以前叫 `system`，实现只有两档：`code.hasPrefix("zh") ? ["zh-Hans"] : ["en-US"]`。
    /// 于是德语用户看到的那行写着「跟随系统」，真实含义是**英语**——正是本文件警告的那种
    /// 安静出错：不报错、不崩溃，只是拿英文模型去认德语文本。
    ///
    /// 现在它是真的跟随设备语言，且覆盖 Vision 支持的每一种（`systemLanguageCode`）。
    case followSystem

    /// 用户手动指定的一档。载荷是 Vision 语言码，如 `"ja-JP"`。
    ///
    /// 存的就是这个码本身，不另造一套档位名：档位名一旦和 Vision 的码分家，将来系统加语言
    /// 就得两处同步改，而漏改的那一处不会有任何编译错误。
    case manual(String)

    // MARK: - 存储

    /// 存进 `UserDefaults` 的字符串。
    var stored: String {
        switch self {
        case .followSystem:      return "followSystem"
        case .manual(let code):  return code
        }
    }

    /// 读存储值，含旧 rawValue 的迁移。
    ///
    /// 改档位之前写进去的是一组档位名（`system` / `chinese` / `english` / `german` …）。
    /// 直接当语言码用会全部落空，再被默认值兜掉——用户之前选过的「简体中文」会被
    /// **静默重置**，而「设置自己变了」和「设置坏了」在界面上分不出来。
    ///
    /// 旧 `system` 映射到 `.followSystem` 是语义等价的：旧的那一档本来就是「跟随设备语言」，
    /// 只是实现只认中文。接到新实现上之后，中文设备照旧得到中文，德语设备从「英文」
    /// 修正为「德语」——那是修好，不是改变。
    ///
    /// **这一层不判断「本机能不能用这个码」——只看它长得像不像一个语言码。**
    /// 曾经它拿 `supported.contains(raw)` 把关，理由是「一个本机识别不了的档位等于把
    /// 『语言选错』固化下来」。那条理由本身对，**放在这里错了两处**：
    ///
    /// 1. **可用性是使用那一刻的属性，不是存储那一刻的。** 真正递码给 Vision 的地方是
    ///    `visionLanguages`，它自己有一道 `supported.contains` 兜底（落回 `en-US`）；
    ///    设置页的选项列表也专门为「值不在清单里」把当前这一档补进去显示
    ///    （`SettingsView.supportedLanguageCodes`）。两处都已经处理好了这件事。
    /// 2. **代价是静默销毁用户的选择，而且不可逆。** `load()` 读出 `.followSystem` 之后，
    ///    设置页一 `onDisappear` 就 `save()`，把存储值**改写**成 `"followSystem"`——
    ///    用户选过的日语不是「这次没显示出来」，是被覆盖掉了。触发条件不需要出错：
    ///    清单查询失败会退化成 `["en-US"]`（见 `OCRSupportedLanguageCodes.all`），系统升级
    ///    后 Vision 撤掉某个码也一样。这正是下面「固定档位名不查它」那一段要避免的事，
    ///    而它当时只保护了旧档位名，**没保护本版及以后写进去的码**——那条路上的用户更多。
    ///
    /// 所以改判形状。`"garbage"` 这种来路不明的值仍然被挡掉（它连形状都不是），
    /// 而 `"is-IS"` 这种「是真码、只是本机没有」的值会原样留下来。
    ///
    /// - Parameter raw: `UserDefaults` 里的原始字符串。可为 nil。
    /// - Returns: 认不出来时返回 nil。
    static func stored(from raw: String?) -> RecognitionLanguage? {
        guard let raw else { return nil }
        switch raw {
        case "followSystem", "system", "followApp": return .followSystem
        case "chinese", "chineseSimplified":        return .manual("zh-Hans")
        case "chineseTraditional":                  return .manual("zh-Hant")
        case "english":                             return .manual("en-US")
        case "german":                              return .manual("de-DE")
        case "french":                              return .manual("fr-FR")
        case "spanish":                             return .manual("es-ES")
        case "italian":                             return .manual("it-IT")
        case "portuguese":                          return .manual("pt-BR")
        default:                                    return looksLikeLanguageCode(raw) ? .manual(raw) : nil
        }
    }

    /// 这个字符串**长得像**一个 BCP-47 语言码吗（`ja-JP`、`zh-Hans`、`sr-Latn-RS`）。
    ///
    /// 只查形状，不查本机 Vision 支不支持——理由见 `stored(from:)`。
    /// 语言部分是 2–3 个字母，后面每一段是 2–8 个字母或数字。
    /// 单段（`"garbage"`）落在这之外，所以「认不出来」仍然是认不出来。
    private static func looksLikeLanguageCode(_ raw: String) -> Bool {
        raw.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$",
                  options: .regularExpression) != nil
    }

    // MARK: - 构造 Vision 的语言数组

    /// 设备语言解析出来的那一档。
    ///
    /// 设置页的 ❗ 和阅读页的提示都靠「实际用的码 ≠ 这个码」来判断「不一致」，
    /// 所以它必须是**同一个函数**算出来的，不能两处各写一份。
    ///
    /// - Parameter deviceLanguageCode: 设备首选语言码，如 `"zh-Hant-TW"`。可为 nil。
    /// - Parameter supported: 本机 Vision 支持的码。
    static func systemLanguageCode(deviceLanguageCode: String?, supported: [String]) -> String {
        let code = (deviceLanguageCode ?? "").lowercased()
        guard !code.isEmpty else { return "en-US" }

        let base = String(code.prefix(while: { $0 != "-" }))

        // 中文和粤语按**文字**分档，不能只靠语言部分匹配——`zh-Hans` 与 `zh-Hant` 的语言
        // 部分都是 `"zh"`，下面那条 `hasPrefix` 会先撞上哪一个完全取决于清单顺序。
        //
        // **显式的文字子标签优先于地区。** 只按地区判断会把 `zh-Hans-HK` / `zh-Hans-MO`
        // 判成繁体——这两个是本机真实存在的标识符（`Locale.availableIdentifiers` 里有
        // `zh_Hans_HK` / `zh_Hans_MO`），iOS 上用户选「中文（简体）」加香港或澳门地区就会
        // 得到它们。判反了的后果正是本文件一直在防的那个模式：默认档拿繁体模型去认简体
        // 文本，不报错、不崩溃，两处新提示还会反过来指责用户——设置页亮 ❗，阅读页写
        // 「识别为简体中文，但你的系统语言是繁體中文」，而系统语言根本不是繁体。
        //
        // 地区只在**没有**文字子标签时才用来推断：`zh-TW` / `zh-HK` / `zh-MO` 只有地区，
        // 那才需要靠它判文字。
        if base == "zh" || base == "yue" {
            let isTraditional: Bool
            if code.contains("-hant") {
                isTraditional = true
            } else if code.contains("-hans") {
                isTraditional = false
            } else {
                isTraditional = code.contains("-tw") || code.contains("-hk")
                    || code.contains("-mo")
            }
            let wanted = base + (isTraditional ? "-Hant" : "-Hans")
            if supported.contains(wanted) { return wanted }
        }

        // 其余：语言部分相同的第一个（`"ja"` → `"ja-JP"`，`"no"` → `"no-NO"`）。
        if let match = supported.first(where: { $0 == base || $0.hasPrefix(base + "-") }) {
            return match
        }

        // 设备语言 Vision 不认识（比如冰岛语）：退回英文，而不是把一个不存在的码递给它。
        return "en-US"
    }

    /// 构造 Vision 的 `recognitionLanguages`。
    ///
    /// **数组的第一个元素决定用哪个识别模型。** 选错不会报错、不会崩溃，只会安静地
    /// 输出垃圾（实测：中文图 + `["en-US"]` 把「用法用量」识别成 `mzms`）。
    ///
    /// - Parameters:
    ///   - deviceLanguageCode: 设备首选语言码。只有 `.followSystem` 用得上它。
    ///   - preference: 用户在设置页的选择。
    ///   - supported: 本机 Vision 支持的码。
    static func visionLanguages(deviceLanguageCode: String?,
                                preference: RecognitionLanguage,
                                supported: [String]) -> [String] {
        let code: String
        switch preference {
        case .followSystem:
            code = systemLanguageCode(deviceLanguageCode: deviceLanguageCode, supported: supported)
        case .manual(let manualCode):
            code = manualCode
        }

        // 再把关一次：手动档的码可能来自旧存储值，而它未必在这台设备的清单里。
        // 递一个不存在的码给 Vision 得不到报错，只会安静地认错。
        //
        // （这里**不**提「从别的设备同步来的」：`SettingsModel.syncToCloud()` 只写
        // fontSize/theme/lineHeight/letterSpacing 四项，`recognitionLanguage` 从不上云，
        // 也没有别的入径能把它带进来。）
        guard supported.contains(code) else { return ["en-US"] }
        return [code]
    }

    /// 这次实际会用哪个模型。和 `visionLanguages` 是同一个结果，只是取成单个码——
    /// 「当前用的是不是系统语言那一档」这个判断在设置页和阅读页都要用。
    static func effectiveLanguageCode(deviceLanguageCode: String?,
                                      preference: RecognitionLanguage,
                                      supported: [String]) -> String {
        // `visionLanguages` 恒返回恰好一个元素。
        visionLanguages(deviceLanguageCode: deviceLanguageCode,
                        preference: preference,
                        supported: supported).first ?? "en-US"
    }

    // MARK: - 显示

    /// 语言码的本族名，如 `"de-DE"` → `Deutsch`。
    ///
    /// **刻意不翻译、也不走 `L10n`。** 选项说的是「文本的语言」，那么用那门语言自己写出来
    /// 的名字，六种界面语言下写法完全一致，一个翻译都不用加，各语言的用户也都能一眼
    /// 找到自己那一项。反过来，把 `Deutsch` 翻成中文「德语」的话，一个德语用户要在
    /// 英文或中文界面里找自己的语言，得先知道它在**别的语言**里怎么写。
    static func displayName(for code: String) -> String {
        if let override = nameOverrides[code] { return override }
        // 去掉地区再问那个语言：`Locale(identifier: "de-DE")` 自报的是
        // 「Deutsch (Deutschland)」，带上国家名，列表里既长又没用。
        let base = String(code.prefix(while: { $0 != "-" }))
        return Locale(identifier: base).localizedString(forIdentifier: base) ?? code
    }

    /// 自动生成不了的那几个。
    ///
    /// `Locale` 是按**语言**给名字的，而这几档的区分在**文字**上、语言部分是同一个，
    /// 去掉地区之后就撞名了——实测 `zh-Hans` 与 `zh-Hant` 都得到「中文」、
    /// `yue-Hans` 与 `yue-Hant` 都得到「廣東話」。另外 `id-ID` 在本机 Foundation 数据里
    /// 给的是「Indonesia」，那是国家名不是语言名，一并覆盖。
    private static let nameOverrides: [String: String] = [
        "zh-Hans":  "简体中文",
        "zh-Hant":  "繁體中文",
        "yue-Hans": "粵語（簡體）",
        "yue-Hant": "粵語（繁體）",
        "id-ID":    "Bahasa Indonesia",
    ]
}
