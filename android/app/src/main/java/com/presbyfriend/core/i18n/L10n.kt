package com.presbyfriend.core.i18n

import androidx.annotation.StringRes
import com.presbyfriend.R

/**
 * Type-safe string resource references.
 * Usage: stringResource(L10n.appName) in Compose, or getString(L10n.appName) in Context.
 */
object L10n {
    @StringRes val appName = R.string.app_name
    @StringRes val appSubtitle = R.string.app_subtitle
    @StringRes val magnifierTab = R.string.magnifier_tab
    @StringRes val settingsTab = R.string.settings_tab
    @StringRes val zoomLabel = R.string.zoom_label
    @StringRes val flashlight = R.string.flashlight
    @StringRes val tapTextToRead = R.string.tap_text_to_read
    @StringRes val cameraError = R.string.camera_error
    @StringRes val cameraPermissionRequired = R.string.camera_permission_required
    @StringRes val readingMode = R.string.reading_mode
    @StringRes val fontSize = R.string.font_size
    @StringRes val themeLabel = R.string.theme_label
    @StringRes val themeWhite = R.string.theme_white
    @StringRes val themeSepia = R.string.theme_sepia
    @StringRes val themeDark = R.string.theme_dark
    @StringRes val themeYellow = R.string.theme_yellow
    @StringRes val lineHeight = R.string.line_height
    @StringRes val letterSpacing = R.string.letter_spacing
    @StringRes val readAloud = R.string.read_aloud
    @StringRes val stopReading = R.string.stop_reading
    @StringRes val readingRuler = R.string.reading_ruler
    @StringRes val rulerDescription = R.string.ruler_description
    @StringRes val defaultFont = R.string.default_font
    @StringRes val defaultTheme = R.string.default_theme
    @StringRes val showControls = R.string.show_controls
    @StringRes val languageLabel = R.string.language_label
    @StringRes val dataManagement = R.string.data_management
    @StringRes val resetSettings = R.string.reset_settings
    @StringRes val resetConfirm = R.string.reset_confirm
    @StringRes val versionFooter = R.string.version_footer
    @StringRes val proFeature = R.string.pro_feature
    @StringRes val freeLimitReached = R.string.free_limit_reached
    @StringRes val upgradePro = R.string.upgrade_pro
    @StringRes val proMonthly = R.string.pro_monthly
    @StringRes val proMonthlyDesc = R.string.pro_monthly_desc
    @StringRes val proYearly = R.string.pro_yearly
    @StringRes val proYearlyDesc = R.string.pro_yearly_desc
    @StringRes val restorePurchases = R.string.restore_purchases
    @StringRes val close = R.string.close
    @StringRes val loadingUrl = R.string.loading_url
    @StringRes val urlExtractFail = R.string.url_extract_fail
    @StringRes val noSharedContent = R.string.no_shared_content
    @StringRes val quickTileLabel = R.string.quick_tile_label
    @StringRes val accessibilityDescription = R.string.accessibility_description
    @StringRes val accessibilityAction = R.string.accessibility_action
    @StringRes val enableAccessibility = R.string.enable_accessibility
    @StringRes val accessibilityHint = R.string.accessibility_hint
}
