package com.presbyfriend.features.reader

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.presbyfriend.PresbyFriendApp
import com.presbyfriend.core.theme.ReadingTheme
import com.presbyfriend.core.tts.SpeechManager
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

class ReaderViewModel(application: Application) : AndroidViewModel(application) {

    private val store = (application as PresbyFriendApp).settingsStore
    private var speechManager: SpeechManager? = null

    private val _text = MutableStateFlow("")
    val text: StateFlow<String> = _text.asStateFlow()

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

    private val _isSpeaking = MutableStateFlow(false)
    val isSpeaking: StateFlow<Boolean> = _isSpeaking.asStateFlow()

    private val _showControls = MutableStateFlow(false)
    val showControls: StateFlow<Boolean> = _showControls.asStateFlow()

    private val _language = MutableStateFlow("en")
    val language: StateFlow<String> = _language.asStateFlow()

    init {
        viewModelScope.launch {
            store.fontSize.collect { _fontSize.value = it }
        }
        viewModelScope.launch {
            store.theme.collect { name ->
                _theme.value = ReadingTheme.fromName(name)
            }
        }
        viewModelScope.launch {
            store.lineHeight.collect { _lineHeight.value = it }
        }
        viewModelScope.launch {
            store.letterSpacing.collect { _letterSpacing.value = it }
        }
        viewModelScope.launch {
            store.rulerEnabled.collect { _rulerEnabled.value = it }
        }
        viewModelScope.launch {
            store.language.collect { _language.value = it }
        }
    }

    fun setText(content: String) {
        _text.value = content
    }

    fun adjustFontSize(by: Float) {
        val new = (_fontSize.value + by).coerceIn(24f, 72f)
        _fontSize.value = new
        viewModelScope.launch { store.setFontSize(new) }
    }

    fun setTheme(t: ReadingTheme) {
        _theme.value = t
        viewModelScope.launch { store.setTheme(t.name) }
    }

    fun adjustLineHeight(by: Float) {
        val new = (_lineHeight.value + by).coerceIn(1.0f, 3.0f)
        _lineHeight.value = new
        viewModelScope.launch { store.setLineHeight(new) }
    }

    fun adjustLetterSpacing(by: Float) {
        val new = (_letterSpacing.value + by).coerceIn(0f, 5f)
        _letterSpacing.value = new
        viewModelScope.launch { store.setLetterSpacing(new) }
    }

    fun toggleRuler() {
        _rulerEnabled.value = !_rulerEnabled.value
        viewModelScope.launch { store.setRulerEnabled(_rulerEnabled.value) }
    }

    fun toggleControls() {
        _showControls.value = !_showControls.value
    }

    fun toggleSpeaking(app: Application) {
        if (_isSpeaking.value) {
            speechManager?.stop()
            _isSpeaking.value = false
        } else {
            if (speechManager == null) {
                speechManager = SpeechManager(app)
            }
            speechManager?.speak(
                text = _text.value,
                language = _language.value,
                onFinish = { _isSpeaking.value = false }
            )
            _isSpeaking.value = true
        }
    }

    override fun onCleared() {
        super.onCleared()
        speechManager?.shutdown()
    }
}
