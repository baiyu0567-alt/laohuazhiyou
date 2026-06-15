package com.presbyfriend.features.settings

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.presbyfriend.PresbyFriendApp
import com.presbyfriend.core.theme.ReadingTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class SettingsViewModel(application: Application) : AndroidViewModel(application) {

    private val store = (application as PresbyFriendApp).settingsStore

    private val _fontSize = MutableStateFlow(40f)
    val fontSize: StateFlow<Float> = _fontSize.asStateFlow()

    private val _theme = MutableStateFlow(ReadingTheme.DARK)
    val theme: StateFlow<ReadingTheme> = _theme.asStateFlow()

    private val _lineHeight = MutableStateFlow(1.8f)
    val lineHeight: StateFlow<Float> = _lineHeight.asStateFlow()

    private val _letterSpacing = MutableStateFlow(1.0f)
    val letterSpacing: StateFlow<Float> = _letterSpacing.asStateFlow()

    private val _rulerEnabled = MutableStateFlow(false)
    val rulerEnabled: StateFlow<Boolean> = _rulerEnabled.asStateFlow()

    private val _language = MutableStateFlow("en")
    val language: StateFlow<String> = _language.asStateFlow()

    val availableLanguages = listOf(
        "en" to "English",
        "de" to "Deutsch",
        "it" to "Italiano",
        "fr" to "Français",
        "es" to "Español",
        "pt" to "Português"
    )

    init {
        viewModelScope.launch { store.fontSize.collect { _fontSize.value = it } }
        viewModelScope.launch { store.theme.collect { _theme.value = ReadingTheme.fromName(it) } }
        viewModelScope.launch { store.lineHeight.collect { _lineHeight.value = it } }
        viewModelScope.launch { store.letterSpacing.collect { _letterSpacing.value = it } }
        viewModelScope.launch { store.rulerEnabled.collect { _rulerEnabled.value = it } }
        viewModelScope.launch { store.language.collect { _language.value = it } }
    }

    fun setFontSize(value: Float) {
        _fontSize.value = value
        viewModelScope.launch { store.setFontSize(value) }
    }

    fun setTheme(value: ReadingTheme) {
        _theme.value = value
        viewModelScope.launch { store.setTheme(value.name) }
    }

    fun setLineHeight(value: Float) {
        _lineHeight.value = value
        viewModelScope.launch { store.setLineHeight(value) }
    }

    fun setLetterSpacing(value: Float) {
        _letterSpacing.value = value
        viewModelScope.launch { store.setLetterSpacing(value) }
    }

    fun setRulerEnabled(value: Boolean) {
        _rulerEnabled.value = value
        viewModelScope.launch { store.setRulerEnabled(value) }
    }

    fun setLanguage(value: String) {
        _language.value = value
        viewModelScope.launch { store.setLanguage(value) }
    }

    fun reset() {
        viewModelScope.launch {
            store.reset()
            _fontSize.value = 40f
            _theme.value = ReadingTheme.DARK
            _lineHeight.value = 1.8f
            _letterSpacing.value = 1.0f
            _rulerEnabled.value = false
            _language.value = "en"
        }
    }
}
