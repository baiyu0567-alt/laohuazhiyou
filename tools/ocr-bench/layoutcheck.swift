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
expect(TextLayout.blocks(in: staggered).map { $0.map(\.text) },
       [["左一", "左二", "左三"], ["右一", "右二", "右三"]],
       "双栏且两栏错开半行 → 不交错（旧比较器在这里会串行）")
// ⚠️ 这里原来钉的是段落 `["左一左二左三", "右一右二右三"]`，那是 `columnFlow` 之前写的。
// 这个输入的几何**恰好就是**「左栏写到栏底没写完」的样子——最后一行与其余各行一样满、
// 行尾又没有句末标点——按栏式排版的读法，它本来就该续到右栏顶上。段落期望因此改了；
// 「不该接」的那几种情形由下面【接跨栏句】那一组夹具钉住。
expect(TextLayout.paragraphs(from: staggered), ["左一左二左三右一右二右三"],
       "左栏最后一行写满且停在半句上 → 续到右栏（栏式排版）")

print("\n【接跨栏句】")

// 该接的：左栏最后一行**写满了**（贴住本栏右边界）且**停在半句上**（行尾不是句末标点）。
// 接缝正好落在**破折号**上（`——`，U+2014）：它一度不在 `isCJK` 的区间表里，接缝上
// 会凭空多一个空格，所以这条断言同时也钉住那件事。
let acrossGutter = column(["一句话从左栏底折过来，", "右栏顶上接着写——"],
                          x: 0.05, firstTop: 0.10, step: 0.05, width: 0.40)
    + column(["这就是栏式排版。", "右栏第二行在这里。"],
             x: 0.55, firstTop: 0.10, step: 0.05, width: 0.40)
expect(TextLayout.paragraphs(from: acrossGutter),
       ["一句话从左栏底折过来，右栏顶上接着写——这就是栏式排版。右栏第二行在这里。"],
       "跨栏的一句话接成一段，不因栏缝断在句子中间")

// 接缝落在**弯引号**上（真机那张照片里的第二处）：`’`（U+2019）与 `，` 之间不该有空格。
let quoteSeam = column(["对他说：“必须‘学而时习之’", "，但到台上，我每不能完全照他"],
                       x: 0.10, firstTop: 0.10, step: 0.05, width: 0.40)
expect(TextLayout.paragraphs(from: quoteSeam),
       ["对他说：“必须‘学而时习之’，但到台上，我每不能完全照他"],
       "接缝落在弯引号与中文逗号之间 → 不加空格（U+2019 原本不在区间表里）")

// 弯撇号接拉丁字母：**仍然加空格**，这是故意的，不是遗漏。
// `don’` + `t know` 该接成 `don’t`，而 `James’` + `book` 该接成 `James’ book`——
// 两者形状一模一样（弯撇号 + 小写字母），判不出来，和上面 `-` 断词那条是同一类
// **有歧义**的判断。这里取「加空格」：多一个空格读起来只是顿一下，粘成一个词
// 是把词写错了，两个方向的代价不对称。
// 中文那边没有这个问题：「必须‘学而时习之’」两侧都是中文标点，走的是「两边都 CJK」。
expect(TextLayout.joinSeparator(after: "don’", before: "t know"),
       " ", "弯撇号接拉丁字母 → 加空格（有歧义，取不粘词的那一边）")

// 不该接之一：左栏最后一行**是句末**——这一段在栏底写完了。
let sentenceEnded = column(["这一段的最后一句写完", "了，画上句号。"],
                           x: 0.05, firstTop: 0.10, step: 0.05, width: 0.40)
    + column(["右栏是另一段话。", "它自成一栏。"],
             x: 0.55, firstTop: 0.10, step: 0.05, width: 0.40)
expect(TextLayout.paragraphs(from: sentenceEnded),
       ["这一段的最后一句写完了，画上句号。", "右栏是另一段话。它自成一栏。"],
       "左栏最后一行以句号收尾 → 不接（这一段在栏底写完了）")

// 不该接之二：左栏最后一行**是短行**——没写满就换行，说明这一段结束了。
// 短行的宽度要**手写**：`column` 逐行给的是同一个 `width`，用它造不出短行。
let shortEnded = [
    line("这一段的最后一行只写到一半就换了行，", x: 0.05, top: 0.10, width: 0.40, height: 0.02),
    line("没写满。", x: 0.05, top: 0.15, width: 0.12, height: 0.02),
] + column(["右栏是另一段话。", "它自成一栏。"],
           x: 0.55, firstTop: 0.10, step: 0.05, width: 0.40)
