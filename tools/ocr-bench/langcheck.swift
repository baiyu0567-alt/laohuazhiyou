import Foundation

// 独立编译 RecognitionLanguage.swift 并断言其构造规则。
// 编译命令见 build.sh —— 它把生产代码原文件直接编进来，测的是真代码，不是副本。

var failures = 0

func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    if actual == expected {
        print("  ✅ \(label) → \(actual)")
    } else {
        print("  ❌ \(label) → 实际 \(actual)，期望 \(expected)")
        failures += 1
    }
}

// 本机实测的 Vision `.accurate` 清单（33 种）。这里用固定清单而不是去读本机 Vision：
// langcheck 编成 macOS 可执行、跑在命令行里，拿不到 iOS 的 Vision 清单。
// 顺序照抄实测顺序——`systemLanguageCode` 用 `first(where:)`，结果依赖清单顺序。
let supported = [
    "en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR", "zh-Hans", "zh-Hant",
    "yue-Hans", "yue-Hant", "ko-KR", "ja-JP", "ru-RU", "uk-UA", "th-TH", "vi-VT",
    "ar-SA", "ars-SA", "tr-TR", "id-ID", "cs-CZ", "da-DK", "nl-NL", "no-NO",
    "nn-NO", "nb-NO", "ms-MY", "pl-PL", "ro-RO", "sv-SE", "fi-FI", "hi-IN", "mr-IN",
]

/// 指定清单的重载，专门用来验证「清单不同则结果不同」。
func langs(_ preference: RecognitionLanguage, _ list: [String], device: String? = nil) -> [String] {
    RecognitionLanguage.visionLanguages(deviceLanguageCode: device,
                                        preference: preference,
                                        supported: list)
}

func langs(_ preference: RecognitionLanguage, device: String? = nil) -> [String] {
    langs(preference, supported, device: device)
}

func system(_ device: String?, _ list: [String] = supported) -> String {
    RecognitionLanguage.systemLanguageCode(deviceLanguageCode: device, supported: list)
}

func stored(_ raw: String?) -> RecognitionLanguage? {
    RecognitionLanguage.stored(from: raw)
}

// MARK: - 设备语言 → Vision 码

expect(system("en-US"), "en-US", "en-US")
expect(system("en-GB"), "en-US", "en-GB → 清单里第一个 en-*")
expect(system("de-DE"), "de-DE", "de-DE")
expect(system("de-AT"), "de-DE", "de-AT → de-DE")
expect(system("DE-DE"), "de-DE", "大小写不敏感")
expect(system("ja"),    "ja-JP", "裸 ja → ja-JP")
expect(system("ja-JP"), "ja-JP", "ja-JP")
expect(system("pt-PT"), "pt-BR", "pt-PT → pt-BR（清单里没有 pt-PT）")
expect(system(nil),     "en-US", "设备语言缺失")
expect(system(""),      "en-US", "空串")

// 设备语言 Vision 不认识（冰岛语不在清单里）→ 英文，而不是把一个不存在的码递给 Vision。
expect(system("is-IS"), "en-US", "冰岛语 → 英文")

// 中文和粤语按**文字**分档，不是按语言部分——`zh-Hans` 与 `zh-Hant` 的语言部分都是 `zh`，
// 只按前缀匹配的话拿到哪一个全看清单顺序。
expect(system("zh-Hans"),     "zh-Hans", "zh-Hans")
expect(system("zh-Hans-CN"),  "zh-Hans", "zh-Hans-CN")
expect(system("zh"),          "zh-Hans", "裸 zh → 简体")
expect(system("zh-Hant"),     "zh-Hant", "zh-Hant")
expect(system("zh-Hant-TW"),  "zh-Hant", "zh-Hant-TW")
expect(system("zh-TW"),       "zh-Hant", "zh-TW 只有地区、没有文字，也要认成繁体")
expect(system("zh-HK"),       "zh-Hant", "zh-HK")
expect(system("zh-MO"),       "zh-Hant", "zh-MO")
expect(system("yue-Hant-HK"), "yue-Hant", "yue-Hant-HK")
expect(system("yue"),         "yue-Hans", "裸 yue → 简体")

