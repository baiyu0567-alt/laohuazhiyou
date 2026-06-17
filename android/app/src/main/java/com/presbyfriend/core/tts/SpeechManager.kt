package com.presbyfriend.core.tts

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale

class SpeechManager(context: Context) : TextToSpeech.OnInitListener {

    private var tts: TextToSpeech? = TextToSpeech(context, this)
    // 0 = pending, 1 = success, -1 = failed
    private var initStatus = 0
    private var onFinish: (() -> Unit)? = null
    private var pendingText: String? = null
    private var pendingLanguage: String = "en"

    init {
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onDone(utteranceId: String?) {
                if (utteranceId == "presbyfriend_utt") {
                    onFinish?.invoke()
                }
            }

            override fun onStart(utteranceId: String?) {}

            @Suppress("DEPRECATION")
            @Deprecated("Override deprecated parent method")
            override fun onError(utteranceId: String?) {}

            override fun onError(utteranceId: String?, errorCode: Int) {
                Log.e("SpeechManager", "TTS error: utteranceId=$utteranceId, errorCode=$errorCode")
                onFinish?.invoke()
            }
        })
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            initStatus = 1
            Log.i("SpeechManager", "TTS initialized successfully")
            pendingText?.let { text ->
                speakInternal(text, pendingLanguage)
                pendingText = null
            }
        } else {
            initStatus = -1
            Log.e("SpeechManager", "TTS init failed with status $status")
            // Fail any pending request
            pendingText = null
            onFinish?.invoke()
        }
    }

    fun speak(text: String, language: String = "en", onFinish: (() -> Unit)? = null) {
        if (text.isBlank()) return
        this.onFinish = onFinish

        when (initStatus) {
            -1 -> {
                Log.e("SpeechManager", "TTS unavailable, cannot speak")
                onFinish?.invoke()
                return
            }
            0 -> {
                Log.i("SpeechManager", "TTS initializing, queuing speak request")
                pendingText = text
                pendingLanguage = language
                return
            }
        }

        speakInternal(text, language)
    }

    private fun speakInternal(text: String, language: String) {
        val tts = this.tts ?: return

        val locale = Locale.forLanguageTag(language)
        val result = tts.setLanguage(locale)

        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
            Log.w("SpeechManager", "Language $language not available (result=$result), falling back to US English")
            val fallbackResult = tts.setLanguage(Locale.US)
            if (fallbackResult == TextToSpeech.LANG_MISSING_DATA || fallbackResult == TextToSpeech.LANG_NOT_SUPPORTED) {
                Log.e("SpeechManager", "Fallback language also unavailable")
                // Try setting default language as last resort
                tts.language = tts.defaultLanguage
            }
        }

        val speakResult = tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "presbyfriend_utt")
        if (speakResult == TextToSpeech.ERROR) {
            Log.e("SpeechManager", "tts.speak() returned ERROR")
            onFinish?.invoke()
        }
    }

    fun stop() {
        onFinish = null
        // Some engines need both stop() + QUEUE_FLUSH with empty text
        tts?.stop()
        tts?.speak("", TextToSpeech.QUEUE_FLUSH, null, null)
    }

    fun shutdown() {
        tts?.shutdown()
        tts = null
    }
}
