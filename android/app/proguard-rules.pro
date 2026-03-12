# ---------------------------------------------
# GO_PLAY release hardening rules (R8/ProGuard)
# ---------------------------------------------

# Keep classes that are entry points from AndroidManifest.
-keep class com.example.go_play.MainActivity { *; }
-keep class com.example.go_play.pip.PlaybackForegroundService { *; }

# Keep JNI bridge class/method names stable for native symbol resolution.
-keep class com.example.go_play.RustAdblockBridge { *; }
-keep class com.example.go_play.security.SecurityNativeBridge { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Flutter engine/plugin entry points required at runtime.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.plugin.** { *; }

# Firebase / Google Sign-In use reflection + service loading internally.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.auth.** { *; }
-keep class com.google.api.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn javax.annotation.**

# Keep Kotlin metadata and annotation attributes that some SDKs inspect.
-keep class kotlin.Metadata { *; }
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod

# Strip obvious debug/log signal from release where safe.
-assumenosideeffects class android.util.Log {
    public static int d(...);
    public static int v(...);
    public static int i(...);
}

# Remove source file names from stack traces in release builds.
-renamesourcefileattribute SourceFile