// **显式的文字子标签必须压过地区。** 这几条是补一个真出过的缺陷：只按地区判断会把
// `zh-Hans-HK` / `zh-Hans-MO` 判成繁体，而这两个是本机真实存在的标识符
// （`Locale.availableIdentifiers` 里有 `zh_Hans_HK` / `zh_Hans_MO`）——iOS 上用户选
// 「中文（简体）」加香港或澳门地区给的就是它们。判反的后果是默认档拿繁体模型认简体文本，
// 且两处新提示会反过来指责用户。
//
// 之前的 142 条里没有这两条，所以那个缺陷是全绿通过的——这几行就是补上那个洞。
expect(system("zh-Hans-HK"),  "zh-Hans", "zh-Hans-HK：地区 HK，但文字明写简体")
expect(system("zh-Hans-MO"),  "zh-Hans", "zh-Hans-MO：地区 MO，但文字明写简体")
expect(system("zh-Hans-TW"),  "zh-Hans", "zh-Hans-TW：地区 TW，但文字明写简体")
expect(system("zh-Hans-SG"),  "zh-Hans", "zh-Hans-SG")
expect(system("zh-Hant-CN"),  "zh-Hant", "zh-Hant-CN：地区 CN，但文字明写繁体")
expect(system("zh-Hant-MY"),  "zh-Hant", "zh-Hant-MY")
expect(system("yue-Hant-MO"), "yue-Hant", "yue-Hant-MO")

// 上面那段的注释声称「不取决于清单顺序」。把清单倒过来，它就成了一句可验证的话：
// 若把 zh 那一支改回 hasPrefix 匹配，这两行会跟着清单顺序翻面。
let reversed = Array(supported.reversed())
expect(system("zh-Hant-TW", reversed), "zh-Hant", "清单倒序，繁体仍是繁体")
expect(system("zh-Hans",    reversed), "zh-Hans", "清单倒序，简体仍是简体")
// 文字子标签是**读出来的**，不是靠清单顺序撞对的，所以倒序也不能翻面。
expect(system("zh-Hans-HK", reversed), "zh-Hans", "清单倒序，zh-Hans-HK 仍是简体")

// 设备清单里没有繁体模型时，落回同一语言的简体比落回英文有用（简体模型多半能读繁体）。
// 这是刻意的取舍，不是漏配。
expect(system("zh-Hant-TW", ["en-US", "zh-Hans"]), "zh-Hans", "繁体设备但清单里没有繁体 → 简体")

// MARK: - visionLanguages：数组首位决定用哪个模型

expect(langs(.followSystem, device: "zh-Hant-TW"), ["zh-Hant"], "跟随系统 + 繁体设备")
expect(langs(.followSystem, device: "ja-JP"),      ["ja-JP"],   "跟随系统 + 日语设备")
expect(langs(.followSystem, device: nil),          ["en-US"],  "跟随系统 + 设备语言缺失")
expect(langs(.followSystem, device: "is-IS"),      ["en-US"],  "跟随系统 + 冰岛语设备")

// 手动档与设备语言**无关**——这就是本次改动的核心：识别语言不再受界面语言或设备语言牵制。
// 德语界面的人要拍中文文件，选中文就该拿中文模型。
expect(langs(.manual("ja-JP"),   device: "de-DE"),   ["ja-JP"],   "手动日语 + 德语设备")
expect(langs(.manual("zh-Hans"), device: "en-US"),   ["zh-Hans"], "手动简体 + 英文设备")
expect(langs(.manual("de-DE"),   device: "zh-Hans"), ["de-DE"],   "手动德语 + 中文设备")

// 手动档的码本机不认（旧存储值，或从另一台设备同步来的）→ 英文。
// 递一个不存在的码给 Vision 不会报错，只会安静地识别出垃圾。
expect(langs(.manual("is-IS")), ["en-US"], "手动档但本机不支持 → 英文")

// MARK: - effectiveLanguageCode 与 visionLanguages 不能分家

