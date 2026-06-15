package com.presbyfriend.core.storage

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import com.presbyfriend.core.theme.ReadingTheme
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

class SettingsDataStore(private val context: Context) {

    companion object {
        private val KEY_FONT_SIZE = floatPreferencesKey("font_size")
        private val KEY_THEME = stringPreferencesKey("theme")
        private val KEY_LINE_HEIGHT = floatPreferencesKey("line_height")
        private val KEY_LETTER_SPACING = floatPreferencesKey("letter_spacing")
        private val KEY_RULER_ENABLED = booleanPreferencesKey("ruler_enabled")
        private val KEY_LANGUAGE = stringPreferencesKey("language")
        private val KEY_DAILY_USE_COUNT = intPreferencesKey("daily_use_count")
        private val KEY_LAST_USE_DATE = longPreferencesKey("last_use_date")
        private val KEY_IS_PRO = booleanPreferencesKey("is_pro")
    }

    val fontSize: Flow<Float> = context.dataStore.data.map { it[KEY_FONT_SIZE] ?: 40f }
    val theme: Flow<String> = context.dataStore.data.map { it[KEY_THEME] ?: ReadingTheme.DARK.name }
    val lineHeight: Flow<Float> = context.dataStore.data.map { it[KEY_LINE_HEIGHT] ?: 1.8f }
    val letterSpacing: Flow<Float> = context.dataStore.data.map { it[KEY_LETTER_SPACING] ?: 1.0f }
    val rulerEnabled: Flow<Boolean> = context.dataStore.data.map { it[KEY_RULER_ENABLED] ?: false }
    val language: Flow<String> = context.dataStore.data.map { it[KEY_LANGUAGE] ?: "en" }
    val dailyUseCount: Flow<Int> = context.dataStore.data.map { it[KEY_DAILY_USE_COUNT] ?: 0 }
    val isPro: Flow<Boolean> = context.dataStore.data.map { it[KEY_IS_PRO] ?: false }

    suspend fun setFontSize(value: Float) {
        context.dataStore.edit { it[KEY_FONT_SIZE] = value }
    }

    suspend fun setTheme(value: String) {
        context.dataStore.edit { it[KEY_THEME] = value }
    }

    suspend fun setLineHeight(value: Float) {
        context.dataStore.edit { it[KEY_LINE_HEIGHT] = value }
    }

    suspend fun setLetterSpacing(value: Float) {
        context.dataStore.edit { it[KEY_LETTER_SPACING] = value }
    }

    suspend fun setRulerEnabled(value: Boolean) {
        context.dataStore.edit { it[KEY_RULER_ENABLED] = value }
    }

    suspend fun setLanguage(value: String) {
        context.dataStore.edit { it[KEY_LANGUAGE] = value }
    }

    suspend fun setIsPro(value: Boolean) {
        context.dataStore.edit { it[KEY_IS_PRO] = value }
    }

    suspend fun incrementUse(): Boolean {
        var canUse = true
        context.dataStore.edit { prefs ->
            val today = System.currentTimeMillis()
            val lastDate = prefs[KEY_LAST_USE_DATE] ?: 0L
            val lastDay = lastDate / 86400000
            val todayDay = today / 86400000

            val count = if (lastDay != todayDay) 1 else (prefs[KEY_DAILY_USE_COUNT] ?: 0) + 1

            prefs[KEY_DAILY_USE_COUNT] = count
            prefs[KEY_LAST_USE_DATE] = today

            val isPro = prefs[KEY_IS_PRO] ?: false
            canUse = isPro || count <= 10
        }
        return canUse
    }

    suspend fun reset() {
        context.dataStore.edit { it.clear() }
    }
}
