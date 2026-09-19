import Foundation

/// Type-safe access to localized strings. All properties are computed so they
/// reflect the current language set by LanguageManager in real time.
enum L10n {
    static var appName: String { NSLocalizedString("app_name", comment: "") }
    static var appSubtitle: String { NSLocalizedString("app_subtitle", comment: "") }
    static var magnifierTab: String { NSLocalizedString("magnifier_tab", comment: "") }
    static var settingsTab: String { NSLocalizedString("settings_tab", comment: "") }
    static var zoomLabel: String { NSLocalizedString("zoom_label", comment: "") }
    static var flashlight: String { NSLocalizedString("flashlight", comment: "") }
    static var cameraError: String { NSLocalizedString("camera_error", comment: "") }
    static var readingMode: String { NSLocalizedString("reading_mode", comment: "") }
    static var fontSize: String { NSLocalizedString("font_size", comment: "") }
    static var themeLabel: String { NSLocalizedString("theme_label", comment: "") }
    static var themeWhite: String { NSLocalizedString("theme_white", comment: "") }
    static var themeSepia: String { NSLocalizedString("theme_sepia", comment: "") }
    static var themeDark: String { NSLocalizedString("theme_dark", comment: "") }
    static var themeYellow: String { NSLocalizedString("theme_yellow", comment: "") }
    static var lineHeight: String { NSLocalizedString("line_height", comment: "") }
    static var letterSpacing: String { NSLocalizedString("letter_spacing", comment: "") }
    static var readAloud: String { NSLocalizedString("read_aloud", comment: "") }
    static var stopReading: String { NSLocalizedString("stop_reading", comment: "") }
    static var readingRuler: String { NSLocalizedString("reading_ruler", comment: "") }
    static var rulerDescription: String { NSLocalizedString("ruler_description", comment: "") }
    static var loadingUrl: String { NSLocalizedString("loading_url", comment: "") }
    static var urlExtractFail: String { NSLocalizedString("url_extract_fail", comment: "") }
    static var defaultFont: String { NSLocalizedString("default_font", comment: "") }
    static var defaultTheme: String { NSLocalizedString("default_theme", comment: "") }
    static var languageLabel: String { NSLocalizedString("language_label", comment: "") }
    static var dataManagement: String { NSLocalizedString("data_management", comment: "") }
    static var resetSettings: String { NSLocalizedString("reset_settings", comment: "") }
    static var resetConfirm: String { NSLocalizedString("reset_confirm", comment: "") }
    static var versionFooter: String { NSLocalizedString("version_footer", comment: "") }
    static var proFeature: String { NSLocalizedString("pro_feature", comment: "") }
    static var freeLimitReached: String { NSLocalizedString("free_limit_reached", comment: "") }
    static var upgradePro: String { NSLocalizedString("upgrade_pro", comment: "") }
    static var proMonthly: String { NSLocalizedString("pro_monthly", comment: "") }
    static var proMonthlyDesc: String { NSLocalizedString("pro_monthly_desc", comment: "") }
    static var proMonthlyPrice: String { NSLocalizedString("pro_monthly_price", comment: "") }
    static var proYearly: String { NSLocalizedString("pro_yearly", comment: "") }
    static var proYearlyDesc: String { NSLocalizedString("pro_yearly_desc", comment: "") }
    static var proYearlyPrice: String { NSLocalizedString("pro_yearly_price", comment: "") }
    static var restorePurchases: String { NSLocalizedString("restore_purchases", comment: "") }
    static var restoreSuccess: String { NSLocalizedString("restore_success", comment: "") }
    static var restoreNoPurchases: String { NSLocalizedString("restore_no_purchases", comment: "") }
    static var playStoreComing: String { NSLocalizedString("play_store_coming", comment: "") }
    /// 购买或恢复**失败**的提示。
    ///
    /// 存在的理由：不能把 `error.localizedDescription` 直接上屏——那是系统英文原文
    /// （`The operation couldn't be completed. (StoreKit.StoreKitError error 2.)`），
    /// 在一个只有 6 种语言的 App 里，用户看到的就是一行乱码。原文送日志，屏上留这句。
    static var storeError: String { NSLocalizedString("store_error", comment: "") }
    /// 交易处于 `.pending`（Ask to Buy 等家人批准）。**不是失败，也不是成功**——
    /// 说「已解锁」是假的（此刻 `currentEntitlements` 里没有它），一句不说又像卡住了。
    static var purchasePending: String { NSLocalizedString("purchase_pending", comment: "") }
    static var close: String { NSLocalizedString("close", comment: "") }
    static var noSharedContent: String { NSLocalizedString("no_shared_content", comment: "") }
    static var showControls: String { NSLocalizedString("show_controls", comment: "") }
    static var cameraPermissionRequired: String { NSLocalizedString("camera_permission_required", comment: "") }
    static var enableAccessibility: String { NSLocalizedString("enable_accessibility", comment: "") }
    static var accessibilityHint: String { NSLocalizedString("accessibility_hint", comment: "") }
    static var accessibilityHintBody: String { NSLocalizedString("accessibility_hint_body", comment: "") }
    static var accessibilityHintTitle: String { NSLocalizedString("accessibility_hint_title", comment: "") }
    static var noTextFound: String { NSLocalizedString("no_text_found", comment: "") }
    static var dailyLimitReached: String { NSLocalizedString("daily_limit_reached", comment: "") }
    static var clipboardEmptyHint: String { NSLocalizedString("clipboard_empty_hint", comment: "") }
    static var readTab: String { NSLocalizedString("read_tab", comment: "") }
    static var pasteAndMagnify: String { NSLocalizedString("paste_and_magnify", comment: "") }
    static var pasteHint: String { NSLocalizedString("paste_hint", comment: "") }
    static var pickFromPhotos: String { NSLocalizedString("pick_from_photos", comment: "") }
    static var pickPhotoHint: String { NSLocalizedString("pick_photo_hint", comment: "") }
    static var shutter: String { NSLocalizedString("shutter", comment: "") }
    static var photoLoadFail: String { NSLocalizedString("photo_load_fail", comment: "") }
    static var ocrPreparing: String { NSLocalizedString("ocr_preparing", comment: "") }
    static var ocrNoText: String { NSLocalizedString("ocr_no_text", comment: "") }
    /// 识别**失败**（Vision 抛错），与「这张图里确实没有文字」是两回事。
    static var ocrFail: String { NSLocalizedString("ocr_fail", comment: "") }
    static var ocrLanguage: String { NSLocalizedString("ocr_language", comment: "") }
    static var ocrLanguageDesc: String { NSLocalizedString("ocr_language_desc", comment: "") }

