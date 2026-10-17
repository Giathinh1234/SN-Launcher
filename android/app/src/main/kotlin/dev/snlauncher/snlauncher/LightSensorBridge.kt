package dev.snlauncher.snlauncher

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/** Provides one on-demand ambient-light reading, avoiding an always-on sensor listener. */
class LightSensorBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val sensorManager: SensorManager? = try {
        context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    } catch (_: Exception) {
        null
    }
    private val handler = Handler(Looper.getMainLooper())

    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasLightSensor" -> hasLightSensor(result)
            "lightLevel" -> lightLevel(result)
            else -> result.notImplemented()
        }
    }

    private fun hasLightSensor(result: MethodChannel.Result) {
        try {
            result.success(mapOf("available" to (sensorManager?.getDefaultSensor(Sensor.TYPE_LIGHT) != null)))
        } catch (_: Exception) {
            result.success(mapOf("available" to false))
        }
    }

    private fun lightLevel(result: MethodChannel.Result) {
        val sensor = try {
            sensorManager?.getDefaultSensor(Sensor.TYPE_LIGHT)
        } catch (_: Exception) {
            null
        }
        if (sensor == null) {
            result.success(mapOf("lux" to 0.0, "available" to false))
            return
        }

        val answered = AtomicBoolean(false)
        lateinit var listener: SensorEventListener
        lateinit var timeout: Runnable
        val finish: (Double?, Boolean) -> Unit = { lux, available ->
            if (answered.compareAndSet(false, true)) {
                handler.removeCallbacks(timeout)
                try {
                    sensorManager?.unregisterListener(listener)
                } catch (_: Exception) {
                    // A listener can race the timeout on vendor sensor implementations.
                }
                result.success(mapOf("lux" to (lux ?: 0.0), "available" to available))
            }
        }
        listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                finish(event.values.firstOrNull()?.toDouble(), true)
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        timeout = Runnable { finish(null, false) }
        try {
            // Dispatching through the main looper keeps the Flutter result on its calling thread.
            val registered = sensorManager?.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI, handler) == true
            if (!registered) {
                finish(null, false)
                return
            }
            handler.postDelayed(timeout, SENSOR_TIMEOUT_MS)
        } catch (_: Exception) {
            finish(null, false)
        }
    }

    private companion object {
        const val CHANNEL_NAME = "dev.snlauncher/sensors"
        const val SENSOR_TIMEOUT_MS = 1_500L
    }
}
