package com.example.go_play.pip

import android.app.AppOpsManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.util.Rational
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class PipController(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL_NAME = "go_play/pip"
        private const val METHOD_SET_PIP_ENABLED = "setPiPEnabled"
        private const val METHOD_SET_VIDEO_STATE = "setVideoState"
        private const val METHOD_ENTER_PIP = "enterPiPIfEligible"
        private const val METHOD_IS_PIP_SUPPORTED = "isPiPSupported"
        private const val METHOD_IS_IN_PIP_MODE = "isInPiPMode"
        private const val METHOD_SET_BACKGROUND_PLAYBACK_ENABLED = "setBackgroundPlaybackEnabled"
        private const val METHOD_SET_APP_IN_FOREGROUND = "setAppInForeground"

        private const val DEFAULT_PIP_WIDTH = 16
        private const val DEFAULT_PIP_HEIGHT = 9
        private const val MEDIA_SESSION_MIN_UPDATE_MS = 500L
        private const val PIP_PARAMS_MIN_UPDATE_MS = 250L

        private const val FLUTTER_METHOD_PIP_ACTION = "onPiPAction"
        private const val FLUTTER_METHOD_PIP_MODE_CHANGED = "onPiPModeChanged"
        private const val TAG = "GoPlayPiP"
    }

    private val methodChannel = MethodChannel(messenger, CHANNEL_NAME)

    private var pipEnabled: Boolean = true
    private var backgroundPlaybackEnabled: Boolean = true
    private var appInForeground: Boolean = true
    private var isInPiPMode: Boolean = false

    private var videoPlaying: Boolean = false
    private var videoFullscreen: Boolean = false
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0
    private var videoRectLeft: Int = 0
    private var videoRectTop: Int = 0
    private var videoRectRight: Int = 0
    private var videoRectBottom: Int = 0
    private var hasNext: Boolean = false
    private var title: String = ""
    private var author: String = ""
    private var durationMs: Long = 0L
    private var positionMs: Long = 0L

    private var lockedSourceRectHint: Rect? = null
    private var pipReceiverRegistered = false
    private var cachedPiPSupportedAndAllowed: Boolean? = null
    private var lastMediaSessionState: MediaSessionState? = null
    private var lastMediaSessionUpdateElapsed: Long = 0L
    private var lastPiPParamsUpdateElapsed: Long = 0L

    private val mediaSessionController =
        MediaSessionController(
            context = activity,
            mediaButtonIntent = createSessionActivityIntent(),
        ) { action ->
            onSystemAction(action, source = "media_session")
        }

    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: Intent?) {
            when (intent?.action) {
                PlaybackForegroundService.ACTION_PLAY_PAUSE ->
                    onSystemAction("togglePlayPause", source = "pip_action")
                PlaybackForegroundService.ACTION_PLAY ->
                    onSystemAction("play", source = "pip_action")
                PlaybackForegroundService.ACTION_PAUSE ->
                    onSystemAction("pause", source = "pip_action")
                PlaybackForegroundService.ACTION_NEXT ->
                    onSystemAction("next", source = "pip_action")
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler(::handleMethodCall)
    }

    fun onStart() {
        registerPiPActionReceiverIfNeeded()
        onAppForegroundChanged(true)
    }

    fun onAppForegroundChanged(inForeground: Boolean) {
        appInForeground = inForeground
        Log.d(
            TAG,
            "onAppForegroundChanged inForeground=$inForeground playing=$videoPlaying inPiP=$isInPiPMode bgEnabled=$backgroundPlaybackEnabled",
        )
        refreshMediaSessionState(force = true)
        syncForegroundPlaybackService(force = true, reason = "appForegroundChanged:$inForeground")
    }

    fun onDestroy() {
        unregisterPiPActionReceiverIfNeeded()
        mediaSessionController.release()
        stopForegroundPlaybackService()
        methodChannel.setMethodCallHandler(null)
    }

    fun onPictureInPictureModeChanged(inPiP: Boolean) {
        isInPiPMode = inPiP
        if (!inPiP) {
            lockedSourceRectHint = null
        }
        refreshMediaSessionState(force = true)
        syncForegroundPlaybackService(force = true, reason = "pipModeChanged:$inPiP")
        notifyFlutterMethod(
            FLUTTER_METHOD_PIP_MODE_CHANGED,
            mapOf("isInPiPMode" to inPiP),
        )
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_SET_PIP_ENABLED -> {
                pipEnabled = call.argument<Boolean>("enabled") ?: true
                updatePictureInPictureParamsIfSupported(force = false)
                syncForegroundPlaybackService(force = true, reason = "setPiPEnabled")
                result.success(null)
            }
            METHOD_SET_BACKGROUND_PLAYBACK_ENABLED -> {
                backgroundPlaybackEnabled = call.argument<Boolean>("enabled") ?: true
                Log.d(TAG, "setBackgroundPlaybackEnabled enabled=$backgroundPlaybackEnabled")
                refreshMediaSessionState(force = true)
                syncForegroundPlaybackService(
                    force = true,
                    reason = "setBackgroundPlaybackEnabled:$backgroundPlaybackEnabled",
                )
                result.success(null)
            }
            METHOD_SET_APP_IN_FOREGROUND -> {
                val inForeground = call.argument<Boolean>("inForeground") ?: true
                onAppForegroundChanged(inForeground)
                result.success(null)
            }
            METHOD_SET_VIDEO_STATE -> {
                setVideoState(call)
                result.success(null)
            }
            METHOD_ENTER_PIP -> {
                result.success(enterPiPIfEligible())
            }
            METHOD_IS_PIP_SUPPORTED -> {
                result.success(isPiPSupportedAndAllowed())
            }
            METHOD_IS_IN_PIP_MODE -> {
                result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInPictureInPictureMode)
            }
            else -> result.notImplemented()
        }
    }

    private fun setVideoState(call: MethodCall) {
        val previousPlaying = videoPlaying
        val previousFullscreen = videoFullscreen
        val previousWidth = videoWidth
        val previousHeight = videoHeight
        val previousRectLeft = videoRectLeft
        val previousRectTop = videoRectTop
        val previousRectRight = videoRectRight
        val previousRectBottom = videoRectBottom
        val previousHasNext = hasNext

        videoPlaying = call.argument<Boolean>("isPlaying") ?: false
        videoFullscreen = call.argument<Boolean>("isFullscreen") ?: false
        videoWidth = normalizeDimension(call.argument<Int>("videoWidth"))
        videoHeight = normalizeDimension(call.argument<Int>("videoHeight"))
        videoRectLeft = normalizeCoordinate(call.argument<Int>("videoRectLeft"))
        videoRectTop = normalizeCoordinate(call.argument<Int>("videoRectTop"))
        videoRectRight = normalizeCoordinate(call.argument<Int>("videoRectRight"))
        videoRectBottom = normalizeCoordinate(call.argument<Int>("videoRectBottom"))
        title = call.argument<String>("title").orEmpty()
        author = call.argument<String>("author").orEmpty()
        durationMs = normalizeLong(call.argument<Number>("durationMs"))
        positionMs = normalizeLong(call.argument<Number>("positionMs"))
        hasNext = call.argument<Boolean>("hasNext") == true

        val paramsRelevantChange =
            previousPlaying != videoPlaying ||
                previousFullscreen != videoFullscreen ||
                previousWidth != videoWidth ||
                previousHeight != videoHeight ||
                previousHasNext != hasNext ||
                (!isInPiPMode &&
                    (previousRectLeft != videoRectLeft ||
                        previousRectTop != videoRectTop ||
                        previousRectRight != videoRectRight ||
                        previousRectBottom != videoRectBottom))

        if (paramsRelevantChange) {
            val forceUpdate = isInPiPMode && (previousHasNext != hasNext || previousPlaying != videoPlaying)
            updatePictureInPictureParamsIfSupported(force = forceUpdate)
        }

        refreshMediaSessionState(force = false)
        syncForegroundPlaybackService(force = false, reason = "setVideoState")
    }

    private fun onSystemAction(action: String, source: String) {
        if (source == "media_session" && isInPiPMode) {
            // Ignore media-session transport callbacks while in PiP.
            // They can arrive out-of-order during transition and cause pause thrashing.
            Log.d(TAG, "Ignoring media_session action in PiP: $action")
            return
        }
        // Do not optimistically mutate playback state here.
        // Keep native UI tied to the confirmed state from Flutter/WebView.
        Log.d(TAG, "onSystemAction source=$source action=$action playing=$videoPlaying")

        if (action == "next") {
            updatePictureInPictureParamsIfSupported(force = true)
        }
        refreshMediaSessionState(force = true)
        syncForegroundPlaybackService(force = true, reason = "systemAction:$action")

        val shouldNotifyFlutter =
            when (action) {
                "togglePlayPause", "play", "pause", "next" -> true
                else -> source == "pip_action"
            }
        if (shouldNotifyFlutter) {
            notifyFlutterMethod(FLUTTER_METHOD_PIP_ACTION, mapOf("action" to action))
        }
    }

    private fun refreshMediaSessionState(force: Boolean) {
        val nextState =
            MediaSessionState(
                isPlaying = videoPlaying,
                title = title,
                author = author,
                durationMs = durationMs,
                positionMs = positionMs,
                hasNext = hasNext,
                active = videoPlaying || isInPiPMode || (backgroundPlaybackEnabled && !appInForeground),
            )

        val previous = lastMediaSessionState
        val now = SystemClock.elapsedRealtime()
        if (!force && previous != null) {
            val significantChange =
                previous.isPlaying != nextState.isPlaying ||
                    previous.hasNext != nextState.hasNext ||
                    previous.active != nextState.active ||
                    previous.title != nextState.title ||
                    previous.author != nextState.author ||
                    previous.durationMs != nextState.durationMs
            val positionDeltaMs = abs(previous.positionMs - nextState.positionMs)
            val intervalElapsed = now - lastMediaSessionUpdateElapsed >= MEDIA_SESSION_MIN_UPDATE_MS
            if (!significantChange && !intervalElapsed && positionDeltaMs < 500L) {
                return
            }
        }

        mediaSessionController.update(nextState)
        lastMediaSessionState = nextState
        lastMediaSessionUpdateElapsed = now
    }

    private fun shouldRunForegroundPlaybackService(state: MediaSessionState): Boolean {
        if (!backgroundPlaybackEnabled) {
            return false
        }
        if (!state.active) {
            return false
        }
        if (state.isPlaying) {
            // Keep service warm while media is actively playing to avoid
            // lock-screen/background transition races on some OEM WebView builds.
            return true
        }
        return !appInForeground || isInPiPMode
    }

    private fun syncForegroundPlaybackService(force: Boolean, reason: String) {
        val state =
            lastMediaSessionState
                ?: MediaSessionState(
                    isPlaying = videoPlaying,
                    title = title,
                    author = author,
                    durationMs = durationMs,
                    positionMs = positionMs,
                    hasNext = hasNext,
                    active = videoPlaying || isInPiPMode || (backgroundPlaybackEnabled && !appInForeground),
                )
        val shouldRun = shouldRunForegroundPlaybackService(state)
        Log.d(
            TAG,
            "syncForegroundPlaybackService reason=$reason force=$force shouldRun=$shouldRun inForeground=$appInForeground inPiP=$isInPiPMode playing=${state.isPlaying} active=${state.active} bgEnabled=$backgroundPlaybackEnabled",
        )
        if (!shouldRun) {
            stopForegroundPlaybackService()
            return
        }
        val intent = PlaybackForegroundService.createUpdateIntent(activity, state)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
    }

    private fun stopForegroundPlaybackService() {
        runCatching {
            activity.stopService(Intent(activity, PlaybackForegroundService::class.java))
        }
    }

    private fun enterPiPIfEligible(): Boolean {
        val supportedAndAllowed = isPiPSupportedAndAllowed()
        if (!pipEnabled || !videoPlaying || !supportedAndAllowed) {
            Log.d(
                TAG,
                "enterPiPIfEligible blocked: pipEnabled=$pipEnabled, videoPlaying=$videoPlaying, supportedAndAllowed=$supportedAndAllowed",
            )
            return false
        }
        lockedSourceRectHint = calculateCurrentSourceRectHint()
        updatePictureInPictureParamsIfSupported(force = true)
        val entered =
            runCatching {
                activity.enterPictureInPictureMode(buildPictureInPictureParams(lockedSourceRectHint))
            }.getOrDefault(false)
        Log.d(TAG, "enterPiPIfEligible result: entered=$entered")
        if (!entered) {
            lockedSourceRectHint = null
        }
        return entered
    }

    private fun registerPiPActionReceiverIfNeeded() {
        if (pipReceiverRegistered) {
            return
        }
        val filter = IntentFilter().apply {
            addAction(PlaybackForegroundService.ACTION_PLAY_PAUSE)
            addAction(PlaybackForegroundService.ACTION_PLAY)
            addAction(PlaybackForegroundService.ACTION_PAUSE)
            addAction(PlaybackForegroundService.ACTION_NEXT)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(pipActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(pipActionReceiver, filter)
        }
        pipReceiverRegistered = true
    }

    private fun unregisterPiPActionReceiverIfNeeded() {
        if (!pipReceiverRegistered) {
            return
        }
        runCatching { activity.unregisterReceiver(pipActionReceiver) }
        pipReceiverRegistered = false
    }

    private fun normalizeDimension(value: Int?): Int {
        if (value == null || value <= 0) {
            return 0
        }
        return value
    }

    private fun normalizeCoordinate(value: Int?): Int {
        if (value == null || value < 0) {
            return 0
        }
        return value
    }

    private fun normalizeLong(value: Number?): Long {
        if (value == null) {
            return 0L
        }
        val normalized = value.toLong()
        return if (normalized < 0L) 0L else normalized
    }

    private fun isPiPSupportedAndAllowed(): Boolean {
        cachedPiPSupportedAndAllowed?.let { return it }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            Log.d(TAG, "PiP unsupported: sdk=${Build.VERSION.SDK_INT}")
            cachedPiPSupportedAndAllowed = false
            return false
        }
        if (!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            Log.d(TAG, "PiP unsupported: missing FEATURE_PICTURE_IN_PICTURE")
            cachedPiPSupportedAndAllowed = false
            return false
        }

        return try {
            val appOpsManager =
                activity.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
                    ?: run {
                        cachedPiPSupportedAndAllowed = false
                        return false
                    }
            val status =
                appOpsManager.checkOpNoThrow(
                    AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                    activity.applicationInfo.uid,
                    activity.packageName,
                )
            val allowed = status == AppOpsManager.MODE_ALLOWED || status == AppOpsManager.MODE_DEFAULT
            Log.d(TAG, "PiP app-op status=$status allowed=$allowed")
            cachedPiPSupportedAndAllowed = allowed
            allowed
        } catch (_: Exception) {
            // Fallback to feature check when OEM app-op behavior is inconsistent.
            Log.d(TAG, "PiP app-op check failed, fallback allow by feature")
            cachedPiPSupportedAndAllowed = true
            true
        }
    }

    private fun createSessionActivityIntent(): PendingIntent? {
        val intent =
            Intent(activity, activity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        return PendingIntent.getActivity(
            activity,
            3010,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun calculateCurrentSourceRectHint(): Rect? {
        val contentView = activity.findViewById<View>(android.R.id.content) ?: return null
        val contentRect = Rect()
        if (!contentView.getGlobalVisibleRect(contentRect) || contentRect.isEmpty) {
            return null
        }

        val hasVideoRect = videoRectRight > videoRectLeft && videoRectBottom > videoRectTop
        if (!hasVideoRect) {
            return contentRect
        }

        fun clampToContent(rect: Rect): Rect? {
            val clamped =
                Rect(
                    rect.left.coerceIn(contentRect.left, contentRect.right),
                    rect.top.coerceIn(contentRect.top, contentRect.bottom),
                    rect.right.coerceIn(contentRect.left, contentRect.right),
                    rect.bottom.coerceIn(contentRect.top, contentRect.bottom),
                )
            return if (clamped.right > clamped.left && clamped.bottom > clamped.top) clamped else null
        }

        val directRect = Rect(videoRectLeft, videoRectTop, videoRectRight, videoRectBottom)
        clampToContent(directRect)?.let { return it }

        // Some WebView builds report coordinates relative to the content view.
        val relativeRect = Rect(directRect)
        relativeRect.offset(contentRect.left, contentRect.top)
        clampToContent(relativeRect)?.let { return it }

        return contentRect
    }

    private fun pipAspectRatio(): Rational {
        // Keep PiP aspect ratio stable across videos to avoid OEM-dependent size jumps.
        return Rational(DEFAULT_PIP_WIDTH, DEFAULT_PIP_HEIGHT)
    }

    private fun createPiPAction(
        iconRes: Int,
        title: String,
        action: String,
        requestCode: Int,
        enabled: Boolean = true,
    ): RemoteAction {
        val intent = Intent(action).setPackage(activity.packageName)
        val pendingIntent =
            PendingIntent.getBroadcast(
                activity,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        return RemoteAction(
            Icon.createWithResource(activity, iconRes),
            title,
            title,
            pendingIntent,
        ).apply {
            isEnabled = enabled
        }
    }

    private fun buildPiPActions(): List<RemoteAction> {
        val togglePlayPauseAction =
            createPiPAction(
                iconRes =
                    if (videoPlaying) {
                        android.R.drawable.ic_media_pause
                    } else {
                        android.R.drawable.ic_media_play
                    },
                title = if (videoPlaying) "Pause" else "Play",
                action = PlaybackForegroundService.ACTION_PLAY_PAUSE,
                requestCode = 2000,
            )

        val nextAction =
            createPiPAction(
                iconRes = android.R.drawable.ic_media_next,
                title = "Next",
                action = PlaybackForegroundService.ACTION_NEXT,
                requestCode = 2002,
                enabled = true,
            )

        return listOf(togglePlayPauseAction, nextAction)
    }

    private fun buildPictureInPictureParams(lockedRect: Rect?): PictureInPictureParams {
        val paramsBuilder =
            PictureInPictureParams.Builder()
                .setAspectRatio(pipAspectRatio())
                .setActions(buildPiPActions())

        val sourceRect = lockedRect ?: calculateCurrentSourceRectHint()
        sourceRect?.let { paramsBuilder.setSourceRectHint(it) }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            paramsBuilder.setAutoEnterEnabled(false)
            paramsBuilder.setSeamlessResizeEnabled(true)
        }

        return paramsBuilder.build()
    }

    private fun updatePictureInPictureParamsIfSupported(force: Boolean) {
        if (!isPiPSupportedAndAllowed()) {
            return
        }
        if (!isInPiPMode && !videoPlaying) {
            // Avoid PiP param churn during startup/ad transitions before playback resumes.
            return
        }
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastPiPParamsUpdateElapsed < PIP_PARAMS_MIN_UPDATE_MS) {
            return
        }
        if (isInPiPMode && !force) {
            // Freeze PiP params while already in PiP to avoid source rect thrashing.
            return
        }
        val lockedRect = if (isInPiPMode) lockedSourceRectHint else null
        runCatching {
            activity.setPictureInPictureParams(buildPictureInPictureParams(lockedRect))
            lastPiPParamsUpdateElapsed = now
        }
    }

    private fun notifyFlutterMethod(method: String, arguments: Any?) {
        runCatching { methodChannel.invokeMethod(method, arguments) }
    }
}
