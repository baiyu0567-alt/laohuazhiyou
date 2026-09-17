import Foundation
import NaturalLanguage

/// 「这一次识别，用的模型对得上画面里的文字吗」。
///
/// ## 为什么需要它
///
/// 原来的判据是「实际用的档 ≠ 设备语言那一档」，再叠一个 `looksWeak` 置信度门槛。
/// 真机上被证伪了，而且两个方向都是坏的：
///
/// **一、判据问错了问题。** 「你有没有偏离设备语言」和「这次读对了吗」是两件事。
/// 中文设备拍英文药盒、设置仍是最初的「跟随系统」——`usedCode` 与 `systemLanguageCode`
/// 都是 `zh-Hans`，第一个 `guard` 直接返回 nil。用户看到的是**什么提示都没有**。
///
/// **二、就算把那道闸门拿掉也没用，因为置信度本身不可信。** 实测（中文模型读英文图）：
///
/// | 结果 | 置信度 |
/// |---|---|
/// | `DOSAGE` ✅ | 1.000 |
/// | `Oral, One tablet...` ❌（句号认成逗号） | **0.500** |
/// | `Do not use ... ingredient Use with...` ❌（丢句号） | **0.500** |
/// | `Keep sealed ... （below 20 degrees C）.` ❌（全角括号） | **0.500** |
///
/// 整批平均 **0.700**、低置信度占比 **0%**，而 `looksWeak` 要的是「平均 < 0.5 **且**
/// 占比 > 0.8」——差得远。反方向同样坏：中文图上**正确**的「不良反应」只有 **0.300**，
/// 是整批最低的。**错的给 0.500、对的给 0.300，置信度在这件事上两头都没有分辨力。**
///
/// ## 它改问什么
///
/// 不问「你选的和系统语言一样吗」，而问「**认出来的这段文字，像不像我们递进去的那门语言**」。
/// 把整段识别结果交给 `NLLanguageRecognizer`，看我们递交的语言一共占了多少概率质量。
///
/// 实测八种情况（占比 = 我们递交的语言所占概率质量）：
///
/// | 情况 | 占比 | 该提示 |
/// |---|---|---|
/// | 英文图 / `zh-Hans` ← 真机上出问题的那一种 | **0.00** | ✅ |
/// | 英文图 / `en-US` | **1.00** | — |
/// | 德文图 / `en-US`（同为拉丁字母，最难） | **0.00**（判为 `de` 1.00） | ✅ |
/// | 中文图 / `zh-Hans` | **1.00** | — |
/// | 中文图 / `en-US`（输出是垃圾） | **0.00** | ✗ 见「已知够不到的地方」 |
/// | 英文 2 行 / `zh-Hans` | **0.00** | ✅ |
/// | 中文 2 行 / `zh-Hans` | **0.92** | — |
/// | 只有 6 字「DOSAGE」 | 0.00（**误判成法语 0.60**） | 靠字数门槛挡掉 |
///
/// 该提示的全是 0.00，不该提示的全在 0.92 以上，中间是**空的**。这比置信度那条线干净得多，
/// 而且它**完全不看设备语言**——一个界面是德语、设备是德语的人拍中文，它照样能判出来。
///
/// ## 已知够不到的地方（写清楚，不假装覆盖）
///
/// **英文设备 + 跟随系统 + 拍中文文件，仍然不会提示。**
///
/// 这一头是上面那个场景的镜像：模型选反了，输出 `mzmz` 这类垃圾，
/// `NLLanguageRecognizer` 连一段像样的文字都拿不到，给出的最高项是 `pl 0.44`。
/// 它确实「不是我们递交的语言」，但它**也不是一门真实的语言**——`pt 0.26`、`nl 0.14`
/// 跟着排在后面，全都不是。这种场合没有任何一条建议是对的，唯一诚实的选择是**不说**。
/// `minimumSuggestionConfidence` 挡的就是它：0.44 够不到 0.8，于是一句话都不给。
///
/// **代价说清楚**：这一头真的坏了，而 App 保持沉默。用户看到的是乱码正文、没有任何解释，
/// 得自己想到「哦这是中文，去设置里改成中文」。要覆盖它得靠别的手段（比如识别结果里
/// 汉字占比、或者拿两门语言各跑一遍比谁认得更像话），不是把这条线调低——
/// 调低只会让波兰语那种建议漏出来。**刻意留着这个洞，也好过给一条把人带偏的建议。**
///
/// 本文件只 `import Foundation` 与 `NaturalLanguage`，不引用 `L10n`、`Vision` 或任何 UI
/// 类型，好让 `tools/ocr-bench/langcheck` 能把它单独编出来跑断言。判定的两个输入——
/// 「本机支持清单」与「这段文字被判成了什么语言」——都由调用方注入，所以断言不依赖
/// 跑它的那台机器上装了什么模型。
enum RecognitionLanguageAudit {

