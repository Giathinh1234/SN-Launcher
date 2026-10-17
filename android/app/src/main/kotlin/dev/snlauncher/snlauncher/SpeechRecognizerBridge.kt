package dev.snlauncher.snlauncher

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Timer
import java.util.TimerTask
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Exposes a single, explicitly requested utterance at a time.  This deliberately does not keep
 * a recognizer alive between requests: an always-listening launcher consumes battery and retains
 * the microphone when nobody has asked it to hear anything.
 */
class SpeechRecognizerBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private val pending = mutableListOf<PendingCall>()
    @Volatile private var initialized = false
    @Volatile private var detached = false

    // Accessed only on the main thread after initialization.
    private var inFlight: ListenCall? = null

    init {
        // SpeechRecognizer has no readiness callback. Posting this makes calls received while the
        // Flutter engine is attaching wait for the main-thread platform setup instead of vanishing.
        mainHandler.post {
            val queued: List<PendingCall>
            synchronized(lock) {
                initialized = !detached
                queued = pending.toList()
                pending.clear()
            }
            queued.forEach { pendingCall ->
                if (initialized) pendingCall.ready() else pendingCall.unavailable()
            }
        }
    }

    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "available" -> whenReady(result, { available(result) }) {
                result.success(mapOf("available" to false))
            }
            "listen" -> whenReady(result, { listen(call, result) }) {
                result.success(mapOf("text" to null, "error" to "unavailable"))
            }
            "stop" -> whenReady(result, { stop(result) }) {
                result.success(mapOf("stopped" to false))
            }
            else -> result.notImplemented()
        }
    }

    /** Call from the owning activity when its engine is being torn down. */
    fun detach() {
        mainHandler.post {
            val queued: List<PendingCall>
            synchronized(lock) {
                detached = true
                queued = pending.toList()
                pending.clear()
            }
            queued.forEach { it.unavailable() }
            inFlight?.let { finish(it, null, "stopped") }
        }
    }

    private fun whenReady(
        result: MethodChannel.Result,
        action: () -> Unit,
        unavailable: () -> Unit,
    ) {
        val executeNow: Boolean
        synchronized(lock) {
            executeNow = initialized || detached
            if (!executeNow) pending += PendingCall(action, unavailable)
        }
        if (executeNow) {
            if (!detached) mainHandler.post(action) else mainHandler.post(unavailable)
        }
    }

    private fun available(result: MethodChannel.Result) {
        val available = try {
            SpeechRecognizer.isRecognitionAvailable(appContext) && hasRecordAudioPermission()
        } catch (_: Exception) {
            false
        }
        result.success(mapOf("available" to available))
    }

    private fun listen(call: MethodCall, result: MethodChannel.Result) {
        if (!isAvailable()) {
            result.success(mapOf("text" to null, "error" to "unavailable"))
            return
        }

        // A second press replaces the previous one-shot request, rather than allowing two
        // recognizers to contend for the single microphone.
        inFlight?.let { finish(it, null, "stopped") }
        val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong() ?: DEFAULT_TIMEOUT_MS)
            .coerceIn(1L, MAX_TIMEOUT_MS)
        val maxResults = (call.argument<Number>("maxResults")?.toInt() ?: DEFAULT_MAX_RESULTS)
            .coerceAtLeast(1)
        val session = ListenCall(result)
        inFlight = session

        try {
            val recognizer = SpeechRecognizer.createSpeechRecognizer(appContext)
            session.recognizer = recognizer
            recognizer.setRecognitionListener(listenerFor(session))
            session.timer = Timer("snlauncher-stt-watchdog", true).apply {
                schedule(object : TimerTask() {
                    override fun run() {
                        mainHandler.post { finish(session, null, "timeout") }
                    }
                }, timeoutMs)
            }
            recognizer.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, maxResults)
            })
        } catch (_: Exception) {
            finish(session, null, "ERROR_CLIENT")
        }
    }

    private fun listenerFor(session: ListenCall) = object : RecognitionListener {
        override fun onReadyForSpeech(params: android.os.Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit // Results normally arrive after this callback.

        override fun onError(error: Int) {
            mainHandler.post { finish(session, null, errorName(error)) }
        }

        override fun onResults(results: android.os.Bundle?) {
            mainHandler.post {
                val text = firstResult(results)
                finish(session, text, if (text == null) "ERROR_NO_MATCH" else null)
            }
        }

        override fun onPartialResults(partialResults: android.os.Bundle?) {
            // A partial result is useful for a one-shot UI too; complete immediately so the mic is
            // released even on recognizers that never follow through with a final callback.
            mainHandler.post { firstResult(partialResults)?.let { finish(session, it, null) } }
        }

        override fun onEvent(eventType: Int, params: android.os.Bundle?) = Unit
    }

    private fun stop(result: MethodChannel.Result) {
        val session = inFlight
        if (session != null) finish(session, null, "stopped")
        result.success(mapOf("stopped" to (session != null)))
    }

    private fun finish(session: ListenCall, text: String?, error: String?) {
        if (!session.answered.compareAndSet(false, true)) return
        session.timer?.cancel()
        session.timer = null
        try {
            session.recognizer?.cancel()
        } catch (_: Exception) {
            // Vendor recognition services may already have disconnected.
        }
        try {
            session.recognizer?.destroy()
        } catch (_: Exception) {
            // destroy() is still attempted on every exit path to release the audio source.
        }
        session.recognizer = null
        if (inFlight === session) inFlight = null
        session.result.success(mapOf("text" to text, "error" to error))
    }

    private fun firstResult(results: android.os.Bundle?): String? = try {
        results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    } catch (_: Exception) {
        null
    }

    private fun isAvailable(): Boolean = try {
        SpeechRecognizer.isRecognitionAvailable(appContext) && hasRecordAudioPermission()
    } catch (_: Exception) {
        false
    }

    private fun hasRecordAudioPermission(): Boolean = appContext.checkPermission(
        Manifest.permission.RECORD_AUDIO,
        Process.myPid(),
        Process.myUid(),
    ) == PackageManager.PERMISSION_GRANTED

    private fun errorName(error: Int) = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "ERROR_AUDIO"
        SpeechRecognizer.ERROR_CLIENT -> "ERROR_CLIENT"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "ERROR_INSUFFICIENT_PERMISSIONS"
        SpeechRecognizer.ERROR_NETWORK -> "ERROR_NETWORK"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "ERROR_NETWORK_TIMEOUT"
        SpeechRecognizer.ERROR_NO_MATCH -> "ERROR_NO_MATCH"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "ERROR_RECOGNIZER_BUSY"
        SpeechRecognizer.ERROR_SERVER -> "ERROR_SERVER"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "ERROR_SPEECH_TIMEOUT"
        SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "ERROR_TOO_MANY_REQUESTS"
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "ERROR_SERVER_DISCONNECTED"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "ERROR_LANGUAGE_NOT_SUPPORTED"
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "ERROR_LANGUAGE_UNAVAILABLE"
        SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT -> "ERROR_CANNOT_CHECK_SUPPORT"
        SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS -> "ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS"
        else -> "ERROR_UNKNOWN"
    }

    private data class PendingCall(val ready: () -> Unit, val unavailable: () -> Unit)

    private class ListenCall(val result: MethodChannel.Result) {
        val answered = AtomicBoolean(false)
        var recognizer: SpeechRecognizer? = null
        var timer: Timer? = null
    }

    private companion object {
        const val CHANNEL_NAME = "dev.snlauncher/stt"
        const val DEFAULT_TIMEOUT_MS = 8_000L
        const val MAX_TIMEOUT_MS = 15_000L
        const val DEFAULT_MAX_RESULTS = 1
    }
}
