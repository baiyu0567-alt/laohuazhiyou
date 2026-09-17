// 断言 `TextLayout` 的版式重建：视觉行 → 段落。
//
// **喂的是手造的 `TextLine`，不是图片，也不问 Vision。** 这一层的输入是几何，
// 那断言就该直接喂几何——这样每条断言的期望值是从图形上读出来的，不是从某台机器
// 某次识别的输出里抄来的。换台机器、换个系统版本，结果不变。
//
// 覆盖三件事，按 `TextLayout` 自己的分法：分栏、排序、成段。

import Foundation

var failures = 0
var total = 0

func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    total += 1
    if actual == expected {
        print("  ✅ \(label) → \(actual)")
    } else {
        failures += 1
        print("  ❌ \(label)：实际 \(actual)，期望 \(expected)")
    }
}

/// 造一行的简写。`top` 为 0 是画面顶边，`width` 是这一行**文字本身**的宽度。
func line(_ text: String, x: Double, top: Double, width: Double, height: Double = 0.02) -> TextLine {
    TextLine(text: text, minX: x, top: top, width: width, height: height)
}

/// 一栏正文：从 `firstTop` 起，每行下移 `step`，行宽 `width`。
func column(_ texts: [String], x: Double, firstTop: Double, step: Double,
            width: Double, height: Double = 0.02) -> [TextLine] {
    texts.enumerated().map { index, text in
        line(text, x: x, top: firstTop + Double(index) * step, width: width, height: height)
    }
}

print("TextLayout：版式重建")

// MARK: - 分栏

print("\n【分栏】")

// 单栏：所有行横向范围重叠，并集连续，不该切出任何缝。
let single = column(["第一行正文内容", "第二行正文内容", "第三行正文内容"],
                    x: 0.10, firstTop: 0.10, step: 0.04, width: 0.80)
expect(TextLayout.blocks(in: single).count, 1, "单栏 → 一栏")

// 双栏：中间一条明显的竖缝，应切成两栏，且左栏在前。
let twoColumnLeft = column(["左栏第一行", "左栏第二行", "左栏第三行"],
                           x: 0.05, firstTop: 0.10, step: 0.04, width: 0.40)
let twoColumnRight = column(["右栏第一行", "右栏第二行", "右栏第三行"],
                            x: 0.55, firstTop: 0.10, step: 0.04, width: 0.40)
let twoColumn = twoColumnLeft + twoColumnRight
let splitColumns = TextLayout.blocks(in: twoColumn)
expect(splitColumns.count, 2, "双栏 → 两栏")
expect(splitColumns.first?.map(\.text), ["左栏第一行", "左栏第二行", "左栏第三行"],
       "双栏 → 左栏整栏在前")

// **这条是重点：真实照片上两栏的行不会恰好等高。**
// 旧的比较器「按 origin.y 降序、minX 只在完全相等时兜底」在这种输入下会把两栏交错。
// 分栏在先、排序在后，交错就不可能发生——左右两栏的 y 故意错开半行。
let staggeredLeft = column(["左一", "左二", "左三"], x: 0.05, firstTop: 0.10, step: 0.04, width: 0.40)
let staggeredRight = column(["右一", "右二", "右三"], x: 0.55, firstTop: 0.12, step: 0.04, width: 0.40)
let staggered = staggeredLeft + staggeredRight
expect(TextLayout.paragraphs(from: staggered),
       ["左一左二左三", "右一右二右三"],
       "双栏且两栏错开半行 → 不交错（旧比较器在这里会串行）")

// 缩进不该造出假栏：段首空两格的行窄一些，但别的行覆盖了那段 x，并集是连续的。
let indented = [
    line("　　段首缩进的一行，比别的行短一点点", x: 0.14, top: 0.10, width: 0.76),
] + column(["接下来的第二行是齐头的正文", "第三行也是齐头的正文内容"],
           x: 0.10, firstTop: 0.16, step: 0.04, width: 0.80)
expect(TextLayout.blocks(in: indented).count, 1, "段首缩进不产生假栏")

// 居中标题：横向范围窄，但被正文行覆盖，同样不该切栏。
let centered = [
    line("居中的标题", x: 0.35, top: 0.04, width: 0.30, height: 0.035),
] + column(["正文第一行的内容在这里", "正文第二行的内容在这里"],
           x: 0.10, firstTop: 0.12, step: 0.04, width: 0.80)