    /// 判定通过时给出的建议。
    struct Verdict: Equatable {
        /// 建议改用的那一档。**保证在 `supported` 里**——UI 要拿它去取名，用户也真的能选到。
        let suggestedCode: String
    }

    // MARK: - 判定

    /// 该不该提示「识别语言可能选错了」，以及建议改成哪一档。
    ///
    /// - Parameters:
    ///   - askedCodes: 这次真正递给 Vision 的语言数组。
    ///   - recognizedText: 这次认出来的全部文字。
    ///   - supported: 本机 Vision 支持的码。建议的那一档必须落在里面。
    /// - Returns: 该提示时给出建议；不该提示、或判不了时返回 nil。
    static func audit(askedCodes: [String],
                      recognizedText: String,
                      supported: [String]) -> Verdict? {
        // 太短就不判。见 `minimumCharacters`。
        guard recognizedText.count >= minimumCharacters else { return nil }
        return verdict(askedCodes: askedCodes,
                       hypotheses: detect(recognizedText),
                       supported: supported)
    }

    /// 判定的**纯逻辑**部分：给定「用了哪些码」和「这段文字被判成了什么语言」，决定要不要提示。
    ///
    /// 与 `detect` 分开是为了可断言：`detect` 调的是系统模型，换台机器、换个系统版本都可能
    /// 给出不同的结果，把它写进断言等于让测试依赖环境。这里只留决策本身。
    static func verdict(askedCodes: [String],
                        hypotheses: [(code: String, probability: Double)],
                        supported: [String]) -> Verdict? {
        guard !askedCodes.isEmpty else { return nil }

        // 我们递交的语言一共占了多少概率质量。低到 `massCeiling` 以下才算「不是这一档」。
        let mass = hypotheses
            .filter { h in askedCodes.contains { sameLanguage($0, h.code) } }
            .reduce(0.0) { $0 + $1.probability }
        guard mass < massCeiling else { return nil }

        // 建议要落到一个**用户真的能选到、而且识别器自己也真有把握**的档上。
        // 第二个条件是必需的，理由见 `minimumSuggestionConfidence`——少了它，
        // 「英文模型读中文」那种输出垃圾的场合会建议用户改用波兰语。
        for h in hypotheses.sorted(by: { $0.probability > $1.probability }) {
            guard h.probability >= minimumSuggestionConfidence else { return nil }
            if let code = supported.first(where: { sameLanguage($0, h.code) }) {
                // 建议的和已经在用的是同一档，就没有建议可言。
                guard askedCodes.allSatisfy({ !sameLanguage($0, code) }) else { return nil }
                return Verdict(suggestedCode: code)
            }
        }
        return nil
    }

    // MARK: - 问模型