expect(TextLayout.paragraphs(from: shortEnded),
       ["这一段的最后一行只写到一半就换了行，没写满。", "右栏是另一段话。它自成一栏。"],
       "左栏最后一行没写满 → 不接（短行是段尾）")

// 不该接之三：左边那一块**只有一行**——单行块是标题一类的东西，不参与接续。
// 真机那张照片上「速写传统」就是这样，而它又与导语那一块横向重叠，只靠「并排」分不开。
let headingBeside = [line("速写传统", x: 0.05, top: 0.10, width: 0.40, height: 0.035)]
    + column(["右栏第一行正文写在这里", "右栏第二行正文写在这里", "右栏第三行正文写在这里"],
             x: 0.55, firstTop: 0.10, step: 0.05, width: 0.40)
expect(TextLayout.columnFlow(from: headingBeside.prefix(1).map { $0 },
                             to: headingBeside.suffix(3).map { $0 }), false,
       "左边是单行块（标题）→ 不接")

// 不该接之四：两块**上下相邻**，不是并排。左块的右边界伸进了右块的左边界里。
let stackedNotBeside = column(["上面那一块的正文写", "得比较满，几乎到栏宽"],
                              x: 0.05, firstTop: 0.10, step: 0.05, width: 0.40)
    + column(["下面那一块的正文", "接着写下去"],
             x: 0.20, firstTop: 0.30, step: 0.05, width: 0.40)
expect(TextLayout.columnFlow(from: stackedNotBeside.prefix(2).map { $0 },
                             to: stackedNotBeside.suffix(2).map { $0 }), false,
       "上下相邻（横向有重叠）→ 不接")

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

// **页面倾斜时观测盒被撑高** —— 这一条钉的是真机上报回来的反序。
//
// 页面是斜的时，Vision 给的**轴对齐**盒要同时圈住这一行在左端和右端的高度，于是
// `盒高 = 真行高 + |斜率| × 盒宽`：宽碎片被撑高，窄碎片不会。基线
// `bottom = 行基线 + 行高 + 斜率 × maxX` 因此带着**右端**的横向位置，
// 宽窄碎片之间不可比 —— 一行靠左的窄碎片会排到它**上面**那一行靠右的宽碎片之前。
//
// 下面三组几何**是从用户的真照片上抄下来的**（文字用的是订正后的原文，
// 只几何照抄），所以它复现的就是现场：真机上「时习之’」确实跑到了
// 「戏的梅兰芳说…」前面，用户报的就是这个。
let tiltWide = "戏的梅兰芳说：“这是我的法帖，必须‘学而"
let tiltTail = "时习之’"
let tiltRest = "，但到台上，我却不能完全照他这"
let tiltedFragments = [
    line(tiltWide, x: 0.536, top: 0.2250, width: 0.313, height: 0.0689),
    line(tiltTail, x: 0.541, top: 0.2631, width: 0.071, height: 0.0160),
    line(tiltRest, x: 0.608, top: 0.2581, width: 0.244, height: 0.0578),
]
expect(TextLayout.readingOrder(tiltedFragments).map(\.text), [tiltWide, tiltTail, tiltRest],
       "倾斜页：窄碎片不得越过上一行的宽碎片")

// **反证：这条夹具必须能区分两种主序。** 否则它只是碰巧通过，什么都没钉住 ——
// 上一段的断言在改主序之前也是红的才对。这里把「按基线排」的结果也钉下来，
// 于是将来若有人把主序改回 `bottom`，这两条会一起变红，而不是悄悄通过。
expect(tiltedFragments.sorted { $0.bottom < $1.bottom }.map(\.text), [tiltTail, tiltWide, tiltRest],
       "反证：按基线排确实得到错误顺序（说明上面的夹具是有效的）")

// 同一行的两个碎片仍按左右排。倾斜页上 `bottom` 沿行单调、中点也沿行单调，
// 这一条确认换主序没有把**行内**顺序弄反——行内本来就对，别改坏。
let tiltedSameRow = [
    line(tiltRest, x: 0.608, top: 0.2581, width: 0.244, height: 0.0578),
    line(tiltTail, x: 0.541, top: 0.2631, width: 0.071, height: 0.0160),
]
expect(TextLayout.readingOrder(tiltedSameRow).map(\.text), [tiltTail, tiltRest],
       "倾斜页：同一行的碎片仍按 minX 升序")

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

