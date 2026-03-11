plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val rustBuildCommand =
    "cargo ndk -t armeabi-v7a -t arm64-v8a -t x86_64 -o ../../app/src/main/jniLibs " +
        "build --release || (cargo clean && cargo ndk -t armeabi-v7a -t arm64-v8a -t x86_64 " +
        "-o ../../app/src/main/jniLibs build --release)"

android {
    namespace = "com.example.go_play"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.go_play"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

tasks.register<Exec>("buildRustAdblockJni") {
    group = "native"
    description = "Build go_play_adblock_jni (adblock-rust) for Android ABIs."
    workingDir = rootProject.file("rust/adblock_jni")

    val userHome = System.getProperty("user.home")
    val cargoBin = if (org.gradle.internal.os.OperatingSystem.current().isWindows) {
        "$userHome\\.cargo\\bin"
    } else {
        "$userHome/.cargo/bin"
    }
    environment("PATH", "$cargoBin${System.getProperty("path.separator")}${System.getenv("PATH")}")

    if (System.getenv("ANDROID_NDK_HOME").isNullOrBlank()) {
        val androidHome = System.getenv("ANDROID_HOME")
            ?: if (org.gradle.internal.os.OperatingSystem.current().isWindows) {
                "$userHome\\AppData\\Local\\Android\\Sdk"
            } else {
                "$userHome/Android/Sdk"
            }
        val ndkRoot = file("$androidHome/ndk")
        if (ndkRoot.exists()) {
            val latestNdk = ndkRoot.listFiles()
                ?.filter { it.isDirectory }
                ?.maxByOrNull { it.name }
            if (latestNdk != null) {
                environment("ANDROID_NDK_HOME", latestNdk.absolutePath)
            }
        }
    }

    if (org.gradle.internal.os.OperatingSystem.current().isWindows) {
        commandLine("cmd", "/c", rustBuildCommand)
    } else {
        commandLine("sh", "-c", rustBuildCommand)
    }

    isIgnoreExitValue = true

    doLast {
        val exitCode = executionResult.get().exitValue
        if (exitCode != 0) {
            logger.warn(
                "Rust JNI build skipped/failed (exit code $exitCode). " +
                    "Install Rust + cargo-ndk and run :app:buildRustAdblockJni.",
            )
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn("buildRustAdblockJni")
}
