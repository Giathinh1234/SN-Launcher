package dev.snlauncher.snlauncher

import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/// Hosts the Nest shell in a permanently-on, chrome-free fullscreen window.
///
/// This is what makes the app behave like the real thing on a repurposed
/// tablet or HDMI stick: the launcher never shows a status bar, never sleeps,
/// and survives the system's immersive-mode swipe with a short grace period
/// rather than immediately revealing chrome.
class MainActivity : FlutterActivity() {
    private lateinit var platformBridge: PlatformBridge
    private lateinit var settingsBridge: SettingsBridge
    private lateinit var speechBridge: SpeechBridge
    private lateinit var lightSensorBridge: LightSensorBridge

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // A smart display is expected to be on all the time.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        enterImmersiveMode()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        platformBridge = PlatformBridge(this).also { it.attach(flutterEngine) }
        // Separate channel, separate bridge: the platform capability surface and
        // the persisted-settings surface change for different reasons and have
        // different lifetimes.
        settingsBridge = SettingsBridge(applicationContext).also { it.attach(flutterEngine) }
        speechBridge = SpeechBridge(applicationContext).also { it.attach(flutterEngine) }
        lightSensorBridge = LightSensorBridge(applicationContext).also { it.attach(flutterEngine) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::platformBridge.isInitialized) {
            platformBridge.onRequestPermissionsResult(requestCode, grantResults)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // The system restores chrome after any transient interruption (a
        // notification shade pull, a permission dialog, a swipe that starts on
        // the very bottom edge). Re-enter immersive mode so the launcher always
        // comes back looking like the Nest.
        if (hasFocus) enterImmersiveMode()
    }

    override fun onDestroy() {
        if (::speechBridge.isInitialized) speechBridge.detach()
        super.onDestroy()
    }

    private fun enterImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // The modern API. BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE is the
            // equivalent of immersiveSticky: bars appear on a swipe and retreat
            // again on their own.
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.apply {
                hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                )
        }

        // Draw into the cutout/notch so a full-bleed launcher really is
        // edge-to-edge on notched panels.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }
}
