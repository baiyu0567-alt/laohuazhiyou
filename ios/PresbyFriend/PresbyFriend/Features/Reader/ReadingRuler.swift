import SwiftUI

/// 阅读标尺：横贯一条浅色带，压在**正在读的那一行**下面。
///
/// 六语言的文案（`ruler_description`）说的都是同一件事——「高亮**手指底下**那一行」。
/// 也就是说带子的位置是**用户拖出来的**，而它此前做不到：
///
/// - `yPosition` 是个**没有任何写入者**的 `@Binding`（`ReadingRuler` 自己也没有手势）；
/// - 带子锚在 `ZStack(alignment: .bottom)` 的**底边**，喂进去的却是「滚动内容顶边的
///   全局 Y」（`ReaderView` 里那个 `GeometryReader` 量出来的）。
///
/// 两个错叠在一起，带子的实际落点是「屏幕底边 + 内容顶边的全局 Y」，恒在屏幕外约一屏，
/// 只有把内容滚过一整屏之后才会从下边缘冒出来——功能等于不存在。
///
/// **手势只挂在带子自己身上，不铺满全屏。** 这一层压在 `ScrollView` 上面，铺满全屏的
/// 纵向手势会把滚动的拖拽整个吃掉。Android 那版正是 `fillMaxSize()` + 全屏手势
/// （`ReadingRuler.kt:22-29`），标尺一开就没法用拖拽滚动正文——那是那边的缺陷，不照抄。
///
/// 位置**锚在阅读区顶边**往下 `yPosition`，与 Android 的 `offset(y = rulerY.dp)` 同义。
struct ReadingRuler: View {
    @Binding var yPosition: CGFloat
    /// 带子高度 = 一个行距再宽两成。跟着阅读字号/行高走——这两个数都是用户自己调的，
    /// 写死一个 60 意味着「字号调到最大时带子只盖住半行」。与 Android 的
    /// `ReadingRulerOverlay(lineHeight = fontSize * lineHeight)` 同式。
    let lineHeight: CGFloat
    /// 可拖范围的上限（阅读区高度，由外层量出来传进来）。
    ///
    /// Android 不设上限（只 `coerceAtLeast(0f)`），因为那边手势铺满全屏，带子被拖出
    /// 屏幕之后随便在哪一拖就能拖回来。这里手势只在带子上，**拖出去就再也抓不到了**，
    /// 所以上限必须有。
    let maxY: CGFloat
    /// 带子的颜色。取**阅读主题**的强调色（`ReadingTheme.accentColor`），与 Android
    /// 一致；用 App 全局的 `Color.accentColor` 在深色阅读页上会偏色。
    let accent: Color

    /// 一次拖动开始时的位置。
    ///
    /// `DragGesture` 给的是**相对本次手势起点**的位移。没有这个起点，就只能把位移累加到
    /// **已经被改过**的 `yPosition` 上——手一直不抬，每一帧都在上一帧的结果上再加一次，
    /// 带子会越拖越快。
    @State private var dragOrigin: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(accent.opacity(0.12))
            .frame(maxWidth: .infinity)
            .frame(height: lineHeight)
            .offset(y: clamped(yPosition))
            // `RoundedRectangle` 是填充图形，本来就吃命中测试；写这一句是为了将来换了
            // 外形（描边、挖空）之后「拖不动」不会变成一个查不出来的回归。
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let origin = dragOrigin ?? yPosition
                        if dragOrigin == nil { dragOrigin = origin }
                        yPosition = clamped(origin + value.translation.height)
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
            .accessibilityLabel(L10n.readingRuler)
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), max(maxY - lineHeight, 0))
    }
}