expect(TextLayout.blocks(in: centered).count, 1, "居中标题不产生假栏")

// 三栏。
let threeColumn = column(["甲一", "甲二"], x: 0.03, firstTop: 0.10, step: 0.04, width: 0.25)
    + column(["乙一", "乙二"], x: 0.37, firstTop: 0.10, step: 0.04, width: 0.25)
    + column(["丙一", "丙二"], x: 0.71, firstTop: 0.10, step: 0.04, width: 0.25)
expect(TextLayout.blocks(in: threeColumn).count, 3, "三栏 → 三栏")

// 栏内排序：自上而下；同一基线上按 minX（ordercheck 钉的同一条不变量）。
let sameRow = [line("右", x: 0.60, top: 0.20, width: 0.10),
               line("左", x: 0.10, top: 0.20, width: 0.10)]
expect(TextLayout.readingOrder(sameRow).map(\.text), ["左", "右"], "同基线按 minX 升序")

// **排序比的是基线，不是上边缘。** 同一行上字大小不一时，上边缘会跟着字号一起变，
// 基线不会：小字 top 0.10 高 0.02（基线 0.12），大字 top 0.08 高 0.06（基线 0.14）。
// 按上边缘排会得出「大、小」，把右边那块的顺序提前；按基线排才是「小、大」，
// 与它们在画面上的左右一致。行高一致时两种排法结果相同，所以这条只有在混排
// （表格、标题、带上标的药名）里才看得出差别。
let mixedSizes = [line("小", x: 0.10, top: 0.10, width: 0.10),
                  line("大", x: 0.60, top: 0.08, width: 0.10, height: 0.06)]
expect(TextLayout.readingOrder(mixedSizes).map(\.text), ["小", "大"],
       "同一行字大小不一 → 按基线排（上边缘会跟着字号跑偏）")

// MARK: - 成段

print("\n【成段】")

// 一句话折成三行：行距均匀、左边界齐平 → 接成一段。
let wrapped = column(["口服。成人一次一片，", "一日三次，饭后服用。", "请勿超量。"],
                     x: 0.10, firstTop: 0.10, step: 0.04, width: 0.80)
expect(TextLayout.paragraphs(from: wrapped),
       ["口服。成人一次一片，一日三次，饭后服用。请勿超量。"],
       "折行的句子接成一段（中文不加空格）")

// 拉丁文接行要加空格。
let latinWrapped = column(["Take one tablet three times", "daily after meals. Do not", "exceed the stated dose."],
                          x: 0.10, firstTop: 0.10, step: 0.04, width: 0.80)
expect(TextLayout.paragraphs(from: latinWrapped),
       ["Take one tablet three times daily after meals. Do not exceed the stated dose."],
       "折行的句子接成一段（拉丁文加空格）")

// 段间距明显大于正常行距 → 断开。
let twoParagraphs = column(["第一段的第一行", "第一段的第二行"],
                           x: 0.10, firstTop: 0.10, step: 0.04, width: 0.40)
    + column(["第二段的第一行", "第二段的第二行"],
             x: 0.10, firstTop: 0.10 + 0.04 * 2 + 0.05, step: 0.04, width: 0.40)
expect(TextLayout.paragraphs(from: twoParagraphs),
       ["第一段的第一行第一段的第二行", "第二段的第一行第二段的第二行"],
       "段间距明显偏大 → 断成两段")

// 行距均匀但段首缩进 → 断开。间距信号不成立，靠缩进信号。
//
// **缩进量要按本页字宽算得诚实。** 缩进的判据是「比本页字宽大多少倍」，所以夹具里
// 那个位移必须**真的是两个字**：正文 13 字占 0.80 ⇒ 字宽约 0.0615 ⇒ 缩进两个字
// 约 0.123。只缩 0.05（不到一个字）在真版式里根本不存在，拿它当夹具是拿一个自相矛盾
// 的图形去问代码要答案——测出来的失败是夹具的，不是代码的。
let indentBreak = column(["上一段写到最后一行就结束了", "写到这里这一行就到头了内容", "接下来是这一段的最后一行了"],
                         x: 0.10, firstTop: 0.10, step: 0.04, width: 0.80)
    + [line("　　这一段的首行缩进两个字", x: 0.223, top: 0.22, width: 0.677)]
expect(TextLayout.paragraphs(from: indentBreak).count, 2, "段首缩进 → 断成两段")

