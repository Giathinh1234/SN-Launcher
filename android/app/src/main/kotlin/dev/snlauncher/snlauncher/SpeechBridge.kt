package dev.snlauncher.snlauncher

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Exposes the system TTS engine without making Flutter own its lifecycle. */
class SpeechBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val lock = Any()
    private val pending = mutableListOf<PendingCall>()
    @Volatile private var initialized = false
    @Volatile private var initializationComplete = false
    @Volatile private var detached = false

    private var tts: TextToSpeech? = null

    init {
        val preferredEngine = try {
            context.packageManager.getApplicationInfo(GOOGLE_TTS_PACKAGE, 0)
            GOOGLE_TTS_PACKAGE
        } catch (_: Exception) {
            null
        }
        // The platform default is retained unless Google's engine is present; it normally
        // supplies the broadest set of high-quality neural voices on Android devices.
        try {
            tts = if (preferredEngine == null) {
                TextToSpeech(context) { status -> onInitialized(status) }
            } else {
                TextToSpeech(context, { status -> onInitialized(status) }, preferredEngine)
            }
        } catch (_: Exception) {
            // A missing or broken engine must make calls fail cleanly, not leave Futures pending.
            initializationComplete = true
        }
    }

    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listVoices" -> whenReady(result, { listVoices(result) }) {
                result.success(mapOf("voices" to emptyList<Map<String, Any>>()))
            }
            "speak" -> whenReady(result, { speak(call, result) }) {
                result.success(mapOf("spoken" to false))
            }
            "stopSpeaking" -> whenReady(result, { stopSpeaking(result) }) {
                result.success(mapOf("stopped" to false))
            }
            "isSpeaking" -> whenReady(result, { isSpeaking(result) }) {
                result.success(mapOf("speaking" to false))
            }
            else -> result.notImplemented()
        }
    }

    fun detach() {
        val queued: List<PendingCall>
        synchronized(lock) {
            detached = true
            queued = pending.toList()
            pending.clear()
        }
        queued.forEach { it.unavailable() }
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Exception) {
            // Some vendor engines throw while their service process is already gone.
        }
    }

    private fun onInitialized(status: Int) {
        val queued: List<PendingCall>
        synchronized(lock) {
            initialized = status == TextToSpeech.SUCCESS && !detached
            initializationComplete = true
            queued = pending.toList()
            pending.clear()
        }
        queued.forEach { pendingCall ->
            if (initialized) pendingCall.ready() else pendingCall.unavailable()
        }
    }

    private fun whenReady(
        result: MethodChannel.Result,
        action: () -> Unit,
        unavailable: () -> Unit,
    ) {
        val executeNow: Boolean
        val canUse: Boolean
        synchronized(lock) {
            executeNow = initializationComplete || detached
            canUse = initialized && !detached
            if (!executeNow) pending += PendingCall(action, unavailable)
        }
        if (executeNow) {
            if (canUse) action() else unavailable()
        }
    }

    private fun listVoices(result: MethodChannel.Result) {
        try {
            val voices = (tts?.voices ?: emptySet())
                .asSequence()
                .filter { it.locale.language.equals("en", ignoreCase = true) }
                .map {
                    mapOf(
                        "id" to it.name,
                        "name" to it.name,
                        "locale" to it.locale.toLanguageTag(),
                        "quality" to it.quality,
                        "network" to it.isNetworkConnectionRequired,
                    )
                }
                .toList()
            result.success(mapOf("voices" to voices))
        } catch (_: Exception) {
            result.success(mapOf("voices" to emptyList<Map<String, Any>>()))
        }
    }

    private fun speak(call: MethodCall, result: MethodChannel.Result) {
        try {
            val text = call.argument<String>("text")?.trim().orEmpty()
            if (text.isBlank()) {
                result.success(mapOf("spoken" to false))
                return
            }
            val requestedVoice = call.argument<String>("voiceId")
            val voice = requestedVoice?.let { id -> tts?.voices?.firstOrNull { it.name == id } }
                ?: bestVoice()
            if (voice != null) {
                tts?.voice = voice
                tts?.language = voice.locale
            } else {
                tts?.language = Locale.US
            }
            val rate = (call.argument<Number>("rate")?.toFloat() ?: 0.95f).coerceAtLeast(0f)
            val pitch = (call.argument<Number>("pitch")?.toFloat() ?: 1.0f).coerceAtLeast(0f)
            val configured = tts?.setSpeechRate(rate) == TextToSpeech.SUCCESS &&
                tts?.setPitch(pitch) == TextToSpeech.SUCCESS
            val spoken = configured && tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, UTTERANCE_ID) ==
                TextToSpeech.SUCCESS
            result.success(mapOf("spoken" to spoken))
        } catch (_: Exception) {
            result.success(mapOf("spoken" to false))
        }
    }

    private fun bestVoice(): Voice? {
        val englishVoices = tts?.voices.orEmpty().filter { it.locale.language.equals("en", true) }
        // Naturalness is judged by engine quality first, then online neural voices; en-US
        // wins the remaining tie because it has the widest Android voice coverage, then en-GB.
        return englishVoices.maxWithOrNull(
            compareBy<Voice> { qualityRank(it.quality) }
                .thenBy { if (it.isNetworkConnectionRequired) 1 else 0 }
                .thenBy { localeRank(it.locale) },
        )
    }

    private fun stopSpeaking(result: MethodChannel.Result) {
        try {
            result.success(mapOf("stopped" to (tts?.stop() == TextToSpeech.SUCCESS)))
        } catch (_: Exception) {
            result.success(mapOf("stopped" to false))
        }
    }

    private fun isSpeaking(result: MethodChannel.Result) {
        try {
            result.success(mapOf("speaking" to (tts?.isSpeaking ?: false)))
        } catch (_: Exception) {
            result.success(mapOf("speaking" to false))
        }
    }

    private data class PendingCall(val ready: () -> Unit, val unavailable: () -> Unit)

    private companion object {
        const val CHANNEL_NAME = "dev.snlauncher/speech"
        const val GOOGLE_TTS_PACKAGE = "com.google.android.tts"
        const val UTTERANCE_ID = "snlauncher"

        fun qualityRank(quality: Int) = when (quality) {
            Voice.QUALITY_VERY_HIGH -> 3
            Voice.QUALITY_HIGH -> 2
            Voice.QUALITY_NORMAL -> 1
            else -> 0
        }

        fun localeRank(locale: Locale) = when (locale.toLanguageTag().lowercase(Locale.US)) {
            "en-us" -> 2
            "en-gb" -> 1
            else -> 0
        }
    }
}