// 设置页的 ❗ 和阅读页的提示都拿 `effectiveLanguageCode` 与 `systemLanguageCode` 比，
// 而真正喂给 Vision 的是 `visionLanguages`。两者一旦对不上，提示就会说一件没发生的事。
for (device, preference) in [
    ("zh-Hant-TW", RecognitionLanguage.followSystem),
    ("de-DE",      RecognitionLanguage.followSystem),
    ("is-IS",      RecognitionLanguage.followSystem),
    (nil,          RecognitionLanguage.followSystem),
    ("en-US",      RecognitionLanguage.manual("ja-JP")),
    ("ja-JP",      RecognitionLanguage.manual("zh-Hans")),
    (nil,          RecognitionLanguage.manual("de-DE")),
] as [(String?, RecognitionLanguage)] {
    let viaVision = langs(preference, device: device).first
    let viaEffective = RecognitionLanguage.effectiveLanguageCode(
        deviceLanguageCode: device, preference: preference, supported: supported)
    expect(viaVision, Optional(viaEffective), "一致/\(preference)/\(device ?? "nil")")
}

// MARK: - 旧存储值迁移：改了档位名不能把用户选过的值静默重置

expect(stored(nil), nil, "迁移/没有存储值")
expect(stored("followSystem"), .followSystem, "迁移/本版的 followSystem")
expect(stored("system"),       .followSystem, "迁移/最初的默认值 system")
expect(stored("followApp"),    .followSystem, "迁移/上一版的 followApp")

expect(stored("chinese"),            .manual("zh-Hans"), "迁移/chinese")
expect(stored("chineseSimplified"),  .manual("zh-Hans"), "迁移/chineseSimplified")
expect(stored("chineseTraditional"), .manual("zh-Hant"), "迁移/chineseTraditional")
expect(stored("english"),            .manual("en-US"),   "迁移/english")
expect(stored("german"),             .manual("de-DE"),   "迁移/german")
expect(stored("french"),             .manual("fr-FR"),   "迁移/french")
expect(stored("spanish"),            .manual("es-ES"),   "迁移/spanish")
expect(stored("italian"),            .manual("it-IT"),   "迁移/italian")
expect(stored("portuguese"),         .manual("pt-BR"),   "迁移/portuguese")

// 直接存成 Vision 码的那一支（本版及以后写进去的值）。
expect(stored("ja-JP"),   .manual("ja-JP"),   "迁移/直接码 ja-JP")
expect(stored("zh-Hant"), .manual("zh-Hant"), "迁移/直接码 zh-Hant")

// **本机不支持的码照样留下。** 这里曾经拿 `supported.contains(raw)` 把关，理由是
// 「免得把一个本机不存在的码固化下来」——代价却是把**用户选过的那一档**改写成
// 「跟随系统」，而 `SettingsView.onDisappear` 会紧接着 `save()`，把它**永久覆盖掉**。
// 触发不需要出错：清单查询失败会退化成 `["en-US"]`，系统升级后 Vision 撤掉某个码也一样。
// 可用性是**使用那一刻**的设备属性，由 `visionLanguages` 兜底（下面第二行）。
expect(stored("is-IS"),   .manual("is-IS"), "迁移/本机不支持的真码要留下")
expect(langs(.manual("is-IS")), ["en-US"], "……但真用它的时候会落回英文")

// 而「根本不是一个语言码」仍然不认：形状就不对，由调用方给默认值。
expect(stored("garbage"), nil, "迁移/认不出来")
expect(stored(""),        nil, "迁移/空串")
// 形状规则的边界：语言部分是 2–3 个字母，后面可有若干段。裸 `ja` 算码，
// 单段的 `garbage` 不算——判据是**形状**，不是本机有没有。
expect(stored("ja"),      .manual("ja"), "迁移/裸语言码（形状够）")

// MARK: - 往返：清单里每个码都要存得下、读得回、并且真的喂给 Vision

// 遍历整份清单而不是只测一两个：只测一个的话，改坏别的档位测试照样全过。
for code in supported {
    expect(stored(code)?.stored, code, "存读往返/\(code)")
    expect(langs(.manual(code)).first, code, "喂给 Vision/\(code)")
}

// MARK: - 选项名（本族名）

// 这五个覆盖是**手工维护**的，直接断言字面值：它们存在的理由就是自动生成会撞名。
expect(RecognitionLanguage.displayName(for: "zh-Hans"),  "简体中文",         "显示/zh-Hans")
expect(RecognitionLanguage.displayName(for: "zh-Hant"),  "繁體中文",         "显示/zh-Hant")
expect(RecognitionLanguage.displayName(for: "yue-Hans"), "粵語（簡體）",     "显示/yue-Hans")
expect(RecognitionLanguage.displayName(for: "yue-Hant"), "粵語（繁體）",     "显示/yue-Hant")
expect(RecognitionLanguage.displayName(for: "id-ID"),    "Bahasa Indonesia", "显示/id-ID")

