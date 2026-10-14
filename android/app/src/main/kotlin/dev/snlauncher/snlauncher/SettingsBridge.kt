package dev.snlauncher.snlauncher

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Persists launcher settings (theme choice, weather coordinates).
 *
 * Exists so the project does not need `shared_preferences`. That plugin would
 * pull another Gradle dependency into a build whose Android configuration has
 * already been fragile — AGP shells out to `sdkmanager` while configuring, which
 * is why the Gradle configuration cache has to stay off. One more plugin is one
 * more thing to go wrong for the sake of a dozen strings.
 *
 * Backed by SharedPreferences, which is part of the platform and has been since
 * API 1, and which the Dart side falls back from automatically on desktop.
 */
class SettingsBridge(private val context: Context) {

    companion object {
        const val CHANNEL = "dev.snlauncher/settings"
        private const val PREFS = "sn_launcher_settings"
    }

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::onCall)
    }

    private fun prefs() =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                // Returned as a JSON-ish string rather than a Map so the Dart
                // side can decode it with the same code path it uses for the
                // desktop file fallback.
                "getAll" -> result.success(
                    org.json.JSONObject(prefs().all).toString()
                )

                "put" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<String>("value")
                    if (key == null) {
                        result.error("bad_args", "key is required", null)
                        return
                    }
                    prefs().edit().putString(key, value ?: "").apply()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            // Never leave a Future hanging on the Dart side — an unanswered
            // result looks exactly like a frozen button.
            result.error("settings_failed", e.message, null)
        }
    }
}