// **包围盒上下叠着的行，不是段边界。**
//
// 斜页上一行的盒高是 `真行高 + |斜率| × 盒宽`，行距比盒高小的时候盒子就互相穿插，
// 「两行之间的空白」于是成了负数。段落判据**不能**去看那段空白：
// 负的正常间距会把阈值拉到**比负间距还负**的地方，于是叠着的两行也「比阈值大」，
// 同一段的两行就这么被拆开。真机那张照片上，实测就是这么把
// 「…创有“绷」和「音”。余叔岩…」拆成两段的（见 `TextLayout.Metrics.normalGap`）。
//
// 判据现在量的是**两个起笔端之间的距离**，正常值取本页那组距离的中位数。
// 下面五行行距一律 0.010、盒高 0.030，盒子叠得很深，但没有一行的行距**偏离**其余各行，
// 所以一段都不该断——这正是这条夹具要钉的东西。
//
// ⚠️ 这条夹具改过一次。原来最后一行摆在 pitch 0.027（其余四行 0.010），为的是让
// 「中位数」不等于「最小值」，好把旧的负阈值逼出来。换成起笔端的判据之后，
// 0.027 就是**本页正常行距的 2.7 倍**，按哪一家的标准都该断段——旧夹具那一条
// 依赖的是旧算法的病，不是版面事实，所以改成行距一致，另加一条专门钉「真有空档要断」。
let overlappingBoxes = [
    line("同一段的开头部分", x: 0.10, top: 0.100, width: 0.50, height: 0.030),
    line("接着往下写的内容", x: 0.10, top: 0.110, width: 0.50, height: 0.030),
    line("再接着往下写的", x: 0.10, top: 0.120, width: 0.50, height: 0.030),
    line("这条与上一条叠着", x: 0.10, top: 0.130, width: 0.50, height: 0.030),
    line("最后一条也叠着", x: 0.10, top: 0.140, width: 0.50, height: 0.030),
]
expect(TextLayout.paragraphs(from: overlappingBoxes).count, 1,
       "包围盒上下叠着（间距为负）→ 不是段边界，五条仍是一段")

// 反过来：盒子同样叠着，但**这一行的行距明显偏离本页其余各行**——那才是段边界。
// 与上一条只差最后一行摆的位置，两条合起来说明这一层判的是「偏离」，不是「间距为正」。
let overlappingBoxesWithGap = [
    line("同一段的开头部分", x: 0.10, top: 0.100, width: 0.50, height: 0.030),
    line("接着往下写的内容", x: 0.10, top: 0.110, width: 0.50, height: 0.030),
    line("再接着往下写的", x: 0.10, top: 0.120, width: 0.50, height: 0.030),
    line("这条与上一条叠着", x: 0.10, top: 0.130, width: 0.50, height: 0.030),
    line("这一段另起", x: 0.10, top: 0.157, width: 0.50, height: 0.030),
]
expect(TextLayout.paragraphs(from: overlappingBoxesWithGap).count, 2,
       "行距偏离本页正常行距 → 断段（同样叠着，但这一行远了一倍多）")

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