// 上一行是短行（没写满）且下一行回到左边界 → 断开。
// 同样要有足够多的满行来定出「本页典型右边界」——两行时那个中位数落在 0.65，
// 既不是满行也不是短行，判据虽然碰巧成立，但成立的理由是错的。
let shortLineBreak = column(["上一段写到最后一行就结束了", "写到这里这一行就到头了内容", "接下来是这一段的最后一行了"],
                            x: 0.10, firstTop: 0.10, step: 0.04, width: 0.80)
    + [line("上一段的最后一行很短", x: 0.10, top: 0.22, width: 0.30),
       line("下一段第一行回到左边界的完整宽度", x: 0.10, top: 0.26, width: 0.80)]
expect(TextLayout.paragraphs(from: shortLineBreak).count, 2, "上一行短且下一行齐头 → 断成两段")

// **满行 → 小标题 → 满行**：小标题与前后的距离都比正文行距大，于是它自成一段。
//
// 这条是 `paracheck` 端到端跑出来的。原先判据算的是
// `normalGap + max(normalGap * 0.8, height * 0.35)`——**基准取错了**：
// `normalGap` 是行间已有的空白，随行距设置漂（1.0 倍行距时趋近 0，2.0 倍时约一个行高），
// 拿它当基数会让阈值的松紧跟着行距走，而且方向是反的。改成以**行高**为基准。
//
// 所以这里的两条断言是同一条不变量的两面：**同样的版式结构，行距松紧变了，结果必须一样。**
// 只钉一边的话，把系数往另一边调都「通过」。
// **五行，不能少。** 只有三行时两个间距样本就把中位数定死，它既不是正文行距也不是
// 小标题间距，判据的基准整个是假的——那样的夹具就算通过也什么都没钉住。
// 两行满行 + 小标题 + 两行满行：四个间距里三个是正文行距，中位数才落在正文上。
func headingFixture(step: Double) -> [TextLine] {
    let height = 0.02
    let bodyGap = step - height        // 行高 0.02，正文行距 step
    let headingGap = bodyGap + 0.02    // 小标题上方再多留一段空白
    // (文字, 行宽, 与**上一行**之间的空白)。间距直接写出来，不由位移反推：
    // 上一版是写 `top += bodyGap + headingGap` 的，多加了那一个 bodyGap，
    // 实际得到 0.06 而不是 0.05——夹具差一点就没测到它声称要测的东西。
    let rows: [(String, Double, Double)] = [
        ("上一段正文写满了一整行到这里结束", 0.80, 0),
        ("第二行也是写满的正文内容接着上面", 0.80, bodyGap),
        ("不良反应", 0.12, headingGap),
        ("偶见皮疹、瘙痒、恶心、胃部不适等。", 0.80, bodyGap),
        ("请立即停药并咨询医师如何处理。", 0.80, bodyGap),
    ]
    var top = 0.05
    var lines: [TextLine] = []
    for (index, row) in rows.enumerated() {
        if index > 0 { top += height + row.2 }
        lines.append(line(row.0, x: 0.10, top: top, width: row.1))
    }
    return lines
}

let headingParagraphs = ["上一段正文写满了一整行到这里结束第二行也是写满的正文内容接着上面",
                         "不良反应",
                         "偶见皮疹、瘙痒、恶心、胃部不适等。请立即停药并咨询医师如何处理。"]
expect(TextLayout.paragraphs(from: headingFixture(step: 0.03)), headingParagraphs,
       "行距紧：满行 → 小标题 → 满行，小标题自成一段")
expect(TextLayout.paragraphs(from: headingFixture(step: 0.05)), headingParagraphs,
       "行距松：同一版式结果不变（旧公式的阈值跟着行距涨，这里会漏判小标题）")

// 反方向：**折行的句子不能被拆散**，而且同样不随行距漂。
// 这条是上一条的对照——只有两条一起，调系数才算被两个方向夹住。
func wrappedFixture(step: Double) -> [TextLine] {
    column(["一段话折了三行，说的是同一件事，", "中间没有任何段落间隔，", "所以它必须留在同一个段落里。"],
           x: 0.10, firstTop: 0.10, step: step, width: 0.80)
}

expect(TextLayout.paragraphs(from: wrappedFixture(step: 0.03)).count, 1,
       "行距较松：折行的句子仍是一段（不误拆）")
