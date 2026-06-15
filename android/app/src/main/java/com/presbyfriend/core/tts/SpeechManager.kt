package com.presbyfriend.core.tts

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

class SpeechManager(context: Context) : TextToSpeech.OnInitListener {

    private val tts: TextToSpeech = TextToSpeech(context, this)
    private var isReady = false
    private var onFinish: (() -> Unit)? = null

    init {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onDone(utteranceId: String?) {
                if (utteranceId == "presbyfriend_utt") {
                    onFinish?.invoke()
                }
            }

            override fun onStart(utteranceId: String?) {}

            @Suppress("DEPRECATION")
            override fun onError(utteranceId: String?) {}

            override fun onError(utteranceId: String?, errorCode: Int) {}
        })
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            isReady = true
        }
    }

    fun speak(text: String, language: String = "en", onFinish: (() -> Unit)? = null) {
        if (!isReady || text.isBlank()) return
        this.onFinish = onFinish

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
