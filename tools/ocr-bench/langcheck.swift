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

func stored(_ raw: String?, _ list: [String] = supported) -> RecognitionLanguage? {
    RecognitionLanguage.stored(from: raw, supported: list)
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

// 上面那段的注释声称「不取决于清单顺序」。把清单倒过来，它就成了一句可验证的话：
// 若把 zh 那一支改回 hasPrefix 匹配，这两行会跟着清单顺序翻面。
let reversed = Array(supported.reversed())
expect(system("zh-Hant-TW", reversed), "zh-Hant", "清单倒序，繁体仍是繁体")
expect(system("zh-Hans",    reversed), "zh-Hans", "清单倒序，简体仍是简体")

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

// 来路不明的码，清单里没有就不认，由调用方给默认值。
expect(stored("is-IS"),   nil, "迁移/本机不支持的码")
expect(stored("garbage"), nil, "迁移/认不出来")

// 旧档位名**不查** `supported`：它来路明确（那组名字是本 App 自己写进去的），能不能用是
// **使用那一刻**的设备属性，由 `visionLanguages` 兜底（下面第二行）。
// 在这里查的话，「用户选过德语」会变成「跟随系统」——那正是这一段要避免的静默重置。
expect(stored("german", ["en-US"]), .manual("de-DE"), "旧档位名不看 supported")
expect(langs(.manual("de-DE"), ["en-US"]), ["en-US"], "……但真用它的时候会落回英文")

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
