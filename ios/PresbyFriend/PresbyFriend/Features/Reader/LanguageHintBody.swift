import Foundation

/// 「识别语言可能选错了」这条提示的正文。
///
/// **为什么是单独一个文件名。** 这条提示有两张卡片：`ReaderView` 里画在阅读主题底色上的
/// 那一张，和 `PresbyFriendApp` 里画在照片上的那一张（识别没拿到文字、退回显示原图时用）。
/// 两张卡片的**版式**确实必须分开——一份用主题正文色的淡色，一份必须用材质才在任意照片上
/// 读得清——但**说的话是同一句**。
///
/// 正文曾经在两边各写一份，`LanguageHint` 从「一个平铺的 `systemCode`」改成
/// 「两种理由的枚举」时，只改到了 `ReaderView` 那一份，另一份继续读一个已经不存在的属性。
/// **这不是猜的，是编译器报的**（`PresbyFriendApp.swift` → `value of type 'LanguageHint'
/// has no member 'systemCode'`）。当时若能编过，用户看到哪句话就取决于这次识别有没有
/// 认出文字——同一件事，两个说法。
///
/// 放在视图层而不是做成 `LanguageHint` 的属性：那个类型住在协调器里，它刻意不碰 `L10n`
/// （见文件头「文案属于视图层」）。文案是视图层的事，所以留在视图层，只是不再留两份。
func languageHintBody(_ hint: LanguageHint) -> String {
    let used = RecognitionLanguage.displayName(for: hint.usedCode)
    switch hint.reason {
    case .differsFromSystem(let systemCode):
        // 第二个名字是**设备语言**：说的是「你的设置相对系统语言」。
        return String(format: L10n.ocrHintLanguageBody,
                      used, RecognitionLanguage.displayName(for: systemCode))
    case .textLooksLike(let suggestedCode):
        // 第二个名字是**建议改用的那一档**：说的是「这段文字本身像什么」。
        // 顶替不得——`.textLooksLike` 的场合用户根本没有「偏离系统语言」这回事，
        // 用上面那条会说成假话。
        return String(format: L10n.ocrHintLanguageLooksLike,
                      used, RecognitionLanguage.displayName(for: suggestedCode))
    }
}