// 其余靠 `Locale` 生成。这里**不断言具体字面值**——那取决于系统的 locale 数据，
// macOS 与 iOS 未必相同，写死只会让测试换台机器就假报错。
// 断言的是性质：每条都得非空，而且两两不同——撞名正是上面那五个覆盖要解决的问题。
let emptyNames = supported.filter { RecognitionLanguage.displayName(for: $0).isEmpty }
expect(emptyNames, [], "显示/没有空名字")

var firstOwner: [String: String] = [:]
var collisions: [String] = []
for code in supported {
    let name = RecognitionLanguage.displayName(for: code)
    if let owner = firstOwner[name] {
        collisions.append("\(code) 与 \(owner) 都叫「\(name)」")
    } else {
        firstOwner[name] = code
    }
}
expect(collisions, [], "显示/没有撞名")
print("  ℹ️ \(supported.count) 个码得到 \(firstOwner.count) 个互不相同的名字")

// MARK: - RecognitionLanguageAudit：认出来的文字像不像我们递交的语言

/// 只调**纯逻辑**那一层（`verdict`），假设由参数喂进来。
/// 不调 `audit`——它会去问 `NLLanguageRecognizer`，而那是机器上的模型，
/// 换台机器、换个系统版本都可能给出不同结果，写进断言等于让测试依赖环境
/// （与上面 `displayName` 只断言性质、不断言字面值同一个理由）。
func audit(_ asked: [String], _ hyps: [(String, Double)], _ list: [String] = supported) -> String? {
    RecognitionLanguageAudit.verdict(
        askedCodes: asked,
        hypotheses: hyps.map { (code: $0.0, probability: $0.1) },
        supported: list)?.suggestedCode
}

// 语言码比较。文字子标签那一半是必需的：zh-Hans 与 zh-Hant 的语言部分都是 zh，
// 只比语言部分会把它们当成同一门，于是「拿繁体模型读简体文本」会被判成没问题。
expect(RecognitionLanguageAudit.sameLanguage("en", "en-US"),         true,  "比较/en 与 en-US")
expect(RecognitionLanguageAudit.sameLanguage("en-US", "en-US"),      true,  "比较/同一个码")
expect(RecognitionLanguageAudit.sameLanguage("EN-us", "en-US"),      true,  "比较/大小写不敏感")
expect(RecognitionLanguageAudit.sameLanguage("de", "en-US"),         false, "比较/de 与 en-US")
expect(RecognitionLanguageAudit.sameLanguage("zh-Hans", "zh-Hans"),  true,  "比较/简体与简体")
expect(RecognitionLanguageAudit.sameLanguage("zh-Hant", "zh-Hant"),  true,  "比较/繁体与繁体")
expect(RecognitionLanguageAudit.sameLanguage("zh-Hans", "zh-Hant"),  false, "比较/简体与繁体——文字不同就不是同一门")
expect(RecognitionLanguageAudit.sameLanguage("zh", "zh-Hant"),       true,  "比较/一边没写文字就不追究")
expect(RecognitionLanguageAudit.sameLanguage("yue-Hans", "zh-Hans"), false, "比较/粤语与中文不是同一门")

// 下面八条是**实测的八种情况**，假设那两列直接抄测量的输出。
// 该提示的一律占比 0.00，不该提示的最低 0.92，中间是空的——这就是判定成立的依据。
expect(audit(["zh-Hans"], [("en", 1.00)]),                                   "en-US",
       "实测/英文图 + zh-Hans（真机出问题的那种）→ 建议英文")
expect(audit(["en-US"],   [("en", 1.00)]),                                   nil,
       "实测/英文图 + en-US → 没问题")
expect(audit(["en-US"],   [("de", 1.00)]),                                   "de-DE",
       "实测/德文图 + en-US（同为拉丁字母，最难的一档）→ 建议德文")
expect(audit(["zh-Hans"], [("zh-Hans", 1.00)]),                              nil,
       "实测/中文图 + zh-Hans → 没问题")
expect(audit(["en-US"],   [("pl", 0.44), ("pt", 0.26), ("nl", 0.14)]),       nil,
       "实测/中文图 + en-US：输出是垃圾——前三名全在清单里，靠置信度 0.44 挡掉，不提示")
