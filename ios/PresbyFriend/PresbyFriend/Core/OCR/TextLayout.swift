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

    /// 盒的水平中点。矫正页面弯曲时要按它取该处的倾斜量（见 `SlopeField`）。
    var centerX: Double { minX + width / 2 }
}

/// 一条观测**自身**携带的倾斜样本。
///
/// `slope` 是**同一个观测内部**首字符盒中心到末字符盒中心那条连线的斜率，
/// 也就是这一行字在它自己那一段横向范围里的局部倾斜 `d(top)/d(x)`。
///
/// ## 它为什么比「猜哪两段属于同一行」可靠
///
/// 页面弯曲把**同一视觉行**在不同横坐标处顶到不同高度，于是「哪些碎片属于同一行」
/// 这件事本身就带上了歧义。实测那个歧义不是可以绕过的噪声，是**量级上的不可辨识**：
/// 页宽上的倾斜量约等于一个行距（`0.03 × 0.85 ≈ 0.026` 对行距 `0.023`），
/// 所以「整页切变一个行距」和「不切变」在包围盒的分布上几乎无法区分。按这个思路
/// 拟合斜率场，目标函数在三张真机照片里有两张**没有内部极大值**（剖面是孤立单点尖峰，
/// 相邻网格点差 5 倍），唯一能拿人工量值校准的那张差了 6 倍。
///
/// 本类型换掉的就是这一步：**不去猜谁和谁同行**，直接问每条观测「你自己斜多少」。
/// 首末字符盒是一条沿基线的序列，它的差是**有向**的，于是不需要配对、不需要行结构、
/// 不需要光滑性假设——歧义根本不进入。代价是短观测量不出来（`A. …` 这种），
/// 但那些恰好可以由拟合出来的场替它们补上。
///
/// `y` 与 `slope` 都在 `TextLine` 那套坐标里（归一化、y 向下为正），
/// 与 Vision 的翻转在 `TextRecognitionService` 一处做掉。
struct TiltSample: Equatable {
    /// 这条观测的竖直中点（`TextLine.center`）。
    let y: Double
    /// 这条观测自己的局部倾斜 `d(top)/d(x)`。
    let slope: Double
    /// 首末字符盒中心的横向跨度，即上面这个斜率的**分母**，用作拟合权重。
    let span: Double
}

/// 一页的页面弯曲，模型是 `s(y) = intercept + slope × (y − 0.5)`，y 向下为正。
///
/// 线性模型是量出来的，不是挑的：三张真机照片上加权最小二乘的 r² 是
/// **0.96 / 0.97 / 0.91**（IMG_0006 / IMG_0004 / IMG_0003），而同一批样本上
/// 分带中位斜率单调穿过零一次——正是一张纸被弯成弓形的样子，不是整体旋转。
///
/// 两处**人工裁图量出来的**值当独立校核（不是本模型自己算的）：
/// IMG_0004 页眉 `−0.018` → 本模型 `−0.020`；选项区 `≈+0.04` → 本模型 `+0.052`。
/// IMG_0006 页眉 `−0.047` → 本模型 `−0.050`。三处同向同量级。
///
/// **没做二次项**：加上它要拿 25–40 个带噪样本去定三个参数，而线性已经把 91–97%
/// 的方差解释掉了。IMG_0002 那页（r² = 0.20）分带中位在 ±0.13 之间乱跳，
/// **可能是它真的弯得超过线性、也可能是那页的字符盒在抖——这两种我没有分开**。
/// 线性模型下它会被下面的 r² 门直接跳过，安全方向。真出现「被跳过但这页确实排错了」
/// 的照片时再回来分辨，不要凭现在这点信息先加二阶项。
struct SlopeField: Equatable {
    /// 场在 `y = 0.5` 处的斜率。
    let intercept: Double
    /// 斜率随 y 的变化率。
    let slope: Double
    /// 加权拟合的决定系数，门控就是拿它判「这一页到底有没有可辨认的弯曲」。
    let r2: Double

    /// 横坐标为 `y` 处的页面倾斜 `d(top)/d(x)`。
    func slope(at y: Double) -> Double { intercept + slope * (y - 0.5) }
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

        // 先看有没有哪一侧**整条**都不是栏，而是一条页边残字——那一侧整条丢掉。
        //
        // **丢掉它不等于可以收工。** 这一支原先写完就 `return`，于是另一侧（通常是正文
        // 那一栏）自己贴页边的残字**一条都清不掉**——那是 `pageEdge` 的活，与另一侧
        // 是不是残条毫无关系。真机那张英语卷子（IMG_0004，右缘一列手写旁注）走的正是
        // 这条路：右缘被丢掉之后左栏原样返回。两件事并成一次删除，各自独立判。
        //
        // **这次改动在四张标定照片上是惰性的。** 前后跑 `paracheck`，段落逐条相同
        // （IMG_0002 10 段 / IMG_0003 15 段 / IMG_0004 44 段 / IMG_0006 40 段）。
        // IMG_0004 确实走进了新路径——左栏 46 行被送进 `pageEdge`——但那一侧没有它
        // 认得出的残字，于是删掉的是空集。也就是说这四张证明的是**不坏**，不是**有用**。
        // 要正面验证得造一张「一侧是残条、且另一侧自己也贴页边有残渣」的页。
        let sliverIndex = sliverSideIndex(sides)
        var dropped: [TextLine] = sliverIndex.map { sides[$0] } ?? []

