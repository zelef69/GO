package com.example.go_play.security

class SecurityNativeBridge {
    companion object {
        private const val LIB_NAME = "go_play_security"

        private val loaded: Boolean =
            runCatching {
                System.loadLibrary(LIB_NAME)
                true
            }.getOrDefault(false)

        @JvmStatic
        private external fun nativeIsTracerAttached(): Boolean

        @JvmStatic
        private external fun nativeHasSuspiciousMaps(): Boolean

        @JvmStatic
        private external fun nativeScanFridaPorts(): Boolean

        @JvmStatic
        private external fun nativeConstantTimeEquals(left: String, right: String): Boolean

        fun isLoaded(): Boolean = loaded

        fun isTracerAttached(): Boolean {
            if (!loaded) return false
            return runCatching { nativeIsTracerAttached() }.getOrDefault(false)
        }

        fun hasSuspiciousMaps(): Boolean {
            if (!loaded) return false
            return runCatching { nativeHasSuspiciousMaps() }.getOrDefault(false)
        }

        fun scanFridaPorts(): Boolean {
            if (!loaded) return false
            return runCatching { nativeScanFridaPorts() }.getOrDefault(false)
        }

        fun constantTimeEquals(left: String, right: String): Boolean {
            if (!loaded) return left == right
            return runCatching { nativeConstantTimeEquals(left, right) }.getOrDefault(false)
        }
    }
}
