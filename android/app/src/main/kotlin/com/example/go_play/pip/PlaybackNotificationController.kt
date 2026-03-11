package com.example.go_play.pip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build

class PlaybackNotificationController(
    private val context: Context,
) {
    companion object {
        const val CHANNEL_ID = "go_play_playback"
        const val CHANNEL_NAME = "GO_PLAY Playback"
        const val NOTIFICATION_ID = 9401
    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    init {
        ensureChannel()
    }

    fun build(state: MediaSessionState): Notification {
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

        val contentTitle = state.title.ifBlank { "GO_PLAY" }
        val contentText =
            state.author.ifBlank {
                if (state.isPlaying) "Playing in background" else "Paused"
            }

        val toggleAction = buildPlayPauseAction(isPlaying = state.isPlaying)
        val nextAction = buildNextAction()

        builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(contentTitle)
            .setContentText(contentText)
            .setOngoing(state.isPlaying)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setContentIntent(buildLaunchActivityPendingIntent())
            .setDeleteIntent(buildServiceIntent(PlaybackForegroundService.ACTION_STOP, 9410))
            .addAction(toggleAction)
        if (state.hasNext) {
            builder.addAction(nextAction)
        }

        val style = Notification.MediaStyle()
        if (state.hasNext) {
            style.setShowActionsInCompactView(0, 1)
        } else {
            style.setShowActionsInCompactView(0)
        }
        builder.setStyle(style)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setColorized(false)
        }

        return builder.build()
    }

    fun cancel() {
        notificationManager.cancel(NOTIFICATION_ID)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val existing = notificationManager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) {
            return
        }
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Playback controls while app is in background"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableLights(false)
                lightColor = Color.TRANSPARENT
                enableVibration(false)
                setSound(null, null)
            }
        notificationManager.createNotificationChannel(channel)
    }

    private fun buildPlayPauseAction(isPlaying: Boolean): Notification.Action {
        val action =
            if (isPlaying) {
                PlaybackForegroundService.ACTION_PAUSE
            } else {
                PlaybackForegroundService.ACTION_PLAY
            }
        val title = if (isPlaying) "Pause" else "Play"
        val iconRes =
            if (isPlaying) {
                android.R.drawable.ic_media_pause
            } else {
                android.R.drawable.ic_media_play
            }
        return Notification.Action.Builder(
            iconRes,
            title,
            buildServiceIntent(action, 9402),
        ).build()
    }

    private fun buildNextAction(): Notification.Action {
        return Notification.Action.Builder(
            android.R.drawable.ic_media_next,
            "Next",
            buildServiceIntent(PlaybackForegroundService.ACTION_NEXT, 9403),
        ).build()
    }

    private fun buildLaunchActivityPendingIntent(): PendingIntent? {
        val launchIntent =
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            } ?: return null
        return PendingIntent.getActivity(
            context,
            9404,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildServiceIntent(action: String, requestCode: Int): PendingIntent {
        val intent =
            Intent(context, PlaybackForegroundService::class.java).apply {
                this.action = action
            }
        return PendingIntent.getService(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