    /// 识别语言的首项。**需要翻译的只有这一项**——它说的是「跟系统走」这件事，
    /// 与具体是哪门语言无关。
    ///
    /// 其余选项名（`Deutsch`、`日本語`、`简体中文`…）**不在这里**，它们由
    /// `RecognitionLanguage.displayName(for:)` 生成：那些是**本族名**（autonym），
    /// 六种界面语言下刻意完全一样，因为它们指的始终是「被拍文本的语言」而不是界面语言。
    /// 界面是德语的人要拍中文文件就该选中文，写成 `简体中文` 他才能一眼找到；
    /// 翻成 `Chinesisch` 反而要他在**别的语言**里认出自己的语言。
    ///
    /// 所以它们本来就不该被翻译，也就不该进 `Localizable.strings`——放进去迟早会被
    /// 当成漏翻而翻掉，一翻掉上面那个好处就没了。这也是它们不在这里列常量的原因：
    /// 清单是运行时从 Vision 取的（本机 33 种），常量列不全，也没必要列。
    static var ocrLanguageFollowSystem: String { NSLocalizedString("ocr_language_follow_system", comment: "") }

    /// 「当前实际用的是哪一档」这一行的**左侧标签**（右侧的值是本族名，由
    /// `RecognitionLanguage.displayName(for:)` 给，不进 `.strings`——理由同首项那段）。
    /// 选了「跟随系统」之后界面上看不出解析结果，靠这一行写出来。
    static var ocrLanguageCurrent: String { NSLocalizedString("ocr_language_current", comment: "") }

    /// 设置页的 ❗ 说明，只在「实际用的 ≠ 系统语言那一档」时显示。
    static var ocrLanguageWarning: String { NSLocalizedString("ocr_language_warning", comment: "") }

    /// 阅读页的提示：「识别语言可能选错了」。标题两种理由共用，正文各一条。
    /// 两条正文都带两个 `%@`，但**第二个的含义不同**：一条是「系统语言」，
    /// 一条是「建议改用的语言」。见 `LanguageHint.Reason`。
    static var ocrHintLanguageTitle: String { NSLocalizedString("ocr_hint_language_title", comment: "") }
    static var ocrHintLanguageBody: String { NSLocalizedString("ocr_hint_language_body", comment: "") }
    static var ocrHintLanguageLooksLike: String { NSLocalizedString("ocr_hint_language_looks_like", comment: "") }
}