// **选项格的右列接着下一题题干**：这不是「上下相邻的两行」，是**两栏**。
//
// 几何逐字照抄 IMG_0006 实测值（第 2 题的选项格 + 第 3 题题干）。去斜之后两条的盒子
// 纵向叠着 0.0046、横向叠着 **0.082**——占窄的那条（`D.` 的 0.320）的 **26%**。
// 「一个字都不许叠」的旧判据于是放行：`D. It's less likely to cause knee injuries.`
// 粘到了下一题题干的**前面**，正是用户报的「有的答案 d 并到下一题 a 之前」。
// 判据与四组实测见 `startsNewParagraph` 第 4 条。
//
// 四条满宽正文行是**为了挡住假栏缝**（与上面两个夹具同一个理由，算式见那里）：
// 夹具里只有这一处并排，中间那条空档两侧的行数就够 `columnBalanceFraction` 了。
let optionGridThenNextStem = [
    line("Race walkers are conditioned athletes. The longest track and field event at the Summer Olympics is the",
         x: 0.116, top: 0.400, width: 0.841),
    line("50-kilometer race walk, which is about five miles longer than the marathon. But the sport's rules require",
         x: 0.116, top: 0.426, width: 0.837),
    line("that a race walker's knees stay straight through most of the leg swing and one foot remain in contact with",
         x: 0.119, top: 0.452, width: 0.833),
    line("the ground at all times. It's this strange form that makes race walking such an attractive activity, says",
         x: 0.120, top: 0.478, width: 0.751),
    line("It takes some practice.", x: 0.122, top: 0.504, width: 0.203, height: 0.0145),
    line("What advantage does race walking have over running?",
         x: 0.143, top: 0.540, width: 0.387, height: 0.0270),
    line("B. It's less challenging physically.", x: 0.541, top: 0.562, width: 0.272, height: 0.0310),
    line("It's more popular at the Olympics.", x: 0.172, top: 0.568, width: 0.244, height: 0.0250),
    line("D. It's less likely to cause knee injuries.", x: 0.544, top: 0.586, width: 0.320, height: 0.0305),
    line("C. It's more effective in body building.", x: 0.144, top: 0.591, width: 0.279, height: 0.0266),
    line("What is Dr. Norberg's suggestion for someone trying race walking?",
         x: 0.146, top: 0.612, width: 0.480, height: 0.0331),
]
expect(TextLayout.paragraphs(from: optionGridThenNextStem),
       ["Race walkers are conditioned athletes. The longest track and field event at the Summer Olympics is the "
        + "50-kilometer race walk, which is about five miles longer than the marathon. But the sport's rules require "
        + "that a race walker's knees stay straight through most of the leg swing and one foot remain in contact with "
        + "the ground at all times. It's this strange form that makes race walking such an attractive activity, says "
        + "It takes some practice.",
        "What advantage does race walking have over running?",
        "It's more popular at the Olympics.",
        "B. It's less challenging physically.",
        "C. It's more effective in body building.",
        "D. It's less likely to cause knee injuries.",
        "What is Dr. Norberg's suggestion for someone trying race walking?"],
       "2×2 选项格 → A B C D 各成一段，`D.` 不粘进下一题题干（旧判据只看「一个字都不叠」）")

// MARK: - 同一视觉行的左右两格（去斜留下的残差）

// 这一组直接考 `visualLines`——它是被改的那一层；`paragraphs` 之上还叠着「怎么切段」，
// 会把这一层的错法掩饰掉。
func order(_ lines: [TextLine]) -> [String] {
    TextLayout.visualLines(in: lines).map { $0.map(\.text).joined() }
}

// 两个夹具都带几条**满宽的行**，这不是为了像真页面，是为了让 `verticalGutters`
// **分不出栏**：并排的几条一放在那里，中间那条空档两侧的行数就够 `columnBalanceFraction`
// 了，`visualLines` 会当场改走「一段一行」那条路，成行与排序根本轮不到跑。
// **真页面上挡掉假缝的就是正文行，这里照搬。**
//
// 要几条才算够——这是三道筛子里最紧的那道（`crossings`）：设满宽行 `c` 条、格子 `m` 个，
// 任何候选空档都落在页内，跨缝数就是 `c`，而预算跟**总行数**走（`(c+m) × 0.25`）。
// 要挡住得 `4c > c + m`，即 **`3c > m`**：四个格子两条、六个格子**三条**。
// 少一条就会从这条路溜过去——那时输出是 `readingOrder` 按 `center` 排的，
// **看着也像对的**，但排的不是同一件事（本夹具少一条时正是如此，见下面的 `词数`）。
// （顺带也钉住了「上下相邻的满宽行不许并排」：它们横向重叠，`sharesRow` 第 1 条当场出局。）

// **页眉去斜之后，同一视觉行各段只差一个有符号的残差**：右列的 `top` 会比左列**更小**
// （看着像更高）。只按 `top` 排就会读成 B A D C。选项格的几何逐字照抄 IMG_0006 第 1 题。
//
// 该并的那一对 `top` 差 0.005（半个矮盒高是 0.0087，够），不该并的那一对差 0.018（不够）
// ——两组各落在一边。判据与尺度见 `TextLayout.sharesRow` / `orderedVertically`。
let skewedOptionGrid = [
    line("导语", x: 0.12, top: 0.600, width: 0.80),
    line("B.", x: 0.544, top: 0.648, width: 0.314, height: 0.0282),
    line("A.", x: 0.165, top: 0.653, width: 0.221, height: 0.0174),
    line("D.", x: 0.543, top: 0.671, width: 0.320, height: 0.0319),
    line("C.", x: 0.168, top: 0.677, width: 0.243, height: 0.0226),
    line("结尾", x: 0.12, top: 0.720, width: 0.80),
]
expect(order(skewedOptionGrid), ["导语", "A.", "B.", "C.", "D.", "结尾"],
       "右列 top 偏小的 2×2 选项格 → 仍按 A B C D 读（只比 top 会读成 B A D C）")