    /// 这段文字是什么语言，按概率从高到低。`withMaximum` 取得够大，是因为
    /// `verdict` 要把我们递交的那几门语言的概率**加起来**——只取前几名会漏掉质量，
    /// 让占比虚低，从而误报。
    static func detect(_ text: String) -> [(code: String, probability: Double)] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: hypothesisLimit)
            .map { (code: $0.key.rawValue, probability: $0.value) }
            .sorted { $0.probability > $1.probability }
    }

    // MARK: - 语言码比较

    /// 两个语言码是不是同一门语言。
    ///
    /// 语言部分必须相同；**任一方写了文字子标签时，文字也必须相同**。后半句是必需的：
    /// `zh-Hans` 与 `zh-Hant` 的语言部分都是 `zh`，只比语言部分会把它们当成同一门，
    /// 于是「拿繁体模型读简体文本」——本仓库一直在防的那个模式——会被判成「没问题」。
    ///
    /// 一边没写文字就不追究：`en`（模型的输出）与 `en-US`（我们递交的）是同一门。
    static func sameLanguage(_ a: String, _ b: String) -> Bool {
        let (langA, scriptA) = parts(a)
        let (langB, scriptB) = parts(b)
        guard !langA.isEmpty, langA == langB else { return false }
        if let scriptA, let scriptB { return scriptA == scriptB }
        return true
    }

    private static func parts(_ code: String) -> (lang: String, script: String?) {
        let fields = code.lowercased().split(separator: "-").map(String.init)
        let lang = fields.first ?? ""
        let script = fields.dropFirst().first { $0 == "hans" || $0 == "hant" }
        return (lang, script)
    }

    // MARK: - 常数（全部实测标定，改动前先看数值来源）

    /// 短于它就不判，一个字的判断都不做。
    ///
    /// `NLLanguageRecognizer` 在很短的文字上自己就不可靠，实测：
    ///
    /// | 文字 | 字数 | 判定 |
    /// |---|---|---|
    /// | `DOSAGE` | 6 | **fr 0.60**（错） |
    /// | `用法用量` | 4 | **zh-Hant 0.44**（文字都判反了） |
    /// | `DOSAGE` + 一行正文 | 55 | en 0.99 ✅ |
    /// | 中文两行 | 23 | zh-Hans 0.92 ✅ |
    ///
    /// 6 到 23 之间没有样本，所以取 30 —— 落在已测的稳定区之上、又有余量。
    /// **代价**：只拍了一两行字的照片不会得到提示。这是故意换的：宁可少说一句，
    /// 也不拿一个 6 个字符时就敢给出 0.60 的法语当判据。
    static let minimumCharacters = 30

    /// 我们递交的语言所占概率质量低于它，才算「这次不是这一档」。
    ///
    /// 实测该提示的一律 **0.00**、不该提示的最低 **0.92**（只认了两行中文那次），
    /// 所以 0.2 两边都有很大余量。取这么低是因为两个方向的代价不对称：
    /// 误报是当着做对了的人的面说他可能错了，漏报只是少显示一句提示。
    static let massCeiling = 0.2

    /// 取多少条假设。取值足够大是为了让 `verdict` 求和时不会漏掉质量——
    /// 漏了会让占比虚低，把「没问题」判成「有问题」。
    static let hypothesisLimit = 30

    /// 建议的那一档，识别器自己至少要有这么大的把握。**少了这一条，这个特性会害人。**
    ///
    /// 只看「在不在 `supported` 里」是不够的——`pl-PL` 本身就在 Vision 的 33 条清单里，
    /// 它并不是一条「用户选不到的码」。真正的问题是**这个判定本身不可信**：
    /// 英文模型读中文，输出 `mzmz` 这类垃圾，`NLLanguageRecognizer` 的第一名是
    /// `pl 0.44`，第二名 `pt 0.26`、第三名 `nl 0.14`——三个都在清单里，
    /// 于是光靠清单这一条，App 会建议中文用户去改用**波兰语**。照做只会更糟。
    ///
    /// 真判出来的场合，第一名是完全另一副样子：
    ///
    /// | 情况 | 第一名 | 置信度 |
    /// |---|---|---|
    /// | 英文图 / `zh-Hans` | en | **1.00** |
    /// | 德文图 / `en-US` | de | **1.00** |
    /// | 英文 2 行 / `zh-Hans` | en | **0.99** |
    /// | 中文图 / `en-US`（垃圾） | pl | **0.44** ←要挡的就是它 |
    /// | 只有 6 字「DOSAGE」 | fr | 0.60（另有字数门槛） |
    ///
    /// 已测的「该提示」最低 **0.99**、「不该提示」最高 **0.60**，中间是空的。
    /// 取 0.8 落在空档里，两边都留了余量。
    ///
    /// **2026-09-16 真机补记**：这张表原先五个点全是合成图。真机上两个方向都走过一遍——
    /// 中文系统语言拍英文（该提示）提示出现、照做后效果明显变好；同机器拍中文（不该提示）
    /// 没有提示。所以 0.8 这条线在真实照片上成立，不只是标定。
    ///
    /// **改这个值之前仍然先补真实样本**：真机各一次只证明「成立」，不足以给出「余量有多少」。
    static let minimumSuggestionConfidence = 0.8
}