expect(TextLayout.paragraphs(from: wrappedFixture(step: 0.05)).count, 1,
       "行距更松：折行的句子仍是一段（不误拆）")

// 居中标题要单独成段。**夹具必须有足够多的正文行**：段间距是跟本页相邻行距的**中位数**
// 比的，只有两行时那个中位数就是唯一那个间距，间距信号结构上不可能触发。
// 真实版式里正文几行均匀行距提供基准，标题与正文之间那道更大的空档才量得出来。
let centeredTitle = [
    line("用法用量", x: 0.40, top: 0.06, width: 0.20, height: 0.035),
] + column(["口服，一次一片，一日三次", "饭后服用，请勿超量", "儿童用量请遵医嘱"],
           x: 0.10, firstTop: 0.14, step: 0.04, width: 0.80)
expect(TextLayout.paragraphs(from: centeredTitle),
       ["用法用量", "口服，一次一片，一日三次饭后服用，请勿超量儿童用量请遵医嘱"],
       "居中标题：与正文之间那道更大的空档把它断成独立一段")

// **已知局限，钉在这里免得日后被当成 bug 查一遍**：只有两行时判不出段落。
// 段间距的门槛建立在「本页相邻行距的中位数」上，两行只有一个间距样本，
// 中位数就是它本身，间距信号于是恒不成立。三行以上才有基准。
let twoLinesOnly = [
    line("第一行结束在这里", x: 0.10, top: 0.10, width: 0.80),
    line("第二行离得很远，明显是新的一段", x: 0.10, top: 0.20, width: 0.80),
]
expect(TextLayout.paragraphs(from: twoLinesOnly).count, 1,
       "已知局限：只有两行时分不出段落（无基准可比）")

// **包围盒上下叠着（间距为负）的两行，不是段边界。**
//
// Vision 会把**同一个视觉行**按字体样式切成几块，各块高度不一，底边于是互相穿插——
// 真机那张照片上，一个块里相邻行距的**中位数量出来是负的**（-0.019）。负的行距把
// 「空档比正常行距大」的阈值拉到 **-0.0095**，于是一个**负的空档**（两行叠着）也算
// 「比阈值大」，被判成段间距——同一段的两行就这么被拆开了。实测就是这么把
// 「…遵守的正道。」和「对戏曲演员来说…」拆成两段的。
//
// 下面五行的数就是照那台机器摆的：四条间距 -0.020、一条 -0.003，中位数 -0.020，
// 阈值 -0.0095，而那条 -0.003 > -0.0095——旧的判据在这里断开。叠着的两行之间根本没有
// 空档，就不可能是段间距，所以这条判据现在要求**间距必须为正**。
let overlappingBoxes = [
    line("同一段的开头部分", x: 0.10, top: 0.100, width: 0.50, height: 0.030),
    line("接着往下写的内容", x: 0.10, top: 0.110, width: 0.50, height: 0.030),
    line("再接着往下写的", x: 0.10, top: 0.120, width: 0.50, height: 0.030),
    line("这条与上一条叠着", x: 0.10, top: 0.147, width: 0.50, height: 0.030),
    line("最后一条也叠着", x: 0.10, top: 0.157, width: 0.50, height: 0.030),
]
expect(TextLayout.paragraphs(from: overlappingBoxes).count, 1,
       "包围盒上下叠着 → 不是段边界（负的「正常行距」把阈值拉到负数，旧判据在这里拆段）")

// **横向完全不相交的两行，不是上下相邻的两行。**
//
// 真机那张照片把对面那页的一列残字也拍了进来（「小」「只」「所」「清」，x 在 0–2%），
// 本页正文从 8% 起。分栏判据**正确地**没把它们当成一栏——五个字的「一栏」当然不是栏——
// 于是残字留在了左栏块里，按底边排进正文的行序，**句子中间就被塞进一个别页的字**。
//
// 它们躲得过上面三条：离上一行不远不近（间距信号）、不缩进（缩进信号）、自身也算不上
// 短行（短行信号）。只有「一个字都不重叠」这条拦得住。
let facingPageBleed = [
    line("正文第一行", x: 0.08, top: 0.100, width: 0.45),
    line("正文第二行", x: 0.08, top: 0.126, width: 0.45),
    line("小", x: 0.00, top: 0.140, width: 0.02),
    line("正文第三行", x: 0.08, top: 0.166, width: 0.45),
]
expect(TextLayout.paragraphs(from: facingPageBleed),
       ["正文第一行正文第二行", "小", "正文第三行"],
       "别页的残字 → 自成一段，不粘进句子中间（旧判据把它粘在「正文第二行」后面）")

