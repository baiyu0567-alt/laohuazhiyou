import Foundation

/// 一行识别出来的文字，连同它在画面里的位置。
///
/// 坐标一律**归一化**（0–1，相对整张图），y **向下**为正：`top = 0` 是画面顶边。
/// Vision 自己用的是「原点左下、y 向上」的归一化坐标，换算在 `TextRecognitionService`
/// 里做掉一处，好让这一层和它的断言不必每处都记得翻转。
///
/// `width` 是**这一行文字本身的宽度**（包围盒宽度），不是它所在栏的宽度——本类型
/// 不知道「栏」是什么，栏是 `TextLayout.columns` 算出来的。
struct TextLine: Equatable {
    let text: String
    let minX: Double
    let top: Double
    let width: Double
    let height: Double

    var maxX: Double { minX + width }
    var bottom: Double { top + height }

    /// 观测盒的竖直中点。
    ///
    /// **排序和量行距都用它，不用 `top`**，理由是同一条（推导见 `readingOrder`）：
    /// 页面倾斜时观测盒被撑高成 `真行高 + |斜率| × 盒宽`，`top` 于是落在**线的一端**
    /// ——右倾的页面上是右端。`top` 之差里因此掺进 `|斜率| × 两端横向距离`，
    /// 两行宽度不一样时这一项不为零，量级和行距本身相当（真机那张照片实测 0.027
    /// 对行距 0.031）；宽窄两行的 `top` 之间不可比。中点落在盒的**水平中点**上，
    /// 横向距离的变化因此少一半，是被撑高的盒子上最接近「同一横坐标」的那个量。
    var center: Double { top + height / 2 }
}

/// 把 Vision 吐出来的**视觉行**，还原成**段落**。
///
/// ## 它为什么存在
///
/// 真机报回来：「识别的内容缺乏合理的组织，只是单纯地把文字识别出来了」。
/// 根因不在识别质量，而在**管线第一步就把重建组织需要的信息丢了**：
///
/// - `RecognizedBlock` 当时只留 `text` / `topYRatio` / `confidence`，**包围盒整个丢掉**，
///   于是下游谁也不知道这一行的宽度、高度、横向范围；
/// - Vision 给的块是**视觉行**，不是段落，而调用方把每个块当一行文本用 `"\n"` 接起来，
///   「一句话折了三行」于是变成三行断句；
/// - 段落分割的入口 `ReaderViewModel.setParagraphs(from:)` 按 `"\n\n"` 切，而 OCR 路径
///   **从不产生** `"\n\n"`，`paragraphs` 恒为空；
/// - 结果 `ReaderView` 整篇渲染成**一个 `Text`**：没有段间距、没有标题、朗读一路念到底。
///
/// 还有第二处，同一个根因：阅读顺序是「按 `origin.y` 降序、`minX` 只在完全相等时兜底」。
/// 两栏**恰好等高**时兜底是对的，但真实照片上左右两栏的行未必落在同一个 y 上，
/// 差一点就会**逐行交错**——左栏第一行、右栏第一行、左栏第二行……读出来是词串。
///
/// ## 它做的六件事
///
/// 1. **剔页边**（`pageBody`）：对开页的照片会把**邻页**边缘的一列字带进来，先整页剔掉。
///    排在最前，因为它的判据是**整页**的统计量，越往下切越不成立。
/// 2. **分块**（`blocks`）：先按横跨栏缝的**通栏行**把页面切成上下**区带**，再在每个
///    区带里认出竖排的栏，最后给各块排阅读顺序。得到的是「标题 → 左栏 → 右栏」。
/// 3. **拼行**（`visualLines`）：Vision 会在一行中间断开，把一行切成好几段观测，
///    按横向接续把它们拼回**视觉行**。排在排序之前，因为排序的判据在碎片上根本不成立。
/// 4. **排序**（`readingOrder`）：栏内自上而下；拼过行之后由 `visualLines` 自己排。
/// 5. **成段**（`paragraphsInBlock`）：把同一段折出来的若干行接成一句，段与段之间断开。
/// 6. **接跨栏句**（`columnFlow`）：一句话从左栏底折到右栏顶时，段落要跨过栏缝接回来
///    ——第 5 步是**按块**各自成段的，接缝落在块与块之间，只有在这一层才看得见。
///
/// ## 阈值全部是**相对的**
///
/// 这里**没有一个绝对像素或绝对比例的门槛**，全部拿这一页自己的统计量当基准：
/// 正常行距取本页相邻行间距的中位数，缩进取本页的平均字宽，如此等等。
///
/// 这是刻意的，而且是被教训出来的。本仓库上一轮那套置信度阈值是在**两张合成图**上标定的，
/// 结果真机行为与标定不符，返工了两轮（见 `ReaderLaunchCoordinator.looksWeak` 的文档）。
/// 绝对阈值要成立，就必须在足够多的真实照片上量过；相对阈值只要「同一页内部自洽」就成立，
/// 而这一点对任何照片都无条件为真。**代价**是它对「整页版式本身就很怪」的图没有办法——
/// 那种情况本来也不该硬猜。
///
/// 本文件只 `import Foundation`，不碰 `Vision`、`L10n` 或任何 UI 类型，好让
/// `tools/ocr-bench/layoutcheck` 把它单独编出来、用手造的 `TextLine` 跑断言。
enum TextLayout {

    // MARK: - 入口

    /// 视觉行 → 段落。这是这一层的唯一出口。
    ///
    /// 四步依次是：**剔页边**（`pageBody`）→ **分块**（`blocks`）→ **成段**
    /// （`paragraphsInBlock`）→ **接跨栏句**（`columnFlow`）。
    ///
    /// 页边剔除排在最先，因为它是**整页**的判断，用的是整页的统计量；一旦进了
    /// `blocks` 的递归，手上只剩一小撮行，那时算出来的「正文边缘」已经不是同一个意思了。
    ///
    /// 接跨栏句只能排在最后：它要的是**成好段之后**的结果——「上一段是不是写完了」
    /// 这个问题问的是段文本，不是行几何。
    static func paragraphs(from lines: [TextLine]) -> [String] {
        let units = blocks(in: pageBody(in: lines))
        var paragraphs: [String] = []
        for (index, unit) in units.enumerated() {
            let own = paragraphsInBlock(unit)
            guard !own.isEmpty else { continue }
            // 左栏的最后一行写到栏底还没写完 → 右栏顶上那一句是它的下半句。
            // 拼的是**文字**：`paragraphsInBlock` 已经各自成过段，这里只把接缝接上。
            if index > 0, let tail = paragraphs.last,
               columnFlow(from: units[index - 1], to: unit) {
                paragraphs[paragraphs.count - 1] = tail
                    + joinSeparator(after: tail, before: own[0]) + own[0]
                paragraphs += own.dropFirst()
            } else {
                paragraphs += own
            }
        }
        return paragraphs
    }

    // MARK: - 接跨栏句