        for (index, side) in sides.enumerated() where index != sliverIndex {
            // 只对**单栏**的一侧动手。那一侧要是自己还能切出栏来，说明它不是一条正文
            // 栏（可能是另一组并排的栏），「中位数 = 正文边缘」这句话就不成立了。
            guard verticalGutters(in: side).isEmpty else { continue }
            dropped.append(contentsOf: pageEdge(in: side))
        }
        guard !dropped.isEmpty else { return lines }
        return lines.filter { !dropped.contains($0) }
    }

    /// 两侧里是不是有一侧根本不是「栏」，而是**贴着页边的一条残字**。
    ///
    /// 两条判据**同时**成立才算，各自挡住对方的误判：
    ///
    /// 1. **横向跨度不到另一侧的一半。** 一条残字没有栏宽——真机那张英语卷子
    ///    （IMG_0004）右缘那列手写旁注占 0.059 的宽度，正文占 0.726，差 12 倍。
    ///    只有这一条的话，「一栏写满了、另一栏只剩几行」的正常分栏页会被误杀；
    /// 2. **行数也不到另一侧的一半。** 只有这一条的话，「一栏本来就只有几行」的页
    ///    会被误杀——报纸那种左栏写满、右栏只补几行的版式是常事。
    ///
    /// 两条合起来，加上「跨度不到一半」这一半，才是「它不是栏」。
    ///
    /// 实测三张真机照片（`sliverFraction` = 0.5）：
    ///
    /// | 照片 | 左跨度 / 右跨度 | 左行 / 右行 | 判定 |
    /// |---|---|---|---|
    /// | IMG_0002（真两栏） | 0.437 / 0.295 | 28 / 28 | 都不是（行数相当） |
    /// | IMG_0003（真两栏） | 0.317 / 0.465 | 25 / 26 | 都不是（行数相当） |
    /// | IMG_0004（正文 + 右缘旁注） | 0.726 / 0.059 | 46 / 15 | 右是残条 |
    ///
    /// IMG_0003 那一行说明**为什么非要两条同时**：它的左栏比右栏窄三分之一
    /// （0.317 对 0.465，比值 0.68），只比阈值 0.5 高一点点——单看跨度它险些被误杀，
    /// 是「行数相当」这一条把它保下来的。
    ///
    /// - Returns: 残条那一侧在 `sides` 里的下标；两侧都像栏、或某一侧是空的时候返回 nil。
    ///   返回**下标**而不是那一侧的行，是为了让调用方能说清楚「**除了**它以外的那一侧」
    ///   ——去掉残条之后，剩下那一侧还要接着做 `pageEdge`（见 `pageBody`）。
    private static func sliverSideIndex(_ sides: [[TextLine]]) -> Int? {
        guard sides.count == 2, !sides[0].isEmpty, !sides[1].isEmpty else { return nil }
        func extent(_ side: [TextLine]) -> Double {
            guard let lo = side.map(\.minX).min(), let hi = side.map(\.maxX).max() else { return 0 }
            return hi - lo
        }
        for (a, b) in [(1, 0), (0, 1)] {
            let narrow = extent(sides[a]) < extent(sides[b]) * sliverFraction
            let few = Double(sides[a].count) < Double(sides[b].count) * sliverFraction
            if narrow && few { return a }
        }
        return nil
    }

    /// 一侧（单栏）里的页边残字：**贴在这一侧最外面、和主体不相接的一小撮**。
    ///
    /// 判据是**结构**的，不是统计的：把这一侧的行按「横向空白」连成几团
    /// （`horizontalBlocks`），最外侧那一团只要不是最大的一团，它就是页边残字。
    /// 全相对，没有绝对坐标，也没有绝对宽度——与文件头那条一致。
    ///
    /// **为什么不是「中位数之外」**（原来是这个写法）：中位数只有当这一侧是
    /// 「一整栏、行行等宽」时才等于正文边缘。页面上行宽参差时它落在**页面中间**，
    /// 于是把正文的右半边整片当成页边残字。真机那张英语卷子（IMG_0004）就是这样：
    /// 上半页是通栏正文（x 0.10–0.90），下半页是**两栏的选择项**（x 0.11–0.48 与
    /// 0.50–0.80），左侧 46 行的中位右界因此落在 **0.448**——比正文右缘窄了一半。
    /// 结果表头那一行（词数 / 建议用时 / 实际用时 / 正确率 / 348 / 8 mins / mins / /4）
    /// 和两条选项（`B. He looks forward…` / `D. He is attached…`）**整行被当页边删掉**，
    /// 共 11 条真实内容。这不是放宽或收紧某个阈值能救的：**这一页没有任何一条缝
    /// 能救它**——换成那条真正的页边缝（0.909–0.944），左侧 60 行的中位右界是 0.494，
    /// 照样吃掉 9 条。行宽参差这件事本身就把中位数废掉了，所以换掉的是判据本身。
    ///
    /// 同一张照片上实测两种判据（`horizontalBlocks` 的相接判据就是同一行碎片之间
    /// 那条 `fragmentGapFraction`）：**现状丢 11 条 → 连通丢 0 条**；
    /// 而另两张上**逐个相同**——IMG_0002（真·对开页边）从左缘 0.000–0.021 的那一撮
    /// （小 / 只 / 所 / 清 / 小）丢 5 条，与中位判据一模一样；IMG_0003 两边都是 0 条。
    /// 也就是说改判据只在**中位判据犯错的那一页**上起作用，其余两页逐条不变。
    ///
    /// 只认**最外侧**那一团：中间被空白夹住的短行（表格单元、行内小注）不动。
    /// 上下两栏共用一个 x 区间是常事，中间那些孤立的团不是页边残字。
    ///
    /// **要删的条数达到这一侧的一半就整个放弃**这条硬闸门保留：删掉正文比漏掉几个
    /// 残字严重得多，宁可漏杀。
    static func pageEdge(in side: [TextLine]) -> [TextLine] {
        guard side.count > 2 else { return [] }

        let groups = horizontalBlocks(in: side)
        guard groups.count > 1, let largest = groups.max(by: { $0.count < $1.count }) else { return [] }

        // 最左那一行所在的团、最右那一行所在的团。两者可能是同一团（只有一团时上面
        // 已经返回了），`formUnion` 天然去重。
        var edge: Set<Int> = []
        for group in groups where group.count < largest.count {
            let leftmost = group.contains(side.indices.min { side[$0].minX < side[$1].minX }!)
            let rightmost = group.contains(side.indices.max { side[$0].maxX < side[$1].maxX }!)
            guard leftmost || rightmost else { continue }
            edge.formUnion(group)
        }

        guard edge.count * 2 < side.count else { return [] }
        return edge.sorted().map { side[$0] }
    }

    /// 把一组行按**横向相接关系**连成几团。
    ///
    /// 两行的横向区间只要隔着的空白小于 `fragmentGapFraction` 就算接上——同一个
    /// 判据在 `continues` 里用来判「这一块碎片是不是接着上一块的末尾」，含义一致：
    /// **小于这个空白的两块横向是连着的，大于它才是分家的**。
    ///
    /// 用 `top`/`height` 判纵向行距也行不通：那一侧本来就可能是上下两栏共用
    /// 一个 x 区间（就是本文档要修的那个情形），纵向判据会把本该分开的团连起来。
    private static func horizontalBlocks(in side: [TextLine]) -> [[Int]] {
        var parent = Array(side.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index { parent[index] = parent[parent[index]]; index = parent[index] }
            return index
        }
        for i in side.indices {
            for j in side.indices where j > i {
                let blank = max(side[i].minX, side[j].minX) - min(side[i].maxX, side[j].maxX)
                if blank < fragmentGapFraction {
                    let (a, b) = (root(i), root(j))
                    if a != b { parent[a] = b }
                }
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in side.indices { groups[root(i), default: []].append(i) }
        return Array(groups.values)
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
    /// 三道筛子依次筛：
    ///
    /// 1. **在页内**（左右两侧的留白不是栏缝）、**跨越它的行不能太多**
    ///    （`columnCrossingFraction`）——跨过栏缝的那几行是通栏行，一两条正常，
    ///    多到几十条就说明这条缝不是栏缝；
    /// 2. **两侧都要真的成栏**（`columnBalanceFraction`）。没有这一条，一栏里参差的
    ///    右边界会造出假空档（某行比别的行短一截），而那种空档两侧是「一行 vs 其余
    ///    所有行」，不是两栏。
    /// 3. **跨缝的行不能比少的那一侧还多**。第 1 条拿 `crossings` 和**全页行数**比，
    ///    那是个全页尺度的问题；这一条把它拉回**这条缝自己**的尺度。单栏页上第 1 条
    ///    必然放行（只有一栏可跨），只有这一条挡得住——详见下面 `divided` 处的实测。
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

            // 3. **跨越它的行，不能比它少的那一侧还多**。
            //
            //    前两道筛子都把 `crossings` 拿去和**全页行数**比（预算 25%），
            //    这在单栏页上答非所问：单栏页上任何一条空档都在横切那一栏，
            //    而「跨越它的行」就是这一栏的几乎全部行，于是这个数只反映
            //    「这条缝切在页面中间还是边上」，从不反映「它到底分没分开东西」。
            //    IMG_0004 那张单栏英文页上，排名第一的假缝 0.713–0.750 跨缝 18 行、
            //    少侧 17 行——**跨越的行比两侧任何一侧都多**，它分不出两堆来；
            //    而同一页上真正的页边缝（0.909–0.944，正文与手写旁注之间）
            //    跨缝 0 行。真栏缝的同一比值：IMG_0002 是 5/28 = 0.18，
            //    IMG_0003 是 7/25 = 0.28——中间空着 2.7 倍。这一条在 IMG_0004 上
            //    挡掉 22 条候选里的 7 条，其余两条照片上一条都没挡。
            //
            //    写成 `crossings < balance` 而不是再配一个比例系数：这句话本身
            //    就是判据的字面意思——「跨过这条缝的行比某一侧全部的行还多，
            //    那它不是缝，是一把横切整块的刀」。上限只有 1.0 这一个自然值。
            //
            //    **诚实记一笔：这三张照片上它不改变最终输出。** 因为同一轮把
            //    `pageEdge` 换成了结构判据，IMG_0004 那一页的 `pageBody` 现在
            //    一条都不删，缝选哪条都走到同一个「整页不动」上去——开/关这条
            //    筛子，三张照片的段落**逐字相同**。留它是当**防线**：缝选错的
            //    代价不止落在 `pageBody`，还落在 `blocks` 的递归切分与阅读顺序上
            //    （用户报过的「左右跳」就是这一类），而这三张恰好都不敏感。
            //    它是**定义**上的一票否决（跨缝比某一侧还多就不是缝），
            //    不是又一个照着某张图标定的比例，所以留着不违文件头那条纪律；
            //    若将来发现它碍事，删掉这三行即可，没有别处依赖它。
            let divided = Double(crossings) < Double(balance)
            guard divided else { continue }

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
    /// **行的纵向判据取「最左边那一段的 `top`」（`anchorTop`），这是整页倾斜下唯一
    /// 站得住的那个量。** 倾斜把 `top` 撑成 `行基线 + 斜率 × minX`（见 `readingOrder`），
    /// 横向位置不同的两段因此不可比；而**一栏里每行的最左段都落在同一个左边界上**，
    /// 横向位置相同，那一项是同一个常量，相减就抵掉了，量到的差就是真行距。用中点、
    /// 用 `bottom`、用外接矩形都会把这一项带进来，八段碎片上就是这么排错的。
    ///
    /// ⚠️ 这一条不是严格的：**段首缩进的行**最左段缩进了几个字，横向位置与别行差一个缩进，
    /// 于是 `top` 里带上 `斜率 × 缩进`。真机那张照片右栏斜率约 0.155、缩进约 0.036，
    /// 误差 0.006，是行距 0.024 的两成——**不足以让相邻两行换位**（相邻两行差一整个行距），
    /// 但别拿它去判「行距是否均匀」。
    ///
    /// ⚠️ **去斜之后这个量不够用了。** 它量的是「行的纵向位置」，而来的人需要的是
    /// 「谁在上面」；**并排的两格**（同一视觉行的左右半）在去斜后只差一个有符号的残差，
    /// 比大小就会反超。所以末尾那一排不再是「按 `anchorTop` 排一遍」，而是先成行、
    /// 行内按 `minX`——见 `orderedVertically`。**上面这一条讲的仍然是它作为行位置量的
    /// 性质**（去斜前后都成立），成行判据里也还在用它。
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

        return orderedVertically(lines)
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

    /// 视觉行的**成行与排序**：把同处一行的几段收成一行，行内按 `minX` 排。
    ///
    /// 分两步：先按 `anchorTop` 排一遍（必须是全序，理由与 `readingOrder` 那条相同，
    /// `sorted(by:)` 不保证稳定），再顺着这个顺序**连**——挨着的两条算不算同一行，
    /// 只看它俩，判据见 `sharesRow`。
    ///
    /// ## 为什么非要有「成行」这一步
    ///
    /// 去斜把同一视觉行各段挪到只差一个**有符号的残差**（IMG_0006 实测 0.003–0.012），
    /// 于是「比 `anchorTop` 大小」开始出错。实测（IMG_0006，去斜之后）：
    ///
    /// | 位置 | 只排序 | 成行之后 |
    /// |---|---|---|
    /// | 页眉 2×6 表头 | ❌ 文体/正确率/实际用时/题材/建议用时/词数 | ✅ 文体 题材 词数 建议用时 实际用时 正确率 |
    /// | Q1 / Q2 的 2×2 选项格 | ❌ B A D C | ✅ A B C D |
    ///
    /// 并排的两格本来就在同一行，**比较它们的 `top` 没有意义**——差的是残差，不是行距。
    ///
    /// ## 试过并否掉的判据（别再走一遍）
    ///
    /// | 判据 | 为什么不行 |
    /// |---|---|
    /// | 锚点差 ≤ 半个**本块行距** | 行距**估不出来**：一张满是选项格的卷子里近半的相邻对本来就在同一行（IMG_0006 实测 20 个相邻差里 8 个 ≤ 0.006），中位数被拽到 0.013 而真行距是 0.024。第 4 题那两格差 0.012 够不着；而全页夹具上两条**货真价实相邻**的行只差 0.0127——窗口是空的 |
    /// | 比 `center`（`top + 行高/2`） | `center` 要减掉行高的一半，而第 4 题那两格的**行高差**（0.0199 vs 0.0131 → 0.0034）比残差还大，右格照样反超 |
    /// | 横向错开 **+ 纵向有重叠** | 纵向那条太松，`layoutcheck` 的「别页残字」夹具当场出反例：「小」(x 0–2%) 与「正文第二行」(x 8%) 确实横向错开、纵向也叠（叠了 42%），被判成同一行 → 段落从「第一行+第二行 / 小 / 第三行」退化成「第一行 / 小 / 第二行+第三行」 |
    /// | 横向错开 + **要求整簇一致**（`allSatisfy`） | 表头 2×6 收不住：`词数` 与 `文体` 的 `top` 差 0.008，**超过矮盒高的一半**（0.0066），于是 `词数` 被挡在簇外（这一步是**算出来的，没跑**） |
    ///
    /// 前两条错在**尺度取自页面上的常量**（行距），第三条错在**只看纵向叠了多少**，
    /// 第四条错在**要求整簇一致**。活着的那条把尺度换成**两个盒子中较矮的那个的高度**、
    /// 把一致性换成**只看挨着的两条**，四个毛病一起没了。**半个盒高**这个数不是凑的，
    /// 三组实测在它两边分得很开——见 `sharesRow`。
    ///
    /// ⚠️ 换成「只看挨着的两条」是有代价的：这是**单链**，理论上可以用一串
    /// 各自都合法的步长从一行爬到另一行。挡着它的是半个盒高这个尺度本身够紧
    /// （实测该并的一对在 0.29，不该并的在 0.70 以上）。**真机上若再见到两行被连成一排，
    /// 先怀疑这里**——那时的修法是改成「同时与簇里最近的那几条都成立」，不是调这个分数。
    ///
    /// ## 还欠一步：去斜的出处没有跟着几何走
    ///
    /// `sharesRow` 第 2 条只在几何**已去斜**时才对得上；而**去斜现在住在上一层**
    /// （`TextRecognitionService.blocks(from:)`，因为算斜率场要逐**字符**的包围盒，
    /// `TextLine` 没有这个信息）。这一层拿到一组坐标时**无从知道**它是去斜过的还是
    /// 原样的。现在能跑是因为第 1 条（横向错开）在两种情形下都成立，
    /// 没去斜的页面靠它也不会错（`layoutcheck` 那批夹具就是没去斜的）。
    /// 真要让这一层知道，得让去斜的出处跟着 `TextLine` 一起下来。
    ///
    /// ## 为什么去斜的残差不归零（别再试「把场拟合得更准」）
    ///
    /// 去斜是**线性**的，而表头那一行去斜后的锚点是
    /// `0.0780 0.0810 0.0860 0.0840 0.0810 0.0780`——关于 x≈0.52 对称的**抛物线**，
    /// 幅度 0.008，中间最低、两端最高。纯切变的场**在数学上表示不出来**：
    /// 切变的残差必须正比于 `|x−0.5|`（中间最小、两端最大），而实测正相反。
    /// 要消掉它得给场加二次项，那是另一件事。
    private static func orderedVertically(_ lines: [[TextLine]]) -> [[TextLine]] {
        guard lines.count > 1 else { return lines }
        // 先排一遍：下面按顺序扫，起点必须是全序（理由与 `readingOrder` 那条相同，
        // `sorted(by:)` 不保证稳定）。
        let ordered = lines.sorted { a, b in
            let topA = anchorTop(a)
            let topB = anchorTop(b)
            if topA != topB { return topA < topB }
            return (a.first?.minX ?? 0) < (b.first?.minX ?? 0)
        }

        // 再顺着这个顺序**连**：挨着的两条算不算同一行，只看它俩（不看整簇）。
        // 判据见 `sharesRow`。
        var rows: [[[TextLine]]] = [[ordered[0]]]
        for line in ordered.dropFirst() {
            if let previous = rows[rows.count - 1].last, sharesRow(previous, line) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { row in
            row.sorted { ($0.first?.minX ?? 0) < ($1.first?.minX ?? 0) }
        }
    }

    /// 挨着的两条是不是**同处一个视觉行**。两条判据，缺一不可：
    ///
    /// 1. **横向完全错开**（端点相接算错开）——并排的两格横向不相交；上下相邻的行
    ///    **必然**相交，因为一栏里每行都从同一个左边界起笔。这条把「上下相邻」
    ///    整个排除掉，所以它不需要任何行距阈值，在**没去斜**的页面上照样成立。
    /// 2. **纵向重叠够多**——两条的盒子在竖直方向叠着的部分，至少要到**矮的那条**
    ///    的盒高的 `rowOverlapFraction`（一半）。并排的两格本来就在一行，盒子叠着
    ///    大半；上下相邻的两行只叠着边角，或者干脆一点都不叠。
    ///
    /// **第 2 条为什么量「重叠」而不是「`top` 差」**：*没去斜*的页面上这两种写法
    /// 几乎等价——同一行两格的 `top` 本来就一样。*去斜之后*就不是了：去斜把同一
    /// 视觉行各段拉到只差一个**有符号的残差**（见 `orderedVertically` 上面那段），
    /// 谁高谁低看的是残差的符号，跟「是不是同一行」没有关系。旧判据比 `top` 大小，
    /// 于是在第 4 题把 `D. Conservative.`（`top` 0.895）排到了 `C. Tolerant.`
    /// （0.907）**前面**——那两条的 `top` 差 0.012，矮的那条高 0.0131，比值
    /// **0.92**，离 0.5 的线只剩两成；同一处并排的还有 Q1、Q2 两格，一起从
    /// A B C D 变成 B A D C。换成量重叠，这几对都叠着六成以上，稳稳站在同一侧。
    ///
    /// **判据的尺度是盒子自己的高度，不是页面上的常量**，所以换个字号、换个分辨率
    /// 都不用重标。
    ///
    /// **为什么是一半**（IMG_0006 实测，纵向重叠 ÷ 较矮盒高）：
    ///
    /// | 一对 | 比值 | 该不该并 |
    /// |---|---|---|
    /// | 四个选项格里并排的每一项（最低是第 4 题的 `D.`/`C.`） | 0.60–1.00 | 该并 |
    /// | `layoutcheck` 的「别页残字」：`小`/`正文第二行` | 0.30 | 不该并 |
    /// | 第 2 题 `D.`/第 3 题题干（夹具 `optionGridThenNextStem`） | 0.15 | 不该并 |
    ///
    /// 该并的那一列都在 0.60 以上，不该并的两处都在 0.30 以下，中间空着一段；
    /// **半（0.5）落在里面，而且偏向「不该并」那侧**——粘错一行的代价是其中一条被
    /// 搬到另一条旁边去（第 4 题就是这么错的），比漏并更显眼，所以余量留给这一侧。
    private static func sharesRow(_ a: [TextLine], _ b: [TextLine]) -> Bool {
        guard let aLeft = a.map(\.minX).min(), let aRight = a.map(\.maxX).max(),
              let bLeft = b.map(\.minX).min(), let bRight = b.map(\.maxX).max(),
              let aTop = a.map(\.top).min(), let aHeight = a.map(\.height).max(),
              let bTop = b.map(\.top).min(), let bHeight = b.map(\.height).max() else { return false }
        guard aLeft >= bRight || bLeft >= aRight else { return false }
        let overlap = min(aTop + aHeight, bTop + bHeight) - max(aTop, bTop)
        return overlap >= min(aHeight, bHeight) * rowOverlapFraction
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

            // **取高分位，不取中位数。** 这个量要回答的是「一行写满能写到哪」，
            // 也就是**本块正文的右边界**——那是被**最长的那些行**定义的，不是被
            // 一半的行定义的。用中位数要求「过半的行都是满宽行」，而正常正文里
            // 段末行、标题行、表格行天生就短，过半根本达不到。
            //
            // 真机那张英语卷子（IMG_0004）上这条判据整个失灵：整页塌成一块之后，
            // 60 行里只有十几行是满宽，`maxX` 的中位数掉到 **0.492**（真右边界 0.909），
            // 「上一行是短行」的阈值跟着掉到 0.418，于是第 4 题的四个选项
            // （右端 0.458 / 0.474 / 0.505 / 0.575）一个都够不着，被并成了一段。
            // 同一块上 0.8 分位是 **0.890**，阈值回到 0.757，四个选项全部断开。
            //
            // **换分位几乎不影响同质的块**，因为那里中位数本来就在最高一档附近——
            // 另外两张照片上逐块实测：IMG_0002 17 行的块 0.849→0.857（其余各块相等），
            // IMG_0003 23 行的块 0.388→0.390、24 行的块 0.890→0.892。差的是
            // **混杂的块**，而那正是旧算法错的地方。
            let rightEdges = ordered.map(\.maxX).sorted()
            typicalRightEdge = rightEdges.isEmpty ? 0 : rightEdges[
                min(rightEdges.count - 1,
                    Int(Double(rightEdges.count - 1) * TextLayout.rightEdgeQuantile))
            ]
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
        /// 4. **横向叠得不够**——两条的重叠不到窄的那条的一半，那它们不是上下相邻的两行
        ///    （并排的两格、别页的残字都落在这条上）。
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
            // 行尾有长有短，短的落在长的里面。**叠得不够窄的那一条的一半，就不是
            // 上下相邻的两行**，它们只是碰巧被归进了同一块。
            //
            // 真机那张照片把对面那页的一列残字也拍了进来（「小」「只」「所」「清」，
            // x 在 0–2%），而本页正文从 8% 起。残字按底边排进左栏的行序，于是
            // 「流派的生成乃至传」后面直接接了一个「小」——**句子中间被塞进一个别页的
            // 字**。上面三条一条都拦不住它：它离上一行不远不近，既不缩进也算不上短行。
            // 那一对的重叠是 **0**。
            //
            // ⚠️ **原来是「一个字都不许叠」**（`lower.minX > upper.maxX || lower.maxX < upper.minX`）。
            // 那条太紧：一栏里的续行只要起笔不比上一行靠左、两条横向总要叠着，可是
            // **上下相邻的另一样东西——同一行里并排的两格——也不完全错开**。IMG_0006 的
            // 2×2 选项格上，第 2 题的 `D`（x 0.544–0.864）下面接着第 3 题的题干
            // （x 0.116–0.626），两条叠着 0.082，正好占矮的那条（0.320）的 **26%**——
            // 于是「一个字都不许叠」放行，`D` 就粘在了下一题题干的**前面**
            // （用户报的「有的答案 d 并到下一题 a 之前」就是这个）。26% 与 0 之间空着一大段：
            // **同一栏的续行在 90% 以上**（行首同左边距，短的落在长的里面），
            // 别页残字是 0。0.5 落在中间，两边各留 1.8 倍以上的余量。
            //
            // 尺度取**两条里窄的那条**，不是页面上的常量——换字号、换分辨率都不用重标。
            // 与纵向那条（`rowOverlapFraction`）是同一个形状的判据，只是换了根轴。
            //
            // **宁可多断一段，也不要把别处的字粘进句子里。** 多一段只是读起来顿一下，
            // 粘错字是把正文改掉了——两个方向的代价不对称，这条判据只朝安全的那边倒。
            let narrower = min(upper.width, lower.width)
            if narrower > 0 {
                let overlap = min(upper.maxX, lower.maxX) - max(upper.minX, lower.minX)
                if overlap < narrower * TextLayout.lineOverlapFraction { return true }
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
    /// **第二版又漏了通用标点区（U+2010–U+201F 那一档）**，同一个坑换个位置再踩一次：
    /// 中文排版里的引号和破折号用的是**弯引号**（`‘’“”`，U+2018–U+201D）和 `—`（U+2014），
    /// 它们都在通用标点区，不在任何 CJK 区间里。真机那张照片上就中了两处——
    /// 「必须‘学而时习之’」折到「，但到台上……」，接缝落在 `’` 和 `，` 之间；
    /// 「承续」折到「“云避月”的嗓音……」，接缝落在 `续` 和 `“` 之间。两处都多出一个空格。
    ///
    /// 这两档一并收进来**对英文也是对的**：`don’t` 的弯撇号、`word—known` 的破折号，
    /// 原本也都会被插一个空格（`don ’t`、`word— known`）。
    ///
    /// 判断方式取「按码位区间列举」而不是 `Unicode.Scalar.Properties.isIdeographic`：
    /// 后者只覆盖表意文字，**同样不含标点和假名**，会踩同一个坑。
    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2010...0x201F,     // 通用标点：— – ‘’“” 等
                 0x2026...0x2027,     // … ‥
                 0x2039...0x203A,     // ‹ ›
                 0x3000...0x303F,     // CJK 符号和标点：。、「」『』〈〉《》〜 等
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

    // MARK: - 页面弯曲（斜率场的拟合与去斜）

    /// 由逐观测的倾斜样本拟合这一页的斜率场。
    ///
    /// 按 `span` 加权：分母越大，那个斜率越准（噪声按 `1/span` 放大），
    /// 所以一条横跨大半页的正文行该比一段 `C. …` 更算数——虽然短的那些根本进不来
    /// （见 `minimumTiltSpan`）。
    ///
    /// **返回 `nil` 是一等结果，不是失败。** 它表示「这一页没有可辨认的弯曲」，
    /// 调用方必须原样放行、一个像素都不动。IMG_0002 就是这样：40 条样本、r² = 0.20。
    /// 宁可不动，也不能拿一个错的场去改一页本来读对了的纸。
    static func slopeField(samples: [TiltSample]) -> SlopeField? {
        guard samples.count >= minimumTiltSamples else { return nil }

        let weight = samples.reduce(0.0) { $0 + $1.span }
        guard weight > 0 else { return nil }

        let meanY = samples.reduce(0.0) { $0 + $1.span * ($1.y - 0.5) } / weight
        let meanSlope = samples.reduce(0.0) { $0 + $1.span * $1.slope } / weight

        var covariance = 0.0
        var variance = 0.0
        for sample in samples {
            let dy = sample.y - 0.5 - meanY
            covariance += sample.span * dy * (sample.slope - meanSlope)
            variance += sample.span * dy * dy
        }
        guard variance > 0 else { return nil }

        let slope = covariance / variance
        let intercept = meanSlope - slope * meanY

        var residual = 0.0
        var total = 0.0
        for sample in samples {
            let predicted = intercept + slope * (sample.y - 0.5)
            residual += sample.span * (sample.slope - predicted) * (sample.slope - predicted)
            total += sample.span * (sample.slope - meanSlope) * (sample.slope - meanSlope)
        }
        guard total > 0 else { return nil }

        let r2 = 1 - residual / total
        guard r2 >= minimumTiltR2 else { return nil }

        // 哨兵，不是标定：接近 90° 的「页面」不是照片。实测三张真机照片拟合出来的
        // 场都没超过 0.09 的绝对值（MAX 在 y 两端取到），0.5 离它们有 5 倍余量，
        // 所以它挡的只可能是数值上跑飞的结果，挡不到任何真照片。
        let extreme = max(abs(intercept + slope * 0.5), abs(intercept - slope * 0.5))
        guard extreme <= maximumTiltSlope else { return nil }

        return SlopeField(intercept: intercept, slope: slope, r2: r2)
    }

    /// 把一条观测按它所在处的斜率场做**竖直平移**，使同一视觉行的各段落到同一高度。
    ///
    /// 平移量是 `−s(y) × (该段的横向中点 − referenceX)`：场的截距定在 `y = 0.5`，
    /// 所以横向基准也取页心，两者是同一个参照点。
    ///
    /// **只平移，不旋转**——观测盒的竖直中点等于真盒的中点（旋转下不变），
    /// 所以把中点搬到同一高度就等于把整行对齐了。`top` 与 `bottom` 同移，
    /// `height` 分毫不动，下游 `mergedLine` 取最左段盒高的那套约定因此不受影响。
    ///
    /// 短观测（`A. …` 这种量不出自己斜率的）同样要过这一道：它们自己不带倾斜样本，
    /// 但它们**坐在同一张斜着的纸上**，正是靠这一步跟上同伴。
    static func deskewed(_ line: TextLine, by field: SlopeField, referenceX: Double) -> TextLine {
        let shift = -field.slope(at: line.center) * (line.centerX - referenceX)
        return TextLine(text: line.text, minX: line.minX, top: line.top + shift,
                        width: line.width, height: line.height)
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

    /// 判「短行」时，「本块正文的右边界」取 `maxX` 的第几分位。
    ///
    /// 不用中位数：这个量是由**最长的那些行**定义的，不是由一半的行定义的。
    /// 实测与推导见 `Metrics.init(of:)` 里 `typicalRightEdge` 那一大段。
    static let rightEdgeQuantile = 0.8

    /// 一侧的**跨度**和**行数**都不到另一侧的这个比例时，它不是栏，是页边的一条残字。
    ///
    /// 两条要同时成立，理由和实测见 `sliverSideIndex`：单独任何一条都会误杀一种正常版式
    /// （窄栏 / 短栏）。三张真机照片上，残条是 0.08 和 0.25，真栏是 0.68 和 0.96——
    /// 0.5 落在中间，两侧各留 1.9 倍和 2 倍的余量。
    static let sliverFraction = 0.5

    /// 两块竖直方向重叠超过**较矮那一块**的这个比例，就算并排的同一行。
    ///
    /// 并排两栏高度相当，重叠接近 100%；上下相邻的两块只重叠一点或干脆不重叠。
    /// 取 0.5 是两者之间：真机那张照片上区带里左右两栏几乎等高，比例接近 1.0，
    /// 而上下两块（比如标题与它下面的正文）重叠通常为 0。
    static let rowOverlapFraction = 0.5

    /// **横向**的同一件事：上下相邻的两行之间，横向重叠不到**窄的那条**的这个比例，
    /// 就算不上相邻的两行。
    ///
    /// 形状与 `rowOverlapFraction` 一样，只是换了根轴（那边量并排，这边量上下）。
    /// 尺度同样取两条里窄的那条。取 0.5 的理由与三组实测见 `startsNewParagraph` 第 4 条。
    static let lineOverlapFraction = 0.5

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

    // MARK: 页面弯曲

    /// 拟合斜率场至少要几条样本。
    ///
    /// 三张真机照片上真正进到拟合里的样本是 25 / 30 / 37 条，8 离它们很远；
    /// 这个下限挡的是「样本太少、随便一条噪声都能凑出一条高 r² 的直线」。
    static let minimumTiltSamples = 8

    /// 拟合的决定系数低于这个值，就判「这页没有可辨认的弯曲」，整页不矫正。
    ///
    /// 三张真机照片实测 **0.96 / 0.97 / 0.91**，而唯一拟合不成立的那页是 **0.20**。
    /// 0.60 落在中间，两侧各留 0.3 以上的余量——它分的是「有弯曲」和「没有」，
    /// 不是在两个都成立的模型之间挑一个。
    static let minimumTiltR2 = 0.6

    /// 量一条观测自身的倾斜至少要这么多个字符。
    ///
    /// 太短的串（单个字、页码）在 Vision 那边可能首末字符盒落在同一个字上。
    static let minimumTiltCharacters = 6

    /// 首末字符盒中心的横向跨度至少要这么大，才拿它们的中心差算斜率。
    ///
    /// **这个数是被噪声定出来的**：斜率的误差按 `1/跨度` 放大，而字符盒中心的抖动
    /// 实测在 0.002 的量级，跨度 0.15 对应斜率噪声约 0.013——与真实弯曲（0.03–0.07）
    /// 同量级已经偏大，再小就淹掉了。实测放宽到 0.05 时会放进斜率 −0.13 … +0.13
    /// 的散点，把 r² 从 0.96 拉到 0.2 以下。
    static let minimumTiltSpan = 0.15

    /// 首末字符盒中心 y 之差小于这个值，判为**没量到**，不是「这一行不倾斜」。
    ///
    /// Vision 有两种退化：首末返回同一个盒，或者干脆沿**水平线**而不是沿基线切片
    /// （两个盒 x 不同、y 完全相同）。两种的 `Δy` 都精确为 0，而真实的零倾斜是
    /// 测度为零的事件。实测不滤掉它们会把场往平里拽：IMG_0006 的 57 条里有 9 条、
    /// IMG_0003 的 57 条里有 **25 条** 是这一种——后者让 r² 从 0.91 掉到 0.77。
    static let tiltDegenerateEpsilon = 1e-9

    /// 去斜只竖直平移，这里定横向基准点。与斜率场的截距（定在 `y = 0.5`）是同一个参照。
    static let deskewReferenceX = 0.5

    /// 拟合出来的场在页面两端的绝对值上限。**哨兵，不是标定**——只挡数值跑飞，
    /// 详见 `slopeField(samples:)`。
    static let maximumTiltSlope = 0.5
}
