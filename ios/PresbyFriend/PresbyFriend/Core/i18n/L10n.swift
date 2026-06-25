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
    static var tapTextToRead: String { NSLocalizedString("tap_text_to_read", comment: "") }
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
}
