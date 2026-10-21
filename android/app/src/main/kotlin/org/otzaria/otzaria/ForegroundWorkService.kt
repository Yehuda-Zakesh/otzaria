package org.otzaria.otzaria

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

/** שירות חזית (dataSync) להורדת הספרייה ב-Dart; אינו מבטיח גישה לרשת ב-Doze. */
class ForegroundWorkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // העצירה עוברת בתור הפקודות: stopService לפני onStartCommand של ההפעלה
        // היה הורס את השירות לפני startForeground, והמערכת מקריסה את האפליקציה.
        if (intent?.action == ACTION_STOP) {
            removeForeground()
            stopSelf(startId)
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
        val text = intent?.getStringExtra(EXTRA_TEXT).orEmpty()
        val channelName = intent?.getStringExtra(EXTRA_CHANNEL_NAME) ?: title
        try {
            val notification = buildNotification(channelName, title, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // למשל מכסת dataSync היומית מוצתה (אנדרואיד 15) — ההורדה ממשיכה בלי השירות.
            startFailedListener?.invoke(e.toString())
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // אנדרואיד 15 מגביל dataSync ל-6 שעות ביום; שירות שלא נעצר כאן מקריס את האפליקציה.
    override fun onTimeout(startId: Int) = handleTimeout()

    override fun onTimeout(startId: Int, fgsType: Int) = handleTimeout()

    private fun handleTimeout() {
        timeoutListener?.invoke()
        removeForeground()
        stopSelf()
    }

    private fun removeForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun buildNotification(channelName: String, title: String, text: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_LOW),
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE),
            )
        }
        return builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_CHANNEL_NAME = "channelName"
        const val ACTION_STOP = "org.otzaria.otzaria.action.STOP_FOREGROUND_WORK"
        private const val CHANNEL_ID = "library_download"
        private const val NOTIFICATION_ID = 7301

        @Volatile
        var timeoutListener: (() -> Unit)? = null

        @Volatile
        var startFailedListener: ((String) -> Unit)? = null

        fun intent(context: Context) = Intent(context, ForegroundWorkService::class.java)
    }
}