// MARK: - 接行细节

print("\n【接行】")

expect(TextLayout.joinSeparator(after: "中文结尾", before: "中文开头"), "", "中文接中文 → 不加空格")
expect(TextLayout.joinSeparator(after: "latin", before: "latin"), " ", "拉丁接拉丁 → 加空格")
expect(TextLayout.joinSeparator(after: "中文结尾", before: "latin"), " ", "中文接拉丁 → 加空格")
expect(TextLayout.joinSeparator(after: "latin", before: "中文"), " ", "拉丁接中文 → 加空格")

// 连字符断词：上一行以 `-` 结尾、下一行小写开头 → 去掉连字符直接接。
expect(TextLayout.joinSeparator(after: "well-", before: "being"), "", "连字符断词 → 去掉连字符")
expect(TextLayout.joinSeparator(after: "well-", before: "Being"), " ",
       "大写开头 → 当真连字符留住（Well-Being 这类）")
expect(TextLayout.joinSeparator(after: "剂量-", before: "说明"), " ",
       "中文接在 `-` 后 → 不当作断词")

// 连字符断词的完整效果。
let hyphenated = column(["Take one tablet three times daily after", "meals. Do not exceed the stated dose."],
                        x: 0.10, firstTop: 0.10, step: 0.04, width: 0.80)
expect(TextLayout.paragraphs(from: hyphenated),
       ["Take one tablet three times daily after meals. Do not exceed the stated dose."],
       "跨行句子的完整接续")

// MARK: - 边界

print("\n【边界】")

expect(TextLayout.paragraphs(from: []), [], "空输入 → 空输出")
expect(TextLayout.paragraphs(from: [line("只有一行", x: 0.10, top: 0.10, width: 0.30)]),
       ["只有一行"], "只有一行 → 一段")
expect(TextLayout.blocks(in: []), [], "分栏/空输入 → 空")

// **通栏标题不该毁掉分栏。** 一条横跨两栏的标题（居中题头够不到左右两栏的边界，
// 但它自己跨过了中间那条缝）在真实说明书上**到处都是**——而它正是真机报回来的那个
// 「左右跳」的成因：
//
// 旧判据取所有行横向区间的**并集**，再要并集内部有零空档。题头把并集连成一片，
// 真正的栏缝于是**一条都找不到**；反倒因题头够不到左栏右边缘而裂出一条窄缝，
// 被当成栏缝挑走。结果是「左栏」自成一块、「右栏 + 题头」粘成另一块——**标题跑到
// 两栏中间**。这一段把那条路堵死：题头自成一块，排在两栏之前。
let crossing = [
    line("横跨两栏的通栏标题", x: 0.05, top: 0.02, width: 0.90, height: 0.035),
] + column(["左栏内容在这", "左栏第二行"], x: 0.05, firstTop: 0.10, step: 0.04, width: 0.40)
  + column(["右栏内容在这", "右栏第二行"], x: 0.55, firstTop: 0.10, step: 0.04, width: 0.40)
expect(TextLayout.blocks(in: crossing).map { $0.map(\.text) },
       [["横跨两栏的通栏标题"], ["左栏内容在这", "左栏第二行"], ["右栏内容在这", "右栏第二行"]],
       "通栏标题 → 自成一块且排在两栏之前（旧判据在这里把标题放进两栏之间）")

// **旧判据真实失败的那种形状**：题头**居中**，够不到左栏的右边缘。
// 于是题头左边裂出一条窄缝（跨越行数 0，比真栏缝还「干净」），真栏缝则被题头跨过。
// 排名**先比宽度**才挑得对——真栏缝总是更宽。
let centeredHeadingPage = [
    line("复方氨酚烷胺片说明书", x: 0.32, top: 0.03, width: 0.36, height: 0.035),
] + column(["左栏第一行正文写在这里", "左栏第二行正文写在这里", "左栏第三行正文写在这里"],
           x: 0.05, firstTop: 0.10, step: 0.04, width: 0.24)
  + column(["右栏第一行正文写在这里", "右栏第二行正文写在这里", "右栏第三行正文写在这里"],
           x: 0.55, firstTop: 0.10, step: 0.04, width: 0.24)