// **表头 2×6**：六个格子的 `top` 铺开 0.008，比矮盒高的一半（0.0066）还大，
// 所以「要求整簇一致」的判据收不住它（`词数` 会被挡在簇外，落到整行后面去）。
// 几何照抄 IMG_0006 实测值。**三条满宽行**：按上面 `3c > m` 的算式，两条不够。
let wideHeaderRow = [
    line("上文", x: 0.12, top: 0.030, width: 0.80),
    line("导语", x: 0.12, top: 0.050, width: 0.80),
    line("文体", x: 0.209, top: 0.078, width: 0.033, height: 0.0131),
    line("题材", x: 0.341, top: 0.081, width: 0.037, height: 0.0132),
    line("词数", x: 0.479, top: 0.086, width: 0.035, height: 0.0132),
    line("建议用时", x: 0.561, top: 0.084, width: 0.074, height: 0.0177),
    line("实际用时", x: 0.665, top: 0.081, width: 0.075, height: 0.0200),
    line("正确率", x: 0.781, top: 0.078, width: 0.060, height: 0.0187),
    line("结尾", x: 0.12, top: 0.110, width: 0.80),
]
expect(order(wideHeaderRow),
       ["上文", "导语", "文体", "题材", "词数", "建议用时", "实际用时", "正确率", "结尾"],
       "2×6 表头 → 按列从左到右（成行判据只看挨着的两条；整簇一致会漏掉「词数」）")


// MARK: - 分流（页边剔除 + 区带分隔）

print("\n【分流】")

