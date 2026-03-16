package com.example.talking_learning

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class LiveForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                val mode = intent?.getStringExtra(EXTRA_MODE) ?: "Guide"
                val muted = intent?.getBooleanExtra(EXTRA_MUTED, false) ?: false
                startForeground(NOTIFICATION_ID, buildNotification(mode, muted))
                return START_STICKY
            }
        }
        return START_STICKY
    }

    private fun buildNotification(mode: String, muted: Boolean): Notification {
        ensureChannel()
        val message = if (muted) {
            "$mode mode is active. Spoken replies are muted."
        } else {
            "$mode mode is active. Listening and voice replies are enabled."
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Realtime Language Guide")
            .setContentText(message)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setSilent(muted)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Live Listening",
            NotificationManager.IMPORTANCE_LOW
        )
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "live_language_guide"
        const val NOTIFICATION_ID = 3007
        const val ACTION_START = "action_start"
        const val ACTION_STOP = "action_stop"
        const val EXTRA_MODE = "extra_mode"
        const val EXTRA_MUTED = "extra_muted"
    }
}