    /// 左边那一块的最后一行**写到了栏底却没写完**，于是右边那块顶上接着写——
    /// 两块是同一条文字流，接缝处不该断段。
    ///
    /// 判据三条，缺一不可：
    ///
    /// 1. **并排**：左块的右边界不越过右块的左边界。上下相邻的两块横向是**重叠**的
    ///    （行有长有短，但都从左边界起），这条把它们排除掉。
    /// 2. **两块都是多行的栏**。单行的块是标题一类的东西，不参与接续——真机那张照片上
    ///    「速写传统」单行成块，上边缘又与导语那一块叠着，只靠第 1 条分不开。
    /// 3. **左块最后一行写满了、并且没有句末标点**。一句话折到下一栏时，上一栏的最后
    ///    一行必然是满行，且停在半句上（真机那张照片上是「……他对来家中对」和
    ///    「……不断创造而累积形」）。短行、或以「。」结尾的行，都说明这一段在这里写完了。
    ///
    /// **已知边界**：判据 3 是「写没写完」的**间接**证据，不是证明。左右两栏各是一篇
    /// 独立文章（报纸那种）而无栏底又恰好写满、又不以句号收尾时，这里会多接一句。
    /// 手上只有几何，没有比这更强的证据；宁可错接（读起来是多了一处断句）也不漏接
    /// （读起来是半句被切成两段）。
    static func columnFlow(from left: [TextLine], to right: [TextLine]) -> Bool {
        guard let leftRight = left.map(\.maxX).max(),
              let rightLeft = right.map(\.minX).min(),
              leftRight <= rightLeft else { return false }

        let leftLines = visualLines(in: left).compactMap(mergedLine)
        let rightLines = visualLines(in: right).compactMap(mergedLine)
        guard leftLines.count > 1, rightLines.count > 1 else { return false }

        guard let last = leftLines.last, !endsSentence(last.text) else { return false }

        let typicalRightEdge = Metrics(of: leftLines).typicalRightEdge
        return typicalRightEdge > 0
            && last.maxX >= typicalRightEdge * shortLineFraction
    }

    /// 行尾是不是一句话说完了：最后一个**非收尾符号**的字符是句末标点。
    ///
    /// 收尾符号（引号、书名号、括号）要跳过：「……找俏头。”」那句话是说完的，
    /// 但最后一个字符是引号。逗号、顿号、分号**不算**——以它们结尾的行明摆着还有下文。
    private static func endsSentence(_ text: String) -> Bool {
        let closers: Set<Character> = ["”", "’", "」", "』", "》", "）", ")", "\"", "'"]
        let finals: Set<Character> = ["。", "！", "？", "…", "!", "?"]
        for character in text.reversed() {
            if closers.contains(character) { continue }
            return finals.contains(character)
        }
        return false
    }

    // MARK: - 页边剔除

    /// 去掉**别页渗进来**的页边残字。整页级的前置一步，只在出口处做一次。
    ///
    /// 拍书时对开页的邻页总会露出一条边，Vision 把那条边上的一列字照单全收。真机那张
    /// 照片的左边缘竖着一列「小 只 所 精 小」，而本页正文从 x=8% 起，它们在 0–2%。
    /// 它们**不是一栏**——五个字的「一栏」当然不是栏——分栏判据因此正确地放过了它们，
    /// 于是它们留在了左栏块里，成了正文的一部分：生成的文字里凭空多出五个字，前后
    /// 还各断出一段。用户看到的就是第 4、5、6、8、10 段那五个没用的单字。
    ///
    /// **为什么是页级前置，而不是塞进 `blocks` 的递归**：判据要的是「这一侧的中位
    /// 左右边界」，也就是**这一侧整体**的统计量。放进递归就会在每个区带、每条子栏上
    /// 再算一遍，越切越小，最后拿一小撮行去定「正文边缘」，那已经不是同一个问题了。
    static func pageBody(in lines: [TextLine]) -> [TextLine] {
        guard let gutter = verticalGutters(in: lines).first else { return lines }
        let sides = [lines.filter { $0.maxX <= gutter.start },
                     lines.filter { $0.minX >= gutter.end }]
        let dropped = sides.flatMap { side -> [TextLine] in
            // 只对**单栏**的一侧动手。那一侧要是自己还能切出栏来，说明它不是一条正文
            // 栏（可能是另一组并排的栏），「中位数 = 正文边缘」这句话就不成立了。
            guard verticalGutters(in: side).isEmpty else { return [] }
            return pageEdge(in: side)
        }
        guard !dropped.isEmpty else { return lines }
        return lines.filter { !dropped.contains($0) }
    }

    /// 一侧（单栏）里的页边残字：整行落在该侧**中位左边界**的左边，或中位右边界的右边。
    ///
    /// 判据取这一侧自己的中位数，**没有绝对坐标**：页面大小、栏宽、字号都不必知道，
    /// 与文件头那条「阈值全部是相对的」一致。
    ///
    /// 两头都要**整行在外面**（`maxX < 左中位` **且** `minX < 左中位`）：只要有一端
    /// 伸进了正文区，那它就不是「贴在边上的一列残字」，判据就朝安全的那边倒——宁可漏杀。
    ///
    /// **要删的条数达到这一侧的一半就整个放弃。** 中位数会被残字自己带偏：残字一多，
    /// 「中位左边界」就落到残字中间去，判据不再代表正文边缘。删掉正文比漏掉几个残字
    /// 严重得多，所以这条闸门是硬的。
    static func pageEdge(in side: [TextLine]) -> [TextLine] {
        guard side.count > 2 else { return [] }
        guard let left = Metrics.median(side.map(\.minX)),
              let right = Metrics.median(side.map(\.maxX)) else { return [] }
        let dropped = side.filter {
            ($0.maxX < left && $0.minX < left) || ($0.minX > right && $0.maxX > right)
        }
        guard dropped.count * 2 < side.count else { return [] }
        return dropped
    }

    // MARK: - 分块（分栏 + 通栏行）