// **真机那张照片的全部 61 个观测，几何逐字照抄实测值。** 这里每条期望值都是
// **看着那张页面图**读出来的，不是从某次运行的输出里抄回来的。
//
// 版面的真实结构（看页面图得到，几何数字推不出来）：
//
//     速写传统                        ← 报头
//     你觉得……你又如何看待             ← 导语两行，一句话折出来的
//     流派对……谈谈你的看法。
//     写作角度1：……                   ← 区带标题，横跨栏缝
//       示范片段 / 对于戏曲艺术而言……
//       戏的梅兰芳说……                ← 左栏在前，右栏在后
//     写作角度2：……                   ← 第二个区带标题
//       示范片段 / 流派的传承就是……
//       成的，是流派艺术传承中必须遵守的正道。……
//
// 左边缘竖着的那一列「小 只 所 精 小」是**对开页的邻页**渗进来的，不属于本页。
// 它躲得过每一条栏内判据：不成栏（判据正确地放过了它）、不缩进、算不上短行，
// 离上一行也不远不近。不整页剔掉，它就会混进正文。
let realPage: [TextLine] = [
    line("小", x: -0.0000, top: 0.1715, width: 0.0213, height: 0.0145),
    line("只", x: -0.0000, top: 0.1933, width: 0.0213, height: 0.0145),
    line("所", x: 0.0000, top: 0.2151, width: 0.0194, height: 0.0160),
    line("清", x: 0.0000, top: 0.2384, width: 0.0174, height: 0.0160),
    line("小", x: 0.0000, top: 0.2631, width: 0.0136, height: 0.0145),
    line("速写传统", x: 0.4484, top: 0.0587, width: 0.1031, height: 0.0231),
    line("流派对家副友展的影响呢？请结合本栏目的阅变篇目，谈谈你的看法。", x: 0.1112, top: 0.1127, width: 0.5834, height: 0.0543),
    line("你觉得，京剧演员应如何在对前辈的模仿中进行创新，创造出自己的风格？你又如何看待", x: 0.1483, top: 0.0872, width: 0.6916, height: 0.1025),
    line("写作角度1：在不断发展中“避短”与“扬长”>", x: 0.1209, top: 0.1720, width: 0.5000, height: 0.0408),
    line("示范片段", x: 0.1185, top: 0.2256, width: 0.0811, height: 0.0242),
    line("对于戏曲艺术而言，流派的生成乃至传", x: 0.1543, top: 0.2417, width: 0.3446, height: 0.0294),
    line("承发展其实是戏曲艺术内部的扬长避短。流", x: 0.1136, top: 0.2656, width: 0.3871, height: 0.0299),
    line("派草创者多是在承续传统范式基础上，结合", x: 0.1117, top: 0.2894, width: 0.3891, height: 0.0294),
    line("自身长处，从而创造出新的格局，引发如潮", x: 0.1137, top: 0.3146, width: 0.3887, height: 0.0295),
    line("的效法，最后自成一派。", x: 0.1105, top: 0.3459, width: 0.2151, height: 0.0204),
    line("如余叔岩师承谭鑫培，向谭鑫培学戏学", x: 0.1466, top: 0.3629, width: 0.3600, height: 0.0305),
    line("到了痴迷的程度，但他终未化身为第二个谭", x: 0.1060, top: 0.3886, width: 0.4007, height: 0.0309),
    line("鑫培，而是成为“余派”创始人。在与梅兰", x: 0.1057, top: 0.4131, width: 0.4009, height: 0.0330),
    line("芳合作《桑园寄子》时，余叔岩常听谭鑫培", x: 0.1039, top: 0.4399, width: 0.4065, height: 0.0308),
    line("灌的唱片《洪羊洞》《卖马》。他对来家中对", x: 0.1019, top: 0.4656, width: 0.4086, height: 0.0330),
    line("戏的梅兰芳说：“这是我的法帖，必须‘学而", x: 0.5360, top: 0.2250, width: 0.3131, height: 0.0689),
    line("时习之’", x: 0.5407, top: 0.2631, width: 0.0717, height: 0.0160),
    line("，但到台上，我每不能完全照他这", x: 0.6081, top: 0.2581, width: 0.2439, height: 0.0578),
    line("样唱，因为我的嗓子和老师不一样，得自已", x: 0.5382, top: 0.2758, width: 0.3173, height: 0.0625),
    line("找俏头。”’余教岩穷尽“谭读”之特色。承续", x: 0.5385, top: 0.3003, width: 0.3189, height: 0.0604),
    line("“云避月”的嗓音，但其音量不如老师高，不", x: 0.5383, top: 0.3257, width: 0.3180, height: 0.0580),
    line("如老师清亮，所以他格外注重四音五声，行", x: 0.5429, top: 0.3546, width: 0.3167, height: 0.0508),
    line("腔中善", x: 0.5465, top: 0.3866, width: 0.0659, height: 0.0189),
    line("用“立音”", x: 0.6066, top: 0.3881, width: 0.0930, height: 0.0174),
    line("，妙用“数音”", x: 0.6935, top: 0.3920, width: 0.0955, height: 0.0295),
    line("音”", x: 0.5484, top: 0.4127, width: 0.0330, height: 0.0176),
    line("。", x: 0.5775, top: 0.4215, width: 0.0194, height: 0.0116),
    line("余", x: 0.6066, top: 0.4172, width: 0.0136, height: 0.0102),
    line("，创有“绷", x: 0.7791, top: 0.4070, width: 0.0795, height: 0.0189),
    line("叔岩正是以“避短”至“扬长”，从", x: 0.6238, top: 0.4100, width: 0.2392, height: 0.0422),
    line("而形成了独特的韵味，在“无腔不学谭”的", x: 0.5492, top: 0.4342, width: 0.3151, height: 0.0382),
    line("历史语境中，得以以“会”生世。", x: 0.5504, top: 0.4650, width: 0.2558, height: 0.0293),
    line("区 写作角度2：不仅传承“技艺”，更要传承“道义”", x: 0.3505, top: 0.5321, width: 0.5160, height: 0.0334),
    line("示范片段", x: 0.0988, top: 0.5959, width: 0.0814, height: 0.0189),
    line("流派的传承就是原封原样、照模脱模、", x: 0.1349, top: 0.6125, width: 0.3870, height: 0.0331),
    line("原原本本地继承吗？京剧“麒派”艺术创始", x: 0.0921, top: 0.6400, width: 0.4281, height: 0.0362),
    line("人周信芳曾在探讨戏曲流派的继承与发展时", x: 0.0904, top: 0.6720, width: 0.4297, height: 0.0313),
    line("谈到，这恐怕不是什么继承流派，而是对于", x: 0.0903, top: 0.7020, width: 0.4318, height: 0.0340),
    line("流派的一种伤害。继承流派的正确道路和方", x: 0.0885, top: 0.7331, width: 0.4355, height: 0.0336),
    line("法，不仅是要把一个流派的艺术学下来，而", x: 0.0886, top: 0.7640, width: 0.4372, height: 0.0316),
    line("且要在这个基础上产生新风格、新流派，要", x: 0.0848, top: 0.7951, width: 0.4411, height: 0.0320),
    line("发展流派本身。", x: 0.0830, top: 0.8318, width: 0.1517, height: 0.0254),
    line("戏曲艺术中，“四功五法”的这套程式", x: 0.1273, top: 0.8572, width: 0.4024, height: 0.0333),
    line("体系及其运用原则与理念，是一代代艺人", x: 0.0814, top: 0.8895, width: 0.4496, height: 0.0291),
    line("和演员们在舞台实践中不断创造而累积形", x: 0.0790, top: 0.9226, width: 0.4527, height: 0.0306),
    line("成的，是流派艺术传承中必须遵守的正道。", x: 0.5538, top: 0.6072, width: 0.3303, height: 0.0275),
    line("对戏曲演员来说，传承流派艺术固然是从", x: 0.5592, top: 0.6310, width: 0.3276, height: 0.0331),
    line("一招一式的模仿开始，通过学习前辈们的", x: 0.5531, top: 0.6560, width: 0.3362, height: 0.0384),
    line("唱腔、身段、做工等外在的技艺手段来表", x: 0.5640, top: 0.6805, width: 0.3300, height: 0.0471),
    line("演人物，一步步走进人物内心，丰富自己", x: 0.5633, top: 0.7002, width: 0.3327, height: 0.0577),
    line("的表演。然而，戏曲洗派艺术“传”的不仅", x: 0.5670, top: 0.7286, width: 0.3340, height: 0.0623),
    line("仅是一字一腔、一招一式，更是历代艺术", x: 0.5668, top: 0.7570, width: 0.3351, height: 0.0646),
    line("家在其中所秉持蕴含的道理、规律和方法。", x: 0.5682, top: 0.7815, width: 0.3385, height: 0.0711),
    line("后者在流派艺术传承发展上的意义更趋向", x: 0.5696, top: 0.8084, width: 0.3389, height: 0.0756),
    line("本质，更为重要，出是成曲艺术洗源守正", x: 0.5710, top: 0.8351, width: 0.3398, height: 0.0851),
    line("创新的核心要义。", x: 0.5749, top: 0.9048, width: 0.1712, height: 0.0367),
]

