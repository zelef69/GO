package com.example.go_play.pip

import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log

class PlaybackForegroundService : Service() {
    companion object {
        private const val TAG = "GoPlayPlaybackSvc"
        const val ACTION_UPDATE_STATE = "com.example.go_play.action.UPDATE_PLAYBACK_STATE"
        const val ACTION_STOP = "com.example.go_play.action.STOP_PLAYBACK_SERVICE"
        const val ACTION_PLAY_PAUSE = "com.example.go_play.ACTION_PIP_PLAY_PAUSE"
        const val ACTION_PLAY = "com.example.go_play.ACTION_PIP_PLAY"
        const val ACTION_PAUSE = "com.example.go_play.ACTION_PIP_PAUSE"
        const val ACTION_NEXT = "com.example.go_play.ACTION_PIP_NEXT"

        private const val EXTRA_IS_PLAYING = "extra_is_playing"
        private const val EXTRA_TITLE = "extra_title"
        private const val EXTRA_AUTHOR = "extra_author"
        private const val EXTRA_DURATION_MS = "extra_duration_ms"
        private const val EXTRA_POSITION_MS = "extra_position_ms"
        private const val EXTRA_HAS_NEXT = "extra_has_next"
        private const val EXTRA_ACTIVE = "extra_active"

        fun createUpdateIntent(context: android.content.Context, state: MediaSessionState): Intent {
            return Intent(context, PlaybackForegroundService::class.java).apply {
                action = ACTION_UPDATE_STATE
                putExtra(EXTRA_IS_PLAYING, state.isPlaying)
                putExtra(EXTRA_TITLE, state.title)
                putExtra(EXTRA_AUTHOR, state.author)
                putExtra(EXTRA_DURATION_MS, state.durationMs)
                putExtra(EXTRA_POSITION_MS, state.positionMs)
                putExtra(EXTRA_HAS_NEXT, state.hasNext)
                putExtra(EXTRA_ACTIVE, state.active)
            }
        }

        fun createStopIntent(context: android.content.Context): Intent {
            return Intent(context, PlaybackForegroundService::class.java).apply {
                action = ACTION_STOP
            }
        }
    }

    private lateinit var notificationController: PlaybackNotificationController
    private var currentState =
        MediaSessionState(
            isPlaying = false,
            title = "",
            author = "",
            durationMs = 0L,
            positionMs = 0L,
            hasNext = false,
            active = false,
        )

    override fun onCreate() {
        super.onCreate()
        notificationController = PlaybackNotificationController(this)
        Log.d(TAG, "onCreate")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(
            TAG,
            "onStartCommand action=${intent?.action ?: "null"} startId=$startId playing=${currentState.isPlaying} active=${currentState.active}",
        )
        when (intent?.action) {
            ACTION_STOP -> {
                Log.d(TAG, "ACTION_STOP")
                stopForegroundCompat()
                notificationController.cancel()
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_UPDATE_STATE -> {
                currentState = stateFromIntent(intent, fallback = currentState)
                Log.d(
                    TAG,
                    "ACTION_UPDATE_STATE playing=${currentState.isPlaying} active=${currentState.active} hasNext=${currentState.hasNext} title=${currentState.title}",
                )
                if (!currentState.active) {
                    stopForegroundCompat()
                    notificationController.cancel()
                    stopSelf()
                    return START_NOT_STICKY
                }
                startOrUpdateForeground()
            }

            ACTION_PLAY_PAUSE,
            ACTION_PLAY,
            ACTION_PAUSE,
            ACTION_NEXT,
            -> {
                Log.d(TAG, "transportAction action=${intent.action}")
                applyOptimisticAction(intent.action ?: "")
                dispatchActionToController(intent.action ?: "")
                startOrUpdateForeground()
            }

            else -> {
                if (currentState.active) {
                    startOrUpdateForeground()
                }
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        stopForegroundCompat()
        notificationController.cancel()
        super.onDestroy()
    }

    private fun startOrUpdateForeground() {
        Log.d(
            TAG,
            "startOrUpdateForeground playing=${currentState.isPlaying} active=${currentState.active}",
        )
        val notification = notificationController.build(currentState)
        startForeground(PlaybackNotificationController.NOTIFICATION_ID, notification)
    }

    private fun dispatchActionToController(action: String) {
        if (action.isBlank()) {
            return
        }
        val forwardIntent =
            Intent(action).apply {
                setPackage(packageName)
            }
        Log.d(TAG, "dispatchActionToController action=$action")
        sendBroadcast(forwardIntent)
    }

    private fun applyOptimisticAction(action: String) {
        currentState =
            when (action) {
                ACTION_PLAY -> currentState.copy(isPlaying = true, active = true)
                ACTION_PAUSE -> currentState.copy(isPlaying = false, active = true)
                ACTION_PLAY_PAUSE ->
                    currentState.copy(
                        isPlaying = !currentState.isPlaying,
                        active = true,
                    )
                else -> currentState.copy(active = true)
            }
    }

    private fun stateFromIntent(
        intent: Intent,
        fallback: MediaSessionState,
    ): MediaSessionState {
        return MediaSessionState(
            isPlaying = intent.getBooleanExtra(EXTRA_IS_PLAYING, fallback.isPlaying),
            title = intent.getStringExtra(EXTRA_TITLE) ?: fallback.title,
            author = intent.getStringExtra(EXTRA_AUTHOR) ?: fallback.author,
            durationMs = intent.getLongExtra(EXTRA_DURATION_MS, fallback.durationMs),
            positionMs = intent.getLongExtra(EXTRA_POSITION_MS, fallback.positionMs),
            hasNext = intent.getBooleanExtra(EXTRA_HAS_NEXT, fallback.hasNext),
            active = intent.getBooleanExtra(EXTRA_ACTIVE, fallback.active),
        )
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
}
