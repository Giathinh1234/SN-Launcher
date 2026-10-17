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

    // No `splits` block here on purpose.
    //
    // Android App Bundles *forbid* ABI splits: with the block enabled,
    // `flutter build appbundle` fails at buildReleasePreBundle with "Multiple
    // shrunk-resources files found". The bundle format already does per-ABI
    // delivery, so splitting it too buys nothing.
    //
    // Per-ABI APKs are still one flag away, and Flutter implements them
    // natively — no Gradle configuration needed:
    //
    //     flutter build apk --release --split-per-abi
    //
    // which matters on this project's hardware: the universal APK is 48 MB
    // because it carries three ABIs, while the arm64 one is 17.6 MB. For a
    // tablet on a metered connection that is a real difference.

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