// **页边残字整页剔掉。**
let realBody = TextLayout.pageBody(in: realPage)
expect(realPage.count - realBody.count, 5, "对开页渗进左边缘的 5 个残字被剔掉")
expect(realBody.count, 56, "正文 56 行，一行不少")
expect(realBody.contains { ["小", "只", "所", "清"].contains($0.text) }, false,
       "残字一个都不剩（正文里没有单字的小/只/所/清）")

// **区带标题排在它管的正文之前，且左栏在右栏之前。** 这就是「先段落，然后左右」。
//
// 改动前这里是 7 块，顺序是「左栏整栏（横跨两个区带）→ 写作角度1 → 右栏整栏
// → 写作角度2」——标题被排到了它管的正文**后面**，而且两栏各自横跨两个区带。
let realBlocks = TextLayout.blocks(in: realBody)
expect(realBlocks.map { $0.first?.text ?? "" },
       ["速写传统",
        "你觉得，京剧演员应如何在对前辈的模仿中进行创新，创造出自己的风格？你又如何看待",
        "写作角度1：在不断发展中“避短”与“扬长”>",
        "示范片段",
        "戏的梅兰芳说：“这是我的法帖，必须‘学而",
        "区 写作角度2：不仅传承“技艺”，更要传承“道义”",
        "示范片段",
        "成的，是流派艺术传承中必须遵守的正道。"],
       "8 块，顺序是「报头 / 导语 / 写作角度1 / 左栏 / 右栏 / 写作角度2 / 左栏 / 右栏」")

// 段这一层：前 3 段就是报头、导语（两句并回一段）、区带标题。
// **导语那两行必须并成一段**：它们是同一句话折出来的，拆开读就成了两个半句。
let realParagraphs = TextLayout.paragraphs(from: realPage)
expect(Array(realParagraphs.prefix(3)),
       ["速写传统",
        "你觉得，京剧演员应如何在对前辈的模仿中进行创新，创造出自己的风格？你又如何看待流派对家副友展的影响呢？请结合本栏目的阅变篇目，谈谈你的看法。",
        "写作角度1：在不断发展中“避短”与“扬长”>"],
       "前 3 段：报头 / 导语（并成一段）/ 区带标题")
expect(realParagraphs.contains("示范片段"), true,
       "区带标题之后紧跟着它那一带的内容（「示范片段」是左栏第一行）")

