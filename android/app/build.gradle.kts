import java.security.MessageDigest
import java.util.Base64
import java.util.Locale

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun sha256Hex(value: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
    return digest.joinToString(separator = "") { "%02X".format(it) }
}

fun normalizeHex(value: String): String {
    return value.replace(":", "").replace(" ", "").uppercase(Locale.US)
}

fun boolProperty(name: String, defaultValue: Boolean): Boolean {
    val projectValue = (project.findProperty(name) as String?)?.trim()
    val envValue = System.getenv(name)?.trim()
    val resolved = projectValue ?: envValue ?: return defaultValue
    return resolved.equals("true", ignoreCase = true) || resolved == "1"
}

val rustBuildCommand =
    "cargo ndk -t armeabi-v7a -t arm64-v8a -t x86_64 -o ../../app/src/main/jniLibs " +
        "build --release || (cargo clean && cargo ndk -t armeabi-v7a -t arm64-v8a -t x86_64 " +
        "-o ../../app/src/main/jniLibs build --release)"

val expectedAppId = "com.example.go_play"
val expectedManifestSentinel = "go_play_release_v1"
val expectedCertSha256 = normalizeHex(
    (project.findProperty("GO_PLAY_EXPECTED_CERT_SHA256") as String?)
        ?: System.getenv("GO_PLAY_EXPECTED_CERT_SHA256")
        ?: "57:5F:13:AA:8F:2B:D7:13:B0:4E:B7:44:34:75:BE:91:63:66:EF:A8:A5:09:A1:B5:96:6C:20:11:1D:2D:07:D6",
)
val pinSetId =
    (project.findProperty("GO_PLAY_PIN_SET_ID") as String?)
        ?: System.getenv("GO_PLAY_PIN_SET_ID")
        ?: "default"
val pinPrimary = normalizeHex(
    (project.findProperty("GO_PLAY_PIN_SHA256_PRIMARY") as String?)
        ?: System.getenv("GO_PLAY_PIN_SHA256_PRIMARY")
        ?: "",
)
val pinBackup = normalizeHex(
    (project.findProperty("GO_PLAY_PIN_SHA256_BACKUP") as String?)
        ?: System.getenv("GO_PLAY_PIN_SHA256_BACKUP")
        ?: "",
)
val certificatePins = listOf(pinPrimary, pinBackup).filter { it.isNotBlank() }.distinct()

val expectedBuildFingerprint = sha256Hex(
    "$expectedAppId|${flutter.versionName}|${flutter.versionCode}|release|",
)

val integrityPayloadJson =
    """
    {
      "expectedAppId": "$expectedAppId",
      "expectedCertSha256": "$expectedCertSha256",
      "expectedBuildFingerprint": "$expectedBuildFingerprint",
      "expectedManifestSentinel": "$expectedManifestSentinel",
      "pinSetId": "$pinSetId",
      "certificatePinsSha256": [${certificatePins.joinToString(separator = ",") { "\"$it\"" }}]
    }
    """.trimIndent()

val integrityPayloadB64 = Base64.getEncoder().encodeToString(integrityPayloadJson.toByteArray(Charsets.UTF_8))
val integrityPayloadChecksum = sha256Hex(integrityPayloadB64)
val generatedSecurityAssetsDir = layout.buildDirectory.dir("generated/security/integrity")
val generatedIntegrityAssetName = "security_integrity_config.json"

android {
    namespace = "com.example.go_play"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // Must match package_name in android/app/google-services.json.
        applicationId = expectedAppId
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        buildConfigField("String", "SECURITY_INTEGRITY_ASSET_NAME", "\"$generatedIntegrityAssetName\"")
        buildConfigField("String", "SECURITY_CONFIG_SHA256", "\"$integrityPayloadChecksum\"")
        buildConfigField("boolean", "SECURITY_BLOCK_ON_TAMPER", boolProperty("GO_PLAY_SECURITY_BLOCK_ON_TAMPER", true).toString())
        buildConfigField("boolean", "SECURITY_BLOCK_ON_DEBUGGER", boolProperty("GO_PLAY_SECURITY_BLOCK_ON_DEBUGGER", true).toString())
        buildConfigField("boolean", "SECURITY_BLOCK_ON_HOOK", boolProperty("GO_PLAY_SECURITY_BLOCK_ON_HOOK", true).toString())
        buildConfigField("boolean", "SECURITY_BLOCK_ON_EMULATOR", boolProperty("GO_PLAY_SECURITY_BLOCK_ON_EMULATOR", true).toString())
        buildConfigField("boolean", "SECURITY_BLOCK_ON_ROOT", boolProperty("GO_PLAY_SECURITY_BLOCK_ON_ROOT", false).toString())

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17", "-fvisibility=hidden", "-fstack-protector-strong", "-D_FORTIFY_SOURCE=2")
            }
        }
    }

    sourceSets["main"].assets.srcDir(generatedSecurityAssetsDir)

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    signingConfigs {
        create("goPlayDebug") {
            storeFile = file("go_play_debug.keystore")
            storePassword = "android"
            keyAlias = "go_play_debug"
            keyPassword = "android"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("goPlayDebug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            signingConfig = signingConfigs.getByName("goPlayDebug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

val generateSecurityIntegrityConfig =
    tasks.register("generateSecurityIntegrityConfig") {
        group = "security"
        description = "Generate sealed runtime integrity config asset."
        val outputDir = generatedSecurityAssetsDir.get().asFile
        val outputFile = outputDir.resolve(generatedIntegrityAssetName)
        outputs.file(outputFile)
        doLast {
            outputDir.mkdirs()
            val fileContent =
                """
                {
                  "payload": "$integrityPayloadB64",
                  "checksum": "$integrityPayloadChecksum"
                }
                """.trimIndent()
            outputFile.writeText(fileContent)
        }
    }

tasks.register<Exec>("buildRustAdblockJni") {
    group = "native"
    description = "Build go_play_adblock_jni (adblock-rust) for Android ABIs."
    workingDir = rootProject.file("rust/adblock_jni")

    val userHome = System.getProperty("user.home")
    val cargoBin =
        if (org.gradle.internal.os.OperatingSystem.current().isWindows) {
            "$userHome\\.cargo\\bin"
        } else {
            "$userHome/.cargo/bin"
        }
    environment("PATH", "$cargoBin${System.getProperty("path.separator")}${System.getenv("PATH")}")

    if (System.getenv("ANDROID_NDK_HOME").isNullOrBlank()) {
        val androidHome =
            System.getenv("ANDROID_HOME")
                ?: if (org.gradle.internal.os.OperatingSystem.current().isWindows) {
                    "$userHome\\AppData\\Local\\Android\\Sdk"
                } else {
                    "$userHome/Android/Sdk"
                }
        val ndkRoot = file("$androidHome/ndk")
        if (ndkRoot.exists()) {
            val latestNdk =
                ndkRoot
                    .listFiles()
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
    dependsOn(generateSecurityIntegrityConfig)
}
