plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.snlauncher.snlauncher"
    compileSdk = flutter.compileSdkVersion
    // No `ndkVersion`: there is no native code in this app (url_launcher is
    // pure Kotlin), so declaring one makes AGP shell out to sdkmanager during
    // configuration and drag in a ~1 GB NDK download for nothing.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.snlauncher.snlauncher"
        // API 21 covers essentially every e-waste Android tablet still in
        // circulation (Android 5.0, 2014) up to current devices.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ── Hybrid CPU/GPU rendering switch ──────────────────────────────
        // Impeller (Vulkan) is the GPU path and is what we ship with. Some
        // older or badly-finned Mali/Adreno drivers hang or render incorrectly
        // under Vulkan, and there the engine's Skia/OpenGL path is the reliable
        // one.
        //
        // Override per build without editing this file:
        //     flutter build apk --release -PenableImpeller=false
        // or set it in android/gradle.properties. Default: true.
        manifestPlaceholders["enableImpeller"] =
            (project.findProperty("enableImpeller") as String?) ?: "true"
    }

    // Per-ABI APKs keep the download small — important when the target device
    // is on a metered connection.
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true
        }
    }

    buildTypes {
        release {
            // Replace with a real signing config before publishing.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        resources {
            excludes += setOf("META-INF/*.version")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