    /// 把一页切成若干**阅读单元**并给出阅读顺序。单元随后各自成段。
    ///
    /// 单元有两类：**栏**（竖着一条，里面若干行）与**通栏行**（横跨栏缝的行）。
    /// 通栏行又是**区带分隔**：页面先被它们横切成上下几段，每段各自再分栏，
    /// 所以单元的顺序是「区带 0 的块 → 第 0 条通栏行 → 区带 1 的块 → …」，
    /// 一条通栏行**排在它下面那一带的前面**。真实教材页上就是
    /// 「写作角度1：…」→ 左栏 → 右栏 →「写作角度2：…」→ 左栏 → 右栏。
    ///
    /// 递归切分，所以三栏、四栏也走得通。块数上限 `columnLimit` 是防病态输入用的：
    /// 一页被切得太碎，说明这页根本不是分栏版式，那时保序比强行分栏安全。
    static func blocks(in lines: [TextLine]) -> [[TextLine]] {
        guard lines.count > 1 else { return lines.isEmpty ? [] : [lines] }

        guard let gutter = verticalGutters(in: lines).first else {
            return [readingOrder(lines)]
        }

        let left = lines.filter { $0.maxX <= gutter.start }
        let right = lines.filter { $0.minX >= gutter.end }
        let spanningIndices = lines.indices.filter {
            lines[$0].maxX > gutter.start && lines[$0].minX < gutter.end
        }

        let leftBlocks = blocks(in: left)
        let rightBlocks = blocks(in: right)
        guard leftBlocks.count + rightBlocks.count <= columnLimit else {
            return [readingOrder(lines)]
        }

        // 没有通栏行：就是普通的并排两栏，交给 `orderBlocks` 排前后。
        guard !spanningIndices.isEmpty else {
            return orderBlocks(leftBlocks + rightBlocks)
        }

        // **通栏行是区带分隔，不是「插在两栏之间的一块」。**
        //
        // 一页里出现横跨栏缝的行，通常意味着版面被它切成了**上下两个区带**，每个区带
        // 各自还要分栏——真实教材页上就是「写作角度1：…」把页面横切成两段，每段里
        // 各有左右两栏。旧写法只把通栏行当成一块，两栏于是**各横跨整个页面**：左栏
        // 把两个区带的左栏连成一块、右栏同理，而标题被排到了它管的正文**后面**
        // （`blockOrder` 先比上边缘，左栏的 −0.000 小于标题的 0.121，两者上边缘还相等）。
        // 用户报回来的「应该是先段落，然后左右」说的就是这件事。
        //
        // 所以先按通栏行的上边缘把页面横切成区带，再在每个区带里分栏。区带内没有通栏行，
        // 走上面那一支，与旧行为完全一致。
        let separators = spanningIndices.map { lines[$0] }.sorted { $0.top < $1.top }
        let separatorIndices = Set(spanningIndices)

        var bands: [[TextLine]] = Array(repeating: [], count: separators.count + 1)
        for index in lines.indices where !separatorIndices.contains(index) {
            var band = 0
            // 区带 k 是「上边缘 ≥ 第 k−1 条通栏行、且 < 第 k 条」的那些行。**先比上边缘**，
            // 因为版面本身就是自上而下的：一条通栏行切在哪儿，由它的上边缘决定，不由
            // 它的高度（斜页上会被撑高）或中点决定。
            for (position, separator) in separators.enumerated()
            where lines[index].top >= separator.top {
                band = position + 1
            }
            bands[band].append(lines[index])
        }

        // **中间没有正文的连续通栏行攒成一块**，交给 `paragraphsInBlock` 去判它们之间
        // 该不该断段。
        //
        // 道理是：一条通栏行有时候是标题，有时候只是**一段正文里写满整页宽的那一行**
        // ——首行缩进之后的第一行常常就跨过了栏缝。后者与紧跟着它的那条通栏行本来就是
        // 同一段：真机那张照片上「你觉得……你又如何看待」与「流派对……谈谈你的看法。」
        // 是一句话折出来的两行，各自成块就把这句话拆成了两段。攒成一块之后，
        // `startsNewParagraph` 的缩短行判据正好分得开它们——标题是短行、下一行回到
        // 左边界；正文的续行则两头都齐。**这里只做分组，断不断的判断留给那一处**，
        // 免得同一个决定有两个地方各说各话。
        var result: [[TextLine]] = blocks(in: bands[0])
        var run: [TextLine] = []
        for (position, separator) in separators.enumerated() {
            // 与上一条通栏行**接着同一个文字流**才并进这一组，否则它起的是新的一组。
            if let previous = run.last, !sameTextFlow(previous, separator) {
                result.append(run)
                run = []
            }
            run.append(separator)
            let band = bands[position + 1]
            guard !band.isEmpty else { continue }
            result.append(run)
            run = []
            result += blocks(in: band)
        }
        if !run.isEmpty { result.append(run) }
        return result
    }

    /// 两条通栏行是不是**同一个文字流**里挨着的两行。
    ///
    /// **判据是「两个观测盒在竖直方向叠着」。** 这是斜页上唯一还分得开的那条：
    /// 观测盒轴对齐，被页面倾斜撑高成
    /// `[基线 + 斜率×minX, 基线 + 行高 + 斜率×maxX]`，于是同一段里相邻两行**总是叠着**
    /// ——上一行的底边被自己右端那一段撑到了下一行上边之下。到了段边界，下一行整整多出
    /// 一个段间距，就叠不上了。
    ///
    /// 真机那张照片上的三个数（这里就是判据要分的那三对）：
    ///
    /// - 「你觉得…」bottom 0.1897 **＞**「流派对…」top 0.1127 → 叠着 → 同一段
    /// - 「流派对…」bottom 0.1670 **＜**「写作角度1…」top 0.1720 → 没叠上 → 另起一段
    /// - 「速写传统」bottom 0.0817 **＜**「你觉得…」top 0.0872 → 没叠上 → 自成一块
    ///
    /// **为什么不比 `top` 之差**：行距（`top` 之差）在真机照片上量不出来。按 `top` 排序后
    /// 取相邻差的中位数是 0.0126，而真正的栏内行距是 0.024——同一个视觉行被 Vision 切成
    /// 的碎片（差 0.0005）比真行距多得多，中位数落在碎片上。**没有可信的行距，
    /// 「比行距多出多少」这条路就走不通**，剩下的就只有「叠没叠上」。
    ///
    /// **页面不斜时这条恒不成立**（`bottom = top + 行高` 恒小于下一行的 `top`），
    /// 于是每条通栏行各自成块——那正是这个函数改动之前的行为。也就是说这一支只在斜页上
    /// 生效，直页一个字都不变；直页上判段由 `Metrics.startsNewParagraph` 负责，
    /// 而它在那里判得动，因为 `bottom` 没有被撑高。
    static func sameTextFlow(_ upper: TextLine, _ lower: TextLine) -> Bool {
        lower.top < upper.bottom
    }

    /// 同一层里并排的几块排阅读顺序：**先上下分行，行内再从左到右。**
    ///
    /// 只按上边缘比不行。斜页上左右两栏的上边缘差不等于零——真机那张照片上左栏顶
    /// **0.2256**、右栏顶 **0.2250**，右栏比左栏高出 0.0006，于是「先比上边缘」把右栏
    /// 排到了左栏前面。这 0.0006 不是版面的意思，是倾斜和裁切留下的噪声。用户要的是
    /// **「先段落，然后左右」**：标题之后先读左栏，再读右栏。
    ///
    /// 判据：**两块在竖直方向重叠得够多就是同一行**（重叠超过较矮那块的
    /// `rowOverlapFraction`）。并排的两栏高度相当，重叠接近百分之百；上下相邻的两块
    /// 只重叠一点，或者干脆不重叠。行内按 `minX` 升序。
    static func orderBlocks(_ blocks: [[TextLine]]) -> [[TextLine]] {
        guard blocks.count > 1 else { return blocks }

        func top(_ block: [TextLine]) -> Double { block.map(\.top).min() ?? 0 }
        func bottom(_ block: [TextLine]) -> Double { block.map(\.bottom).max() ?? 0 }
        func left(_ block: [TextLine]) -> Double { block.map(\.minX).min() ?? 0 }

        var rows: [[[TextLine]]] = []
        for block in blocks.sorted(by: blockOrder) {
            if let row = rows.last {
                let rowTop = row.map(top).min() ?? 0
                let rowBottom = row.map(bottom).max() ?? 0
                let overlap = min(rowBottom, bottom(block)) - max(rowTop, top(block))
                let shorter = min(rowBottom - rowTop, bottom(block) - top(block))
                if overlap > shorter * rowOverlapFraction {
                    rows[rows.count - 1].append(block)
                    continue
                }
            }
            rows.append([block])
        }
        return rows.flatMap { row in
            row.sorted { a, b in
                if left(a) != left(b) { return left(a) < left(b) }
                if top(a) != top(b) { return top(a) < top(b) }
                return bottom(a) < bottom(b)
            }
        }
    }

