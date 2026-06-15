import Foundation

/// Type-safe access to localized strings.
/// Never hardcode user-visible strings — always use L10n.
enum L10n {
    // MARK: - App
    static let appName = String(localized: "app_name")
    static let appSubtitle = String(localized: "app_subtitle")

    // MARK: - Navigation
    static let magnifierTab = String(localized: "magnifier_tab")
    static let settingsTab = String(localized: "settings_tab")

    // MARK: - Magnifier
    static let zoomLabel = String(localized: "zoom_label")
    static let flashlight = String(localized: "flashlight")
    static let tapTextToRead = String(localized: "tap_text_to_read")
    static let cameraError = String(localized: "camera_error")

    // MARK: - Reader
    static let readingMode = String(localized: "reading_mode")
    static let fontSize = String(localized: "font_size")
    static let themeLabel = String(localized: "theme_label")
    static let themeWhite = String(localized: "theme_white")
    static let themeSepia = String(localized: "theme_sepia")
    static let themeDark = String(localized: "theme_dark")
    static let themeYellow = String(localized: "theme_yellow")
    static let lineHeight = String(localized: "line_height")
    static let letterSpacing = String(localized: "letter_spacing")
    static let readAloud = String(localized: "read_aloud")
    static let stopReading = String(localized: "stop_reading")
    static let readingRuler = String(localized: "reading_ruler")
    static let rulerDescription = String(localized: "ruler_description")
    static let loadingUrl = String(localized: "loading_url")
    static let urlExtractFail = String(localized: "url_extract_fail")

    // MARK: - Settings
    static let defaultFont = String(localized: "default_font")
    static let defaultTheme = String(localized: "default_theme")
    static let languageLabel = String(localized: "language_label")
    static let dataManagement = String(localized: "data_management")
    static let resetSettings = String(localized: "reset_settings")
    static let resetConfirm = String(localized: "reset_confirm")
    static let versionFooter = String(localized: "version_footer")

    // MARK: - Pro
    static let proFeature = String(localized: "pro_feature")
    static let freeLimitReached = String(localized: "free_limit_reached")
    static let upgradePro = String(localized: "upgrade_pro")
    static let proMonthly = String(localized: "pro_monthly")
    static let proYearly = String(localized: "pro_yearly")
}