expect(TextLayout.blocks(in: centeredHeadingPage).map { $0.map(\.text) },
       [["复方氨酚烷胺片说明书"],
        ["左栏第一行正文写在这里", "左栏第二行正文写在这里", "左栏第三行正文写在这里"],
        ["右栏第一行正文写在这里", "右栏第二行正文写在这里", "右栏第三行正文写在这里"]],
       "居中题头 + 两栏 → 题头在前、左栏整栏、右栏整栏（真机报的就是这条错）")

// 一条孤零零的短行不该把单栏切成两栏：它和正文之间确实有空档，但一侧**只有它自己**。
// 挡这条的是平衡判据——假空档两侧是「一行 vs 其余所有行」，真栏缝两侧都成栏。
let strayLine = column(["正文第一行写满了整行宽度内容", "正文第二行写满了整行宽度内容",
                        "正文第三行写满了整行宽度内容", "正文第四行写满了整行宽度内容"],
                       x: 0.10, firstTop: 0.10, step: 0.04, width: 0.35)
    + [line("孤零零的一行", x: 0.55, top: 0.30, width: 0.10)]
expect(TextLayout.blocks(in: strayLine).count, 1, "孤零零的一行不产生假栏（平衡判据）")

// **真机那张照片的形状**：两栏之间是一条**不到 1% 的窄缝**，而栏内参差的右边界里
// 藏着一条**更宽的假缝**。
//
// 真机实测：左栏最宽的一行排到 0.5320，右栏最靠左的一行从 0.5360 起——真栏缝只有
// **0.4%**，全页每一条候选都 ≤ 1.6%。这里按同样的比例摆：左栏十行，五条排到 0.53、
// 五条只到 0.50，右栏从 0.535 起。真缝 [0.53, 0.535] 宽 **0.5%**，左栏内部那条假缝
// [0.50, 0.53] 宽 **3%**——假缝比真缝宽六倍。
//
// 两条缝**都过得了那两道筛子**：假缝跨越 5 行（预算 20×25% = 5），两侧平衡 5 行
// （下限 max(2, 20×20%) = 4）。宽度分不开它们，跨越行数也分不开——**只有平衡分得开**：
// 真缝两侧各 10 行，假缝两侧是 5 行 vs 10 行。
//
// 这一条同时钉住两件事：排名**先比平衡**（先比宽度会挑中假缝），以及**没有宽度下限**
// （旧的 2% 下限把真缝连同所有候选一起否掉、只剩假缝——真机上发生的就是这件事）。
let raggedLeftSpec: [(String, Double)] = [
    ("左栏第一行", 0.45), ("左栏第二行", 0.42), ("左栏第三行", 0.45), ("左栏第四行", 0.42),
    ("左栏第五行", 0.45), ("左栏第六行", 0.42), ("左栏第七行", 0.45), ("左栏第八行", 0.42),
    ("左栏第九行", 0.45), ("左栏第十行", 0.42),
]
let narrowSeamPage = raggedLeftSpec.enumerated().map { index, spec in
    line(spec.0, x: 0.08, top: 0.10 + Double(index) * 0.04, width: spec.1)
} + column(["右栏第一行", "右栏第二行", "右栏第三行", "右栏第四行", "右栏第五行",
            "右栏第六行", "右栏第七行", "右栏第八行", "右栏第九行", "右栏第十行"],
           x: 0.535, firstTop: 0.10, step: 0.04, width: 0.40)
let narrowSeamBlocks = TextLayout.blocks(in: narrowSeamPage)
expect(narrowSeamBlocks.count, 2, "0.5% 的真栏缝 + 3% 的假缝 → 仍切成两栏")
expect(narrowSeamBlocks.first?.map(\.text) ?? [], raggedLeftSpec.map(\.0),
       "挑中的是真缝：左栏十行整栏在前（先比宽度会挑中假缝，切走五条长行）")
expect(narrowSeamBlocks.last?.map(\.text) ?? [],
       ["右栏第一行", "右栏第二行", "右栏第三行", "右栏第四行", "右栏第五行",
        "右栏第六行", "右栏第七行", "右栏第八行", "右栏第九行", "右栏第十行"],
       "右栏整栏在后")

print("\n  共 \(total) 条断言")
if failures == 0 {
    print("全部通过")
} else {
    print("\(failures) 条失败")
    exit(1)
}
