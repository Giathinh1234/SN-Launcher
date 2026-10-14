# Flutter/R8 keep rules.
#
# R8 shrinking is worth it here — this is an APK that will be side-loaded onto
# weak devices, so every kilobyre of dex and every unused class costs cold-start
# time on a UNISOC T610.

# The Flutter embedding and its plugins are reached reflectively by the engine.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# url_launcher resolves its platform implementation through the plugin registry.
-keep class androidx.browser.customtabs.** { *; }
-dontwarn androidx.browser.customtabs.**

# Keep annotations so R8 does not strip metadata url_launcher reads.
-keepattributes *Annotation*
-keepattributes Signature