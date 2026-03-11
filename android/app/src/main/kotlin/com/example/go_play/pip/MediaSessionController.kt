package com.example.go_play.pip

import android.app.PendingIntent
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.SystemClock

data class MediaSessionState(
    val isPlaying: Boolean,
    val title: String,
    val author: String,
    val durationMs: Long,
    val positionMs: Long,
    val hasNext: Boolean,
    val active: Boolean,
)

class MediaSessionController(
    private val context: Context,
    private val mediaButtonIntent: PendingIntent?,
    private val onAction: (String) -> Unit,
) {
    private val mediaSession: MediaSession = MediaSession(context, "go_play_media_session")
    private var released = false

    init {
        mediaSession.setFlags(
            MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS,
        )
        mediaSession.setSessionActivity(mediaButtonIntent)
        mediaSession.setCallback(
            object : MediaSession.Callback() {
                override fun onPlay() {
                    onAction("play")
                }

                override fun onPause() {
                    onAction("pause")
                }

                override fun onSkipToNext() {
                    onAction("next")
                }
            },
        )
        mediaSession.isActive = false
    }

    fun update(state: MediaSessionState) {
        if (released) {
            return
        }

        val actions =
            PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                if (state.hasNext) PlaybackState.ACTION_SKIP_TO_NEXT else 0L

        val playbackState =
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (state.isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    state.positionMs.coerceAtLeast(0L),
                    if (state.isPlaying) 1f else 0f,
                    SystemClock.elapsedRealtime(),
                )
                .build()
        mediaSession.setPlaybackState(playbackState)

        val metadataBuilder = MediaMetadata.Builder()
        if (state.title.isNotBlank()) {
            metadataBuilder.putString(MediaMetadata.METADATA_KEY_TITLE, state.title)
        }
        if (state.author.isNotBlank()) {
            metadataBuilder.putString(MediaMetadata.METADATA_KEY_ARTIST, state.author)
        }
        if (state.durationMs > 0L) {
            metadataBuilder.putLong(MediaMetadata.METADATA_KEY_DURATION, state.durationMs)
        }
        mediaSession.setMetadata(metadataBuilder.build())
        mediaSession.isActive = state.active
    }

    fun release() {
        if (released) {
            return
        }
        released = true
        mediaSession.isActive = false
        mediaSession.release()
    }
}