    /// 排块序时的第一把钥匙：先比上边缘，平局比左边缘。
    ///
    /// **比较器必须是全序，不能只写上边缘。** 真实两栏页面上左右两栏的上边缘
    /// 几乎总是相等（并排起头），这时 `sorted(by:)` 不保证稳定，两栏顺序就会随运行
    /// 而变——`ordercheck` 存在的全部理由就是不让人踩这一脚，这里不能再踩一次。
    /// 左边缘各不相等，所以拿它破平局就够了。
    ///
    /// 它**只**用来把块排成一个初步的上下次序，给 `orderBlocks` 分行当输入；
    /// 并排两栏谁在前由 `orderBlocks` 的行内排序说了算，不由这里。
    static func blockOrder(_ a: [TextLine], _ b: [TextLine]) -> Bool {
        let topA = a.map(\.top).min() ?? 0
        let topB = b.map(\.top).min() ?? 0
        if topA != topB { return topA < topB }
        let leftA = a.map(\.minX).min() ?? 0
        let leftB = b.map(\.minX).min() ?? 0
        return leftA < leftB
    }

    /// 页内的竖向空档（候选栏缝），最像栏缝的排在前面。
    ///
    /// **判据不是「并集里的零空档」。** 原先的写法取所有行横向区间的并集，再把并集
    /// 内部的空档当候选——那要求**没有任何一行**跨过这条缝。真实说明书恰恰有一条
    /// **居中题头**横跨栏缝，并集于是连成一片，真正的栏缝一条都找不到；反而在题头
    /// 左边（题头够不到左栏右边缘）裂出一条**窄缝**，它被当成栏缝挑走。结果左栏自成
    /// 一块、右栏和题头粘成另一块，**标题跑到两栏中间**。真机报回来的「左右跳」
    /// 就是这一类：缝挑错了，顺序就全错。
    ///
    /// 现在按**边界区间**取候选：把所有 `minX` / `maxX` 排序，相邻两个值之间就是一个
    /// 候选空档。有行跨过某条缝时，那条缝**依然是一个区间**，只是「跨越行数」不为零
    /// ——这两个量随后一起用来排名。
    ///
    /// 两道筛子依次筛：
    ///
    /// 1. **在页内**（左右两侧的留白不是栏缝）、**跨越它的行不能太多**
    ///    （`columnCrossingFraction`）——跨过栏缝的那几行是通栏行，一两条正常，
    ///    多到几十条就说明这条缝不是栏缝；
    /// 2. **两侧都要真的成栏**（`columnBalanceFraction`）。没有这一条，一栏里参差的
    ///    右边界会造出假空档（某行比别的行短一截），而那种空档两侧是「一行 vs 其余
    ///    所有行」，不是两栏。
    ///
    /// **宽度只排名，不设下限。** 这里原先还有一条绝对下限（`gutterMinimumWidth`，
    /// 页宽的 2%），它是在合成图上定的，而真机照片上的真栏缝**窄得多**：一张两栏教材
    /// 页实测只有 **0.4%**——左栏最宽的一行到 0.5320，右栏最靠左的一行从 0.5360 起
    /// ——全页每一条候选都 ≤ 1.6%。下限于是把真缝连同所有候选一起否掉，整页退成一块、
    /// 两栏逐行交错，正是用户报回来的那个样子。阈值被合成图带偏，这已经是第三次，所以
    /// 这次不是把 0.02 改小，而是**取消它**：它原本要挡的「栏内参差的右边界」由上面
    /// 第 2 条挡，宽度不承担筛选。再定一个小一点的数，就又是一次「照着一张图配参数」。
    ///
    /// 排名**先比两侧里少的那一边，再比宽度，最后比跨越行数**。
    ///
    /// 先比平衡，是因为它直接对应「这是一条把页面分成两半的缝」：真栏缝把行分成大致相当
    /// 的两堆，别的位置只会把一小撮行孤立出来。真机那张照片上真缝的少边是 28 行（全页
    /// 61 行），最接近的假缝只有 18 行——差 10 行，很稳。**反过来先比宽度就会挑错**：
    /// 左栏右边界参差，中间裂出一条 0.9% 的空档，比真缝（0.4%）宽一倍多，而且跨越行数
    /// 15 恰好卡在预算 15.25 之下，两条筛子都过得去——它会赢。真缝赢在平衡上，不在宽度上。
    ///
    /// 宽度退为**平局判据**：平衡相当的几条候选（真机上是相邻的几条，同一条栏缝的不同
    /// 画法）里取空档最宽的那条，最不容易有杂框贴在边上。这一条仍要留着，
    /// `centeredHeadingPage` 那条夹具就靠它：题头旁边那条窄缝与真栏缝平衡相同，只有宽度
    /// 分得开。
    static func verticalGutters(in lines: [TextLine]) -> [(start: Double, end: Double)] {
        let boundaries = Set(lines.flatMap { [$0.minX, $0.maxX] }).sorted()
        guard let pageStart = boundaries.first, let pageEnd = boundaries.last,
              boundaries.count > 1 else { return [] }

        let crossingBudget = Double(lines.count) * columnCrossingFraction
        let balanceFloor = max(2.0, Double(lines.count) * columnBalanceFraction)

        var candidates: [(start: Double, end: Double, width: Double, crossings: Int, balance: Int)] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let width = end - start
            guard start > pageStart, end < pageEnd else { continue }

            let mid = (start + end) / 2
            let crossings = lines.filter { $0.minX < mid && mid < $0.maxX }.count
            guard Double(crossings) <= crossingBudget else { continue }

            // 两侧的行数要与后面切分时用的判据**完全一致**（`maxX <= start` /
            // `minX >= end`），否则这里算出来的平衡与切出来的两侧对不上。
            let left = lines.filter { $0.maxX <= start }.count
            let right = lines.filter { $0.minX >= end }.count
            let balance = min(left, right)
            guard Double(balance) >= balanceFloor else { continue }

            candidates.append((start, end, width, crossings, balance))
        }

