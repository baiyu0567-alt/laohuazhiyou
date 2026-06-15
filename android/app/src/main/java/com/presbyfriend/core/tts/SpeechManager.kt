package com.presbyfriend.core.tts

import android.content.Context
import android.speech.tts.TextToSpeech
import java.util.Locale

class SpeechManager(context: Context) : TextToSpeech.OnInitListener {

    private val tts: TextToSpeech = TextToSpeech(context, this)
    private var onFinish: (() -> Unit)? = null
    private var isReady = false

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isReady = true
        }
    }

    fun speak(text: String, language: String = "en", onFinish: (() -> Unit)? = null) {
        if (!isReady || text.isBlank()) return
        this.onFinish = onFinish

        tts.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
            override fun onDone(utteranceId: String?) {
                onFinish?.invoke()
            }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {}
        })

        val locale = Locale.forLanguageTag(language)
        tts.language = locale
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "presbyfriend_utt")
    }

    fun stop() {
        tts.stop()
    }

    fun shutdown() {
        tts.shutdown()
    }
}