// **跨栏的两句话接回来了。** 两个区带里各有一句话是从左栏底折到右栏顶的：
// 「……他对来家中对」→「戏的梅兰芳说：……」、「……不断创造而累积形」→「成的，是……」。
// 成段是**按块**做的，接缝落在块与块之间，只有 `columnFlow` 这一层看得见。
// 不接的话，读者看到的是半句一段、半句一段。
expect(Array(realParagraphs.prefix(6)).count, 6, "前 6 段仍在（跨栏的接续没有把前面的段并掉）")
expect(realParagraphs.contains { $0.contains("他对来家中对") && $0.contains("戏的梅兰芳说") },
       true, "「……他对来家中对」与「戏的梅兰芳说：……」接成一段（跨过栏缝）")
expect(realParagraphs.contains { $0.contains("而累积形") && $0.contains("成的，是流派艺术") },
       true, "「……而累积形」与「成的，是流派艺术……」接成一段（跨过栏缝）")
// **守正那一句不再被误断。** 行距判据曾经用两个 `top` 之差，而 `top` 量的是盒最高处、
// 落在倾斜盒子的**右端**；「创新的核心要义。」是短行，右端比别的行靠左 0.165，
// 于是量出来的「行距」多出 `|斜率| × 0.165 ≈ 0.027`，翻了一倍还多，被当成段间距。
// 改用盒中点之后残差少一半，落回阈值以内。墨迹实测：那两行的行距 0.0318，
// 与同栏其余各对（0.0308–0.0318）一模一样，本来就没有空档。
expect(realParagraphs.contains { $0.contains("出是成曲艺术洗源守正创新的核心要义。") },
       true, "「……流派守正」与「创新的核心要义。」仍是同一段（短行的盒被撑偏过）")
expect(realParagraphs.count, 10, "全页 10 段（跨栏的两句各接回一处、守正那句不再误断）")

// **「同一个文字流」的判据：两个观测盒在竖直方向叠着。**
//
// 斜页上观测盒被撑高（`盒高 = 真行高 + |斜率| × 盒宽`），同一段相邻两行**总是叠着**
// ——上一行的底边被自己右端那一段撑到了下一行上边之下；到了段边界，下一行整整多出
// 一个段间距，就叠不上了。下面三条用的就是真机照片上的那三对实测值。
expect(TextLayout.sameTextFlow(
    line("你觉得，京剧演员应如何在对前辈的模仿中进行创新", x: 0.1483, top: 0.0872, width: 0.6916, height: 0.1025),
    line("流派对家副友展的影响呢？请结合本栏目的阅变篇目", x: 0.1112, top: 0.1127, width: 0.5834, height: 0.0543)),
       true, "斜页：上一行的盒子被撑高盖住下一行（0.1897 ＞ 0.1127）→ 同一个文字流")
expect(TextLayout.sameTextFlow(
    line("流派对家副友展的影响呢？请结合本栏目的阅变篇目", x: 0.1112, top: 0.1127, width: 0.5834, height: 0.0543),
    line("写作角度1：在不断发展中“避短”与“扬长”>", x: 0.1209, top: 0.1720, width: 0.5000, height: 0.0408)),
       false, "斜页：段边界处叠不上（0.1670 ＜ 0.1720）→ 另起一块")
expect(TextLayout.sameTextFlow(
    line("直页上的上一行", x: 0.10, top: 0.10, width: 0.80),
    line("直页上的下一行", x: 0.10, top: 0.14, width: 0.80)),
       false, "直页：盒子不叠 → 不合并（直页分段归 startsNewParagraph，行为与改动前一致）")

// **并排两栏的上边缘差一点，不是版面的意思，是倾斜噪声。**
// 真机照片上左栏顶 0.2256、右栏顶 0.2250，右栏高出 0.0006；「先比上边缘」于是把
// 右栏排到了左栏前面。`orderBlocks` 先按竖直重叠分行，行内再按左边界排。
let tiltedLeftBlock = column(["左栏第一行正文", "左栏第二行正文", "左栏第三行正文"],
                             x: 0.10, firstTop: 0.2256, step: 0.024, width: 0.30)
let tiltedRightBlock = column(["右栏第一行正文", "右栏第二行正文", "右栏第三行正文"],
                              x: 0.55, firstTop: 0.2250, step: 0.024, width: 0.30)
expect(TextLayout.orderBlocks([tiltedRightBlock, tiltedLeftBlock]).first?.first?.text, "左栏第一行正文",
       "并排两栏上边缘差 0.0006（倾斜噪声）→ 仍按左栏在前")
expect(TextLayout.orderBlocks([tiltedLeftBlock,
                               column(["上方那一块"], x: 0.10, firstTop: 0.60, step: 0.024, width: 0.30)]).count,
       2, "上下不重叠的两块仍是两块，不并成一行")

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