        return candidates
            .sorted { a, b in
                if a.balance != b.balance { return a.balance > b.balance }
                if a.width != b.width { return a.width > b.width }
                if a.crossings != b.crossings { return a.crossings < b.crossings }
                return a.start < b.start
            }
            .map { ($0.start, $0.end) }
    }

    /// 栏内阅读顺序：自上而下。
    ///
    /// **主序比的是观测盒的竖直中点，不是基线，也不是上边缘。**
    ///
    /// 原因是真实照片上页面是斜的，而倾斜会**把轴对齐的观测盒撑高**：
    /// `盒高 = 真行高 + |斜率| × 盒宽`（实测，见 `layoutcheck` 的 `tiltedFragments`）。于是
    /// `top    = 行基线 + 斜率 × minX`
    /// `bottom = 行基线 + 行高 + 斜率 × maxX`
    /// 两者各自带着碎片**自己那一端**的横向位置。宽碎片和窄碎片之间因此不可比：
    /// 一行靠左的窄碎片，`bottom` 会小于它**上面**那一行靠右的宽碎片。真机上的表现
    /// 就是「时习之'」排到「戏的梅兰芳说…」之前。
    ///
    /// 中点 `(top + bottom) / 2 = 行基线 + 行高/2 + 斜率 × 中点` **把宽度项减掉了**，
    /// 只剩横向位置这一项，量级与行距相当——宽窄碎片于是回到同一个尺度上。
    ///
    /// 平局（中点相等）回落到基线，再平局才看 `minX` 升序。
    /// **这一层不是多余的**：同一行的字大小不一时，上边缘和中点都会跟着字号跑，
    /// 基线不会。行高一致时中点与基线只差一个常量，两种排法结果相同，所以这一层
    /// 只在混排（表格、标题、带上标的药名）里才看得出来。
    ///
    /// `minX` 那一层与 `TextRecognitionService.blocks(from:)` 的比较器是同一条；
    /// 主序那两层那两个函数也一致，只是那边比的是 Vision 坐标里的同一个中点的补量
    /// （`midY`）。`ordercheck` 钉的就是这组不变量。
    /// 分栏之后这里只剩栏内比较，「左栏整栏在前」不再需要在这里表达——它由 `columns`
    /// 的顺序承担，见那里。
    static func readingOrder(_ lines: [TextLine]) -> [TextLine] {
        lines.sorted { a, b in
            if a.center != b.center { return a.center < b.center }
            if a.bottom != b.bottom { return a.bottom < b.bottom }
            return a.minX < b.minX
        }
    }

    // MARK: - 拼行（碎片 → 视觉行）

    /// 一栏之内的碎片拼回**视觉行**，行与行按阅读顺序排好，行内按横坐标排好。
    ///
    /// **为什么必须有这一步。** Vision 给的观测是视觉行，但它**会在一行中间断开**——
    /// 引号、书名号、标点处最容易断。真机那张照片右栏连着两行被切成八段（`minX` / `top` 实测）：
    ///
    /// | 真行 | 碎片 | `minX` | `top` |
    /// |---|---|---|---|
    /// | `…四音五声，行` | `腔中善` | 0.5465 | 0.3866 |
    /// | | `用“立音”` | 0.6066 | 0.3881 |
    /// | | `，妙用“数音”` | 0.6935 | 0.3920 |
    /// | | `，创有“绷` | 0.7791 | 0.4070 |
    /// | `音”。余叔岩正是以“避短”至“扬` | `音”` | 0.5484 | 0.4127 |
    /// | | `。` | 0.5775 | 0.4215 |
    /// | | `余` | 0.6066 | 0.4172 |
    /// | | `叔岩正是以…` | 0.6238 | 0.4100 |
    ///
    /// 按纵向排（`readingOrder`）出来是 `腔中善` `用“立音”` `，妙用“数音”` `，创有“绷`
    /// `音”` `余` `。` `叔岩…`——**`余` 和 `。` 调了个个儿**，读出来是「…绷音”余。叔岩…」。
    /// 更糟的是每个碎片各自成一行，`startsNewParagraph` 逐段判下去，**一句话裂成六段**。
    ///
    /// **判据是横向接续，不是纵向位置。** 同一视觉行的两段，右边那段从左边那段**末尾**
    /// 起笔，横坐标挨着；不同行的两段之间隔着一次换行，右边那段的 `minX` 回到栏的左边界，
    /// 与上一行末尾差着大半个栏宽。所以先按 `minX` 排，再一段一段往已有的行上接：
    /// 接得上就是同一行，接不上就新起一行。**两条都要满足**：
    ///
    /// - **横向够近**（`fragmentGapFraction`）：接续段的起点落在上一段末尾附近。
    /// - **纵向有重叠**（`fragmentOverlapFraction`）：同一视觉行的两段在竖直方向叠着。
    ///
    /// 纵向这条防**误并**：上一行是短行时会提前换行，它的末尾可能恰好落在下一行**缩进后**
    /// 的起点旁边，光看横向就并错了。横向这条防**漏并**：页面倾斜时轴对齐的观测盒被撑高
    /// （`盒高 = 真行高 + |斜率| × 盒宽`），满宽的相邻两行也叠着（实测右栏 L2/L3 叠了 69%），
    /// 只看纵向同样会并错。两条各自都不够，合起来才够——**这不是「多一条更保险」，
    /// 是缺任何一条都有实测反例。**
    ///
    /// **行的顺序按「最左边那一段的 `top`」排，这是整页倾斜下唯一站得住的纵向判据。**
    /// 倾斜把 `top` 撑成 `行基线 + 斜率 × minX`（见 `readingOrder`），横向位置不同的两段
    /// 因此不可比；而**一栏里每行的最左段都落在同一个左边界上**，横向位置相同，那一项
    /// 是同一个常量，相减就抵掉了，量到的差就是真行距。用中点、用 `bottom`、用外接矩形
    /// 都会把这一项带进来，八段碎片上就是这么排错的。
    ///
    /// ⚠️ 这一条不是严格的：**段首缩进的行**最左段缩进了几个字，横向位置与别行差一个缩进，
    /// 于是 `top` 里带上 `斜率 × 缩进`。真机那张照片右栏斜率约 0.155、缩进约 0.036，
    /// 误差 0.006，是行距 0.024 的两成——**不足以让相邻两行换位**（相邻两行差一整个行距），
    /// 但别拿它去判「行距是否均匀」。
    static func visualLines(in block: [TextLine]) -> [[TextLine]] {
        guard block.count > 1 else { return block.isEmpty ? [] : [block] }
        // **块内还分得出栏，说明这一块不是「一栏」。** `blocks` 只有两条路会走到这里：
        // 栏数超过 `columnLimit`，或整页塌成一块。那时候横向接续说明不了任何事——
        // 真栏缝只有 0.4% 宽，左栏末尾到右栏行首的横向距离小得能过接续判据，
        // 两栏会当场并成一行。退回**一段一行**，也就是这一步之前的排法。
        guard verticalGutters(in: block).isEmpty else {
            return readingOrder(block).map { [$0] }
        }

        let pieces = block.sorted { a, b in
            if a.minX != b.minX { return a.minX < b.minX }
            return a.top + a.height / 2 < b.top + b.height / 2
        }

        var lines: [[TextLine]] = []
        for piece in pieces {
            // 可能不止一行接得上（不同行在竖直方向叠着时会有多条候选），
            // 取**末尾最靠右**的那条：那才是紧挨着这一段的上一段。
            let candidates = lines.indices.filter { continues(piece, lines[$0]) }
            if let nearest = candidates.max(by: { rightEdge(lines[$0]) < rightEdge(lines[$1]) }) {
                lines[nearest].append(piece)
            } else {
                lines.append([piece])
            }
        }

        return lines.sorted { anchorTop($0) < anchorTop($1) }
    }

    /// 一串碎片拼成的一行。
    ///
    /// 文字按 `joinSeparator`（中中之间不加空格）接起来。盒子取**最左边那一段**的
    /// `top` 与 `height`，不取整行的外接矩形：倾斜会把外接矩形撑成
    /// `真行高 + |斜率| × 整行宽`（真机那张照片右栏满宽行是 0.058，真行高只有 0.019），
    /// 而 `startsNewParagraph` 的间距判据正是拿行高当基准的，撑出来的那一项会当场把它废掉。
    /// 最左那一段最短，被撑出来的那一项最小；更要紧的是**每行都取同一位置的那一段**，
    /// 行与行之间这才可比。
    static func mergedLine(_ fragments: [TextLine]) -> TextLine? {
        guard let first = fragments.first else { return nil }
        let text = fragments.dropFirst().reduce(first.text) {
            $0 + joinSeparator(after: $0, before: $1.text) + $1.text
        }
        return TextLine(text: text,
                        minX: first.minX,
                        top: first.top,
                        width: max(rightEdge(fragments) - first.minX, 0),
                        height: first.height)
    }

    /// 一行的**起笔端**的 `top`——就是最左边那一段的上边缘。行内已按 `minX` 排过，
    /// 所以是第一段。整行的纵向判据都用它，理由见 `visualLines`。
    private static func anchorTop(_ line: [TextLine]) -> Double {
        line.first?.top ?? 0
    }

    private static func rightEdge(_ line: [TextLine]) -> Double {
        line.map(\.maxX).max() ?? 0
    }

    /// `piece` 是不是紧接着 `line` 的末尾写的。见 `visualLines` 的推导。
    private static func continues(_ piece: TextLine, _ line: [TextLine]) -> Bool {
        guard let first = line.first else { return false }
        let gap = piece.minX - rightEdge(line)
        guard abs(gap) <= TextLayout.fragmentGapFraction else { return false }
        let overlap = min(piece.bottom, line.map(\.bottom).max() ?? 0)
            - max(piece.top, first.top)
        let shorter = min(piece.height, line.map(\.height).max() ?? 0)
        return overlap > shorter * TextLayout.fragmentOverlapFraction
    }

    // MARK: - 成段

    /// 一个阅读单元（一栏，或一条通栏行）之内的行 → 段落。
    ///
    /// 先**拼行**（`visualLines`），把 Vision 切碎的视觉行还原回整行，再判段。
    /// 顺序不能反：`startsNewParagraph` 的每一条判据（间距、缩进、短行、横向错开）
    /// 都以「这两行是上下相邻的两个视觉行」为前提，碎片不满足这个前提。
    static func paragraphsInBlock(_ lines: [TextLine]) -> [String] {
        let ordered = visualLines(in: lines).compactMap(mergedLine)
        guard !ordered.isEmpty else { return [] }

        let metrics = Metrics(of: ordered)
        var paragraphs: [String] = []
        var current = ordered[0].text

        for index in 1..<ordered.count {
            let upper = ordered[index - 1]
            let lower = ordered[index]
            if metrics.startsNewParagraph(upper: upper, lower: lower) {
                paragraphs.append(current)
                current = lower.text
            } else {
                current += joinSeparator(after: upper.text, before: lower.text) + lower.text
            }
        }
        paragraphs.append(current)
        return paragraphs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 接行时中间放什么。
    ///
    /// - 上一行以 `-` 结尾、下一行以小写字母开头：连字符断词，去掉连字符直接接。
    ///   **仅限拉丁文**，且下一行必须是小写开头——`Well-\nBeing` 这种真连字符要留住。
    ///   这条判断本身有歧义（`well-\nbeing` 与 `well-\nknown` 无法区分），取的是
    ///   排版上更常见的那一种。
    /// - 中文行尾接中文行首：**不加空格**。加了会在正文中间凭空多出空格，
    ///   朗读时停一下，正是要修的那类毛病。
    /// - 其余：加一个空格。
    static func joinSeparator(after upper: String, before lower: String) -> String {
        guard let last = upper.last, let first = lower.first else { return "" }
        if last == "-", first.isLowercase, !isCJK(first) { return "" }
        if isCJK(last) && isCJK(first) { return "" }
        return " "
    }

    // MARK: - 一页自己的统计量

    /// 判段依据全部取自**这一页自己的**统计量，没有任何跨页面的绝对值。
    struct Metrics {
        /// 相邻两行之间的正常**空白**（本页中位数）：上一行的 `bottom` 到下一行的 `top`。
        ///
        /// ⚠️ **只在盒子不互相穿插时才有意义**，所以用它的那条判据挂了 `normalGap > 0` 的闸。
        /// 斜页上一行的盒高是 `真行高 + |斜率| × 盒宽`（见 `visualLines`），行距小于盒高时
        /// 盒子就穿插，「空白」量出来是**负数**。真机那张照片右栏量到 **−0.019**——
        /// 那时候阈值被拉到比负间距还负的地方，**每一个正的间距都被判成段间距**，
        /// 实测把「…创有“绷」和「音”。余叔岩…」——同一段的两行——拆开了。
        ///
        /// 这条判据本身没写错，错的是拿它去量穿插的盒子：**两个盒子都不留缝的时候，
        /// 「缝有多宽」这个问题本身就不成立。** 那时候改用 `normalPitch`。
        let normalGap: Double

        /// 相邻两行之间的正常行距（本页中位数）：两个**盒中点**之差。
        ///
        /// 这是斜页上唯一站得住的纵向判据：它不掺盒高，所以盒子穿插与否都不影响。
        ///
        /// **中点，不是 `top`。** 这一条曾经用 `top` 之差，理由是「起笔端都落在栏的
        /// 左边界上，`top` 里的 `斜率 × minX` 是同一个常量」。**那句话是错的**——
        /// `top` 量的是**盒最高处**，而右倾的页面上最高处在**线的右端**，不在左端。
        /// 于是 `top` 之差里掺进 `|斜率| × 两端右端点的横向距离`，两行**宽度不一样**时
        /// 这一项不为零。真机那张照片上把这个式子算出来是 0.027，而那一栏的行距是 0.031
        /// ——**量出来的「行距」翻了一倍还多**，`startsNewParagraph` 第 1 条因此把
        /// 「……流派守正」和「创新的核心要义。」（同一段折出来的两行）判成了两段。
        ///
        /// 中点落在盒的**水平中点**上，横向位置的变化少一半（实测残差 0.014），
        /// 再被第 1 条那个随倾斜一起变大的 `行高` 项盖住，就够了。
        ///
        /// **代价**：字号不一致的页面（说明书那种「大标题 + 小正文」）里，行距本身随字号变，
        /// 拿行距当中位数就分不清「这一行字号大」和「这一行前面有空档」。所以这一条
        /// **不单独用**，它和 `normalGap` 那条并存——空白量得出来时以空白为准，
        /// 量不出来（穿插）时以这条为准。
        let normalPitch: Double
        /// 本页行高的中位数，用来量「间距比正常多出多少」。
        ///
        /// **不拿这一行自己的 `height` 当基准。** 拼行之后每行的盒子是**起笔端那一段
        /// 碎片**的盒子（`mergedLine`），斜页上它等于 `真行高 + |斜率| × 那一段的宽`
        /// ——一行里恰好只被切成一小段时，盒子就特别矮，阈值跟着塌到 `normalPitch` 上，
        /// 任何抖动都够触发。真机那张照片的右栏就是这么把一整段切成三段的：第 2 行
        /// （「时习之’，但到台上，我」）的盒子只有 **0.0160** 高，而本页中位高是
        /// **0.0445**，阈值于是从 0.041 掉到 0.031，而那一对的间距是 0.036——本来不该断。
        ///
        /// 取本页中位数，阈值就与「这一行恰好被切成一小段」无关了。这也正是这个文件里
        /// 「阈值全部是相对的」那一条该有的样子：基准是**本页**的，不是这一行的。
        let typicalHeight: Double
        /// 本页平均字宽，用来把「缩进」换算成「缩进几个字」。
        let characterWidth: Double
        /// 正文行的典型右边界，用来判断某一行是不是「短行」。
        let typicalRightEdge: Double

        init(of ordered: [TextLine]) {
            let gaps = (1..<ordered.count).map { ordered[$0].top - ordered[$0 - 1].bottom }
            normalGap = Metrics.median(gaps) ?? 0

            let pitches = (1..<ordered.count).map { ordered[$0].center - ordered[$0 - 1].center }
            normalPitch = Metrics.median(pitches) ?? 0

            typicalHeight = Metrics.median(ordered.map(\.height)) ?? 0

            let widths = ordered.map { line -> Double in
                let count = Double(max(line.text.count, 1))
                return line.width / count
            }
            characterWidth = Metrics.median(widths) ?? 0

            let rightEdges = ordered.map(\.maxX)
            typicalRightEdge = Metrics.median(rightEdges) ?? 0
        }

        /// 这段的起点是不是新的一段。
        ///
        /// 四条信号，**任一成立即断开**：
        ///
        /// 1. **间距明显大于正常行距**——段与段之间的空档，最直接的证据。
        /// 2. **首行缩进**——比本页左边界多缩进一个多字宽。
        /// 3. **上一行是短行、且这一行回到左边界**——上一行没写满就换行，说明那一段写完了。
        ///    居中标题也满足「短行」，但**不满足**「这一行回到左边界」，
        ///    所以标题不会被误判成段尾。
        /// 4. **横向完全不相交**——两行左右错开、一个字都不重叠，那它们不是上下相邻的两行。
        func startsNewParagraph(upper: TextLine, lower: TextLine) -> Bool {
            // **两条由远及近的信号，任一成立即断开。** 两条的超出量都拿**本页行高**
            // （`typicalHeight`）当基准，不拿间距当基数——`heightFactor` 那里记着为什么；
            // 也不拿**这一行自己的** `height`——`typicalHeight` 那里记着为什么。
            //
            // 1. **两行中点之间的距离明显大于本页正常行距。** 斜页上唯一站得住的纵向判据，
            //    不掺盒高，盒子穿插与否都成立。**代价是分不清「这一行字号大」和
            //    「这一行前面有空档」**，所以它只负责「明显偏离」这一档。
            //    用中点不用 `top`：`top` 落在倾斜盒子的右端，量的是「两端横向距离」而不是
            //    行距（推导与实测见 `normalPitch`）。
            // 2. **两行之间的空白明显大于本页正常空白。** 更贴近「段间距」的本义，
            //    但**要求 `normalGap > 0`**：盒子互相穿插时「缝有多宽」不成立
            //    （见 `normalGap` 的推导），拿负数当基准会把每个正间距都判成段间距。
            //
            // 分开写而不是合成一条，是因为两者的适用面是**互补**的：真机那张照片是两个
            // 极端——斜到盒子全穿插，只有第 1 条能用；`paracheck` 那张说明书的图是全正立，
            // 空白量得准，但标题字号比正文大、行距跟着大，只有第 2 条分得开
            // （实测段间距处的空档 0.039–0.043，普通行距 0.020–0.025，而两条的行距
            // 只差 0.010，第 1 条在那一页上判不出来）。
            let pitch = lower.center - upper.center
            if pitch > normalPitch + typicalHeight * TextLayout.heightFactor {
                return true
            }
            // 空白是**上一行的底边到这一行的上边**，两个量各自取自己的盒边，
            // 不能用 `pitch - upper.height` 去凑——`pitch` 现在量的是中点之差。
            let gap = lower.top - upper.bottom
            if normalGap > 0,
               gap > normalGap + typicalHeight * TextLayout.heightFactor {
                return true
            }

            let indent = lower.minX - upper.minX
            if characterWidth > 0, indent > characterWidth * TextLayout.indentCharacters {
                return true
            }

            if typicalRightEdge > 0,
               upper.maxX < typicalRightEdge * TextLayout.shortLineFraction,
               lower.minX <= upper.minX + characterWidth * TextLayout.indentCharacters {
                return true
            }

            // 同一条文字流里，相邻两行的横向区间总要重叠：行首落在同一个左边距上，
            // 行尾有长有短，短的落在长的里面。**一个字都不重叠的两行，不是上下相邻的
            // 两行**，它们只是碰巧被归进了同一块。
            //
            // 真机那张照片把对面那页的一列残字也拍了进来（「小」「只」「所」「清」，
            // x 在 0–2%），而本页正文从 8% 起。残字按底边排进左栏的行序，于是
            // 「流派的生成乃至传」后面直接接了一个「小」——**句子中间被塞进一个别页的
            // 字**。上面三条一条都拦不住它：它离上一行不远不近，既不缩进也算不上短行。
            //
            // **宁可多断一段，也不要把别处的字粘进句子里。** 多一段只是读起来顿一下，
            // 粘错字是把正文改掉了——两个方向的代价不对称，这条判据只朝安全的那边倒。
            if lower.minX > upper.maxX || lower.maxX < upper.minX {
                return true
            }

            return false
        }

        static func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let middle = sorted.count / 2
            if sorted.count % 2 == 1 { return sorted[middle] }
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
    }

    // MARK: - 字符判定

    /// 是不是「中日韩语境里的字符」。只看**接缝处那两个字符**，不看整行的语言——
    /// 中英混排的一行里，接缝在中英之间时，两边各该用哪个分隔符这里判得出来。
    ///
    /// **标点那几个区间是必需的，而且第一版漏了它们。** 当初只列了汉字和假名的区间，
    /// 于是 `，`（U+FF0C，全角形式区）和 `。`（U+3002，CJK 符号和标点区）**都不算 CJK**，
    /// 接缝落在句子边界上时就凭空插进一个空格：
    ///
    /// ```
    /// "口服。成人一次一片，" + "一日三次，饭后服用。"  →  "……一片， 一日三次……"
    /// ```
    ///
    /// 而 `。` 和 `，` 在真实中文里满地都是，所以这不是边角情况——中文正文每在句子边界处
    /// 折一次行就会中一次，朗读时还会在那里停顿。`layoutcheck` 里那条「折行的句子接成一段
    /// （中文不加空格）」就是钉它的。
    ///
    /// 判断方式取「按码位区间列举」而不是 `Unicode.Scalar.Properties.isIdeographic`：
    /// 后者只覆盖表意文字，**同样不含标点和假名**，会踩同一个坑。
    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x303F,     // CJK 符号和标点：。、「」『』〈〉《》〜 等
                 0x3040...0x309F,     // 平假名
                 0x30A0...0x30FF,     // 片假名
                 0x3400...0x4DBF,     // 扩展 A
                 0x4E00...0x9FFF,     // 基本区
                 0xA960...0xA97F,     // 谚文字母扩展 A
                 0xAC00...0xD7AF,     // 谚文音节
                 0xF900...0xFAFF,     // 兼容表意文字
                 0xFE10...0xFE1F,     // 竖排形式
                 0xFE30...0xFE4F,     // CJK 兼容形式
                 0xFF00...0xFFEF,     // 全角形式：，！？：；（）Ａ-Ｚ 等
                 0x20000...0x2FA1F:   // 扩展 B 及以后 + 兼容补充
                return true
            default:
                return false
            }
        }
    }

    // MARK: - 常数（全部相对，见文件头的「阈值全部是相对的」）

    /// 一条候选栏缝允许被多大比例的行跨过。
    ///
    /// 跨过栏缝的行是**通栏行**（居中的大标题），一两条很正常——真机报回来的那个
    /// 缺陷恰恰就是「有一条通栏行，于是真正的栏缝被整个否掉」。定 0.25：真实版面上
    /// 通栏行是少数，而单栏页面里任何一条内部空档都会被几乎所有行跨过，两者差得很远。
    static let columnCrossingFraction = 0.25

    /// 切开之后，两侧各自至少要占这个比例的行，才算「两栏」。
    ///
    /// 挡的是「一栏 + 一条短行」：参差的右边界会在栏内裂出假空档，而那种空档两侧是
    /// 「一行 vs 其余所有行」。真栏缝两侧都有成栏的正文。
    static let columnBalanceFraction = 0.2

    /// 一页最多认几栏。切过头说明这页不是分栏版式，那时保序比强行分栏安全。
    static let columnLimit = 4

    /// 两块竖直方向重叠超过**较矮那一块**的这个比例，就算并排的同一行。
    ///
    /// 并排两栏高度相当，重叠接近 100%；上下相邻的两块只重叠一点或干脆不重叠。
    /// 取 0.5 是两者之间：真机那张照片上区带里左右两栏几乎等高，比例接近 1.0，
    /// 而上下两块（比如标题与它下面的正文）重叠通常为 0。
    static let rowOverlapFraction = 0.5

    /// 同一视觉行的两段碎片，接续段的起点离上一段末尾最远这么多（横向，占整页宽的比例）。
    ///
    /// 一行的字是连着排的，横坐标上两段之间只隔着一个接缝，量级是**零**——真机那张照片
    /// 上八段碎片的接缝实测在 −0.0098 到 +0.0097 之间（负数=包围盒略微叠着）。
    /// 定 0.02 是**一个字的量级**（那张照片右栏字宽 0.018），留出识别把接缝撑开一点、
    /// 或原文里夹了一个空格（`用了“数音”， 创有` 这种）的余地。
    ///
    /// **上限卡的是换行**：一栏内换行后 `minX` 回到左边界，与上一行末尾差着大半个栏宽
    /// （那张照片上是 0.31），离 0.02 差一个数量级，所以这一条几乎不会误判。
    /// **下限卡的是「同一段文字不该左右叠着」**：横坐标上倒退超过一个字，说明这一段
    /// 不属于这一行，而是左边另一行伸过来的。
    static let fragmentGapFraction = 0.02

    /// 两段碎片竖直方向重叠超过**较矮那一段**的这个比例，才算同一视觉行。
    ///
    /// 与 `rowOverlapFraction` 同一个意思，只是量在**碎片**而不是块上，分开取是因为
    /// 两者的实测分布不同：同行的两段叠得很深（真机那张照片八段碎片实测 57%–116%），
    /// 取 0.4 给最浅的那一对（`音”` 对 `。`，57%）留出余量。
    ///
    /// **不能只靠这一条**：页面倾斜时满宽的相邻两行也叠到 69%，光看它会并错。
    /// 也不能只看横向：上一行是短行时会提前换行，末尾可能恰好落在下一行缩进后的起点旁。
    /// 两条一起才够，见 `visualLines`。
    static let fragmentOverlapFraction = 0.4

    /// 段间距要比正常行距**再多出「行高的这么多倍」**，才算段落断开。
    ///
    /// **基准是行高，不是 `normalGap`。** 这一条是改出来的，原来写的是
    /// `gap > normalGap + max(normalGap * 0.8, height * 0.35)`，那个 `max` 的后半句
    /// 不是兜底，是污染：`normalGap` 是行间**已有的**空白，它的大小由行距设置决定
    /// ——1.0 倍行距时它接近 0，2.0 倍行距时它约等于一个行高。拿它当基数，阈值的松紧
    /// 就跟着行距走，而且是**反的**：
    ///
    /// - 行距紧 → `normalGap` 趋近 0 → 阈值也趋近 0 → 任何一点抖动都判成段，
    ///   **折行的句子会被拆散**。这比漏判一个标题更糟：它毁掉的是真正的正文。
    /// - 行距松 → 阈值大得离谱 → 真正的段间距反而判不出来。
    ///
    /// 段间距的**超出量**该拿行高当基准：行高是排版里的稳定量，不随行距设置漂。
    /// 这个「行高」取的是**本页行高的中位数**（`Metrics.typicalHeight`），不是这一行
    /// 自己的盒子——理由见那里。
    ///
    /// 取 0.35 是**朝着不误拆的方向保守**。往下调会让它更灵敏，代价是上面第一条——
    /// 而两个方向的代价并不对称：漏判一个标题只是看起来差一点，误拆一段正文是错的。
    ///
    /// ⚠️ **这个数只在两张图上验过。** 一张是合成图（`paracheck` 的说明书图，实测
    /// 超出量约 0.61 个行高）。另一张是真机那张照片的**右栏**——那里每一对相邻行
    /// 都是同一段，倾斜项把中点顶出去最多 **0.0455**，而阈值是
    /// `0.0291 + 0.0577 × 0.35 = 0.0493`：**再小一点就会把「创新的核心要义。」拆出去**，
    /// 再大一点则「重新」那句真段间距就判不出来。0.35 正好落在能同时站住的窄缝里。
    /// 真实素材请用 `tools/ocr-bench` 的 `paracheck` 打出本页统计量再判，别直接改这个数——
    /// 本项目上一轮的置信度阈值就是在合成图上标的，真机行为与标定不符，返工了两轮。
    static let heightFactor = 0.35

    /// 缩进超过几个字宽算段首缩进。
    static let indentCharacters = 1.0

    /// 一行短到本页典型右边界这个比例以下，算「没写满」。
    static let shortLineFraction = 0.85
}