expect(audit(["zh-Hans"], [("en", 0.99)]),                                   "en-US", "实测/英文只 2 行 + zh-Hans")
expect(audit(["zh-Hans"], [("zh-Hans", 0.92), ("zh-Hant", 0.07), ("ja", 0.02)]), nil,
       "实测/中文只 2 行 + zh-Hans：占比 0.92，离门槛很远")

// 文字子标签：用简体模型读到繁体文本，该建议换繁体。只比语言部分的话这条会被漏掉。
expect(audit(["zh-Hans"], [("zh-Hant", 0.90)]), "zh-Hant", "文字/简体模型读到繁体 → 建议繁体")

// 建议的绝不能是**已经在用的**那一档——那是句废话。
// 这条要靠「求和占比」之外的另一道闸：占比 0.10 已经低于门槛，但最高项正是我们在用的。
expect(audit(["en-US"], [("en", 0.10), ("de", 0.05)]), nil,
       "不重复建议/最高项就是在用的那一档 → 不提示")

// 置信度门槛：**建议的那一档，识别器自己也得有把握。**
// 「在不在清单里」单独用是不够的——pl-PL 就在那 33 条里，光靠清单会把垃圾输出
// 判成「建议改用波兰语」。这条线才是真正拦住它的东西。
expect(audit(["en-US"], [("is", 0.90)]), nil,
       "置信度/冰岛语不在清单里（这一条查的是清单，不是置信度）")
expect(audit(["en-US"], [("pl", Double(RecognitionLanguageAudit.minimumSuggestionConfidence))]), "pl-PL",
       "置信度/正好等于门槛 → 算是够格（门槛是「不低于」）")
expect(audit(["en-US"], [("pl", 0.79)]), nil,
       "置信度/差一点点 → 不说")
expect(audit(["en-US"], [("pl", 0.44), ("de", 0.90)]), "de-DE",
       "置信度/最高项没把握但次高项有 → 用说得准的那个")

// 判不了就不说。
expect(audit([],        [("en", 1.00)]), nil, "边界/没递交任何语言")
expect(audit(["en-US"], []),             nil, "边界/一条假设都没有")

// 短文本门槛。**这条能断言，是因为门槛在问模型**之前**就返回了**——
// 所以无论这台机器上的模型怎么判，结果都是 nil。
expect(RecognitionLanguageAudit.audit(askedCodes: ["zh-Hans"],
                                      recognizedText: "DOSAGE",
                                      supported: supported) == nil, true,
       "字数门槛/6 字不判（识别器在这个长度会把它判成法语 0.60）")
expect(RecognitionLanguageAudit.audit(askedCodes: ["zh-Hans"],
                                      recognizedText: String(repeating: "D", count: 29),
                                      supported: supported) == nil, true,
       "字数门槛/29 字仍不判")
print("  ℹ️ 门槛取 \(RecognitionLanguageAudit.minimumCharacters) 字，占比门槛 \(RecognitionLanguageAudit.massCeiling)")
print("  ℹ️ 30 字以上那一侧依赖系统模型，本文件不断言——见 README「局限」")

// MARK: - 回归：中文档绝不能把英文模型放第一位

// 英文模型遇汉字会静默输出垃圾（实测 "用法用量" → "mzms"），这是本 App 最容易踩的坑。
for device in ["zh-Hans", "zh-Hans-CN", "zh", "zh-Hant", "zh-Hant-TW",
               "zh-TW", "zh-HK", "zh-MO", "yue", "yue-Hant"] {
    if langs(.followSystem, device: device).first == "en-US" {
        print("  ❌ 回归失败：设备 \(device) 拿到了英文模型")
        failures += 1
    } else {
        print("  ✅ 回归：设备 \(device) 首位不是 en-US")
    }
}

// 回归：改动前的默认档（`.followApp`）在德语设备上给的是**英文**——因为界面语言默认是 en。
// 也就是说界面写着「跟随系统」，实际拿的是英文模型。这一条把那个 bug 钉住。
expect(langs(.followSystem, device: "de-DE"), ["de-DE"], "回归：德语设备不再拿到英文")

if failures == 0 {
    print("\n全部通过")
} else {
    print("\n失败 \(failures) 项")
    exit(1)
}
