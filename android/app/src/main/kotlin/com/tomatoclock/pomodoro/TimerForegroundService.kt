package com.tomatoclock.pomodoro

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * 计时前台服务：常驻通知显示倒计时，附「暂停/继续」「跳过」按钮。
 * 只负责 UI 展示和把按钮点击转发给 Dart 层，计时本体在 Dart 引擎里。
 */
class TimerForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "pomodoro_timer"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "com.tomatoclock.pomodoro.START"
        const val ACTION_UPDATE = "com.tomatoclock.pomodoro.UPDATE"
        const val ACTION_STOP = "com.tomatoclock.pomodoro.STOP"
        const val ACTION_USER_TOGGLE = "com.tomatoclock.pomodoro.USER_TOGGLE"
        const val ACTION_USER_SKIP = "com.tomatoclock.pomodoro.USER_SKIP"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_RUNNING = "running"

        var isRunning = false
            private set
    }

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "计时中", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "倒计时进行中常驻显示"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    // API 34+ 必须显式声明 specialUse 类型
                    ServiceCompat.startForeground(
                        this, NOTIFICATION_ID,
                        buildNotification(
                            intent.getStringExtra(EXTRA_TITLE) ?: "番茄时钟",
                            intent.getStringExtra(EXTRA_TEXT) ?: "",
                            intent.getBooleanExtra(EXTRA_RUNNING, true),
                        ),
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                    )
                } else {
                    startForeground(
                        NOTIFICATION_ID,
                        buildNotification(
                            intent.getStringExtra(EXTRA_TITLE) ?: "番茄时钟",
                            intent.getStringExtra(EXTRA_TEXT) ?: "",
                            intent.getBooleanExtra(EXTRA_RUNNING, true),
                        ),
                    )
                }
                isRunning = true
            }
            ACTION_UPDATE -> {
                if (isRunning) {
                    getSystemService(NotificationManager::class.java).notify(
                        NOTIFICATION_ID, buildNotification(
                            intent?.getStringExtra(EXTRA_TITLE) ?: "番茄时钟",
                            intent?.getStringExtra(EXTRA_TEXT) ?: "",
                            intent?.getBooleanExtra(EXTRA_RUNNING, true) ?: true,
                        ))
                }
            }
            ACTION_STOP -> {
                isRunning = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_USER_TOGGLE -> sendToFlutter("onUserToggle")
            ACTION_USER_SKIP -> sendToFlutter("onUserSkip")
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(title: String, text: String, running: Boolean): Notification {
        val contentIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName)
                ?.apply { putExtra("from_notification", true) },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val toggleAction = NotificationCompat.Action.Builder(
            0,
            if (running) "暂停" else "继续",
            PendingIntent.getService(
                this, 1,
                Intent(this, TimerForegroundService::class.java).setAction(ACTION_USER_TOGGLE),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        ).build()

        val skipAction = NotificationCompat.Action.Builder(
            0, "跳过",
            PendingIntent.getService(
                this, 2,
                Intent(this, TimerForegroundService::class.java).setAction(ACTION_USER_SKIP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        ).build()

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(contentIntent)
            .addAction(toggleAction)
            .addAction(skipAction)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .build()
    }

    private fun sendToFlutter(method: String) {
        MainActivity.channel?.invokeMethod(method, null)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
