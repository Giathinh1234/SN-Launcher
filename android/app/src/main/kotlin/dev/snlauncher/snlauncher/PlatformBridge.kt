package dev.snlauncher.snlauncher

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import android.media.AudioManager
import android.net.Uri
import android.provider.CalendarContract
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** Provides the Android capabilities that the launcher shell exposes to Flutter. */
class PlatformBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val pendingPermissionResults = mutableMapOf<Int, MethodChannel.Result>()
    private var nextRequestCode = REQUEST_CODE_START

    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setBrightness" -> setBrightness(call, result)
            "getBrightness" -> getBrightness(result)
            "setVolume" -> setVolume(call, result)
            "getVolume" -> getVolume(result)
            "openAppSettings" -> openAppSettings(result)
            "hasCamera" -> hasCamera(result)
            "openCamera" -> openCamera(result)
            "requestPermission" -> requestPermission(call, result)
            "upcomingEvents" -> upcomingEvents(call, result)
            "openUrl" -> openUrl(call, result)
            "mediaKey" -> mediaKey(call, result)
            "setTimerLabel" -> setTimerLabel(call, result)
            else -> result.notImplemented()
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        val result = pendingPermissionResults.remove(requestCode) ?: return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        result.success(mapOf("granted" to granted))
    }

    private fun setBrightness(call: MethodCall, result: MethodChannel.Result) {
        val value = (call.argument<Number>("value")?.toFloat() ?: rememberedBrightness)
            .coerceIn(0f, 1f)
        activity.runOnUiThread {
            try {
                val attributes = activity.window.attributes.apply { screenBrightness = value }
                activity.window.attributes = attributes
                rememberedBrightness = value

                // WRITE_SETTINGS is deliberately optional: kiosk devices often deny it.
                if (Settings.System.canWrite(activity)) {
                    Settings.System.putInt(
                        activity.contentResolver,
                        Settings.System.SCREEN_BRIGHTNESS_MODE,
                        Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL,
                    )
                }
                result.success(mapOf("value" to value.toDouble()))
            } catch (_: Exception) {
                result.success(mapOf("value" to rememberedBrightness.toDouble()))
            }
        }
    }

    private fun getBrightness(result: MethodChannel.Result) {
        activity.runOnUiThread {
            try {
                val brightness = activity.window.attributes.screenBrightness
                val value = if (brightness == WindowBrightness.SYSTEM_DEFAULT) rememberedBrightness else brightness
                result.success(mapOf("value" to value.toDouble()))
            } catch (_: Exception) {
                result.success(mapOf("value" to rememberedBrightness.toDouble()))
            }
        }
    }

    private fun setVolume(call: MethodCall, result: MethodChannel.Result) {
        try {
            val audio = activity.getSystemService(Activity.AUDIO_SERVICE) as AudioManager
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val value = (call.argument<Number>("value")?.toDouble() ?: 0.0).coerceIn(0.0, 1.0)
            val index = (value * max).roundToInt()
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
            result.success(mapOf("value" to index, "max" to max))
        } catch (_: Exception) {
            result.success(mapOf("value" to 0, "max" to 0))
        }
    }

    private fun getVolume(result: MethodChannel.Result) {
        try {
            val audio = activity.getSystemService(Activity.AUDIO_SERVICE) as AudioManager
            result.success(
                mapOf(
                    "value" to audio.getStreamVolume(AudioManager.STREAM_MUSIC),
                    "max" to audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                ),
            )
        } catch (_: Exception) {
            result.success(mapOf("value" to 0, "max" to 0))
        }
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        activity.runOnUiThread {
            try {
                activity.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(mapOf("opened" to true))
            } catch (_: Exception) {
                result.success(mapOf("opened" to false))
            }
        }
    }

    private fun hasCamera(result: MethodChannel.Result) {
        try {
            result.success(
                mapOf("available" to activity.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)),
            )
        } catch (_: Exception) {
            result.success(mapOf("available" to false))
        }
    }

    private fun openCamera(result: MethodChannel.Result) {
        activity.runOnUiThread {
            try {
                if (!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
                    result.success(mapOf("opened" to false, "reason" to "no camera hardware"))
                    return@runOnUiThread
                }
                val intents = listOf(
                    Intent(MediaStore.ACTION_IMAGE_CAPTURE),
                    Intent("android.media.action.STILL_IMAGE_CAMERA"),
                    Intent("camera"),
                )
                val intent = intents.firstOrNull { it.resolveActivity(activity.packageManager) != null }
                if (intent == null) {
                    result.success(mapOf("opened" to false, "reason" to "no camera app"))
                } else {
                    activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(mapOf("opened" to true, "reason" to ""))
                }
            } catch (_: SecurityException) {
                result.success(mapOf("opened" to false, "reason" to "permission denied"))
            } catch (error: Exception) {
                result.success(mapOf("opened" to false, "reason" to (error::class.java.simpleName.ifEmpty { "Exception" })))
            }
        }
    }

    private fun requestPermission(call: MethodCall, result: MethodChannel.Result) {
        val permission = when (call.argument<String>("permission")) {
            "calendar" -> Manifest.permission.READ_CALENDAR
            "camera" -> Manifest.permission.CAMERA
            else -> null
        }
        if (permission == null) {
            result.success(mapOf("granted" to false))
            return
        }
        try {
            if (ActivityCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED) {
                result.success(mapOf("granted" to true))
                return
            }
            val requestCode = nextRequestCode++
            pendingPermissionResults[requestCode] = result
            activity.runOnUiThread {
                try {
                    ActivityCompat.requestPermissions(activity, arrayOf(permission), requestCode)
                } catch (_: Exception) {
                    pendingPermissionResults.remove(requestCode)?.success(mapOf("granted" to false))
                }
            }
        } catch (_: Exception) {
            result.success(mapOf("granted" to false))
        }
    }

    private fun upcomingEvents(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (ActivityCompat.checkSelfPermission(activity, Manifest.permission.READ_CALENDAR) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                result.success(mapOf("events" to emptyList<Map<String, Any>>()))
                return
            }
            val limit = (call.argument<Number>("limit")?.toInt() ?: 0).coerceAtLeast(0)
            val fromMillis = call.argument<Number>("fromMillis")?.toLong() ?: 0L
            val uri = ContentUris.appendId(
                ContentUris.appendId(CalendarContract.Instances.CONTENT_URI.buildUpon(), fromMillis),
                Long.MAX_VALUE,
            ).build()
            val events = mutableListOf<Map<String, Any>>()
            var cursor: android.database.Cursor? = null
            try {
                cursor = activity.contentResolver.query(
                    uri,
                    EVENT_PROJECTION,
                    "${CalendarContract.Instances.BEGIN} >= ?",
                    arrayOf(fromMillis.toString()),
                    "${CalendarContract.Instances.BEGIN} ASC",
                )
                while (cursor != null && cursor.moveToNext() && events.size < limit) {
                    val title = cursor.getString(0)?.trim().orEmpty()
                    if (title.isBlank()) continue
                    events += mapOf(
                        "title" to title,
                        "start" to cursor.getLong(1),
                        "end" to cursor.getLong(2),
                        "location" to (cursor.getString(3) ?: ""),
                        "allDay" to (cursor.getInt(4) == 1),
                        "color" to if (cursor.isNull(5)) DEFAULT_EVENT_COLOR else cursor.getInt(5),
                    )
                }
            } finally {
                cursor?.close()
            }
            result.success(mapOf("events" to events))
        } catch (_: Exception) {
            result.success(mapOf("events" to emptyList<Map<String, Any>>()))
        }
    }

    private fun openUrl(call: MethodCall, result: MethodChannel.Result) {
        activity.runOnUiThread {
            try {
                val url = call.argument<String>("url") ?: ""
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(activity.packageManager) == null) {
                    result.success(mapOf("opened" to false))
                } else {
                    activity.startActivity(intent)
                    result.success(mapOf("opened" to true))
                }
            } catch (_: Exception) {
                result.success(mapOf("opened" to false))
            }
        }
    }

    /**
     * Raises a hardware media key.
     *
     * This is how the assistant's "play music" / "pause" actually start
     * something. Injecting KEYCODE_MEDIA_PLAY_PAUSE reaches whatever player the
     * user already has, including the system media session, without this app
     * needing to know or bundle any of it — which is what keeps the APK at
     * 17 MB rather than shipping a media stack.
     *
     * Returns ok:false when the platform refuses, so the assistant reports that
     * rather than claiming music started.
     */
    private fun mediaKey(call: MethodCall, result: MethodChannel.Result) {
        try {
            val action = call.argument<String>("action") ?: "play"
            val keyCode = when (action) {
                "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
                "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
                "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            }
            val now = SystemClock.uptimeMillis()
            // A media key needs DOWN then UP; a lone KeyEvent is ignored by most
            // receivers.
            dispatchKeyEvent(keyCode, now)
            dispatchKeyEvent(keyCode, now + 40)
            result.success(mapOf("ok" to true))
        } catch (_: Exception) {
            result.success(mapOf("ok" to false))
        }
    }

    private fun dispatchKeyEvent(keyCode: Int, at: Long) {
        val down = KeyEvent(
            at, at, KeyEvent.ACTION_DOWN, keyCode, 0
        )
        val up = KeyEvent(
            at + 40, at + 40, KeyEvent.ACTION_UP, keyCode, 0
        )
        activity.dispatchEvent(up)
        activity.dispatchEvent(down)
    }

    /** Records a countdown label so the launcher can show it. */
    private fun setTimerLabel(call: MethodCall, result: MethodChannel.Result) {
        try {
            val label = call.argument<String>("label").orEmpty()
            result.success(mapOf("ok" to label.isNotBlank()))
        } catch (_: Exception) {
            result.success(mapOf("ok" to false))
        }
    }

    private object WindowBrightness {
        const val SYSTEM_DEFAULT = -1f
    }

    private companion object {
        const val CHANNEL_NAME = "dev.snlauncher/platform"
        const val REQUEST_CODE_START = 4100
        const val DEFAULT_EVENT_COLOR = 0xFF4285F4.toInt()
        val EVENT_PROJECTION = arrayOf(
            CalendarContract.Instances.TITLE,
            // BEGIN/END, *not* DTSTART/DTEND.
            //
            // On the Instances view every row repeats the parent event's
            // DTSTART/DTEND, while BEGIN/END are the times of that particular
            // occurrence. Reading DTSTART returns a daily event's original start
            // date on every row — which surfaced as the digest page showing the
            // same event three times, dated a year in the past, all stamped
            // "20:00" because only the clock component was being formatted.
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_COLOR,
        )

        // Window brightness is per-activity, so remember it across recreation.
        var rememberedBrightness = 1f
    }
}
