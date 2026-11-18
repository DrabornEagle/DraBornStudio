package com.draborneagle.drabornslot

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log

class BackgroundTrackingService : Service() {
    private data class Work(val plan: Boolean, val protection: Boolean, val connected: Boolean) {
        val required get() = plan || protection
    }

    private val stateClient by lazy { SlotStateClient(this) }
    private val notifications by lazy { getSystemService(NotificationManager::class.java) }
    private var lastWork: Work? = null
    private val permissionObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) = updateNotification()
    }

    override fun onCreate() {
        super.onCreate()
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Slot takibi ve servis bağlantısı", NotificationManager.IMPORTANCE_LOW)
        )
        contentResolver.registerContentObserver(
            Settings.Secure.getUriFor(Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES), false, permissionObserver
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            PAUSE -> if (stateClient.read()?.plan?.background == true) stateClient.pause()
            STOP_PROTECTION -> SettingsStore.setConnectionProtection(this, false)
        }
        val work = currentWork()
        if (!work.required && intent?.action != null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        try {
            val notification = notification(work)
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: RuntimeException) {
            Log.w("DraBornSlot", "Arka plan servisi öne alınamadı", error)
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (!work.required) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        active = this
        lastWork = work
        return START_STICKY
    }

    override fun onDestroy() {
        if (active === this) active = null
        contentResolver.unregisterContentObserver(permissionObserver)
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun currentWork() = Work(
        plan = stateClient.read()?.shouldRunInBackground == true,
        protection = SettingsStore.connectionProtectionEnabled(this) && isSlotAccessibilityEnabled(),
        connected = SlotAccessibilityService.boundSince > 0
    )

    private fun updateNotification() {
        if (active !== this) return
        val work = currentWork()
        if (!work.required) {
            stopSelf()
            return
        }
        if (work == lastWork) return
        runCatching { notifications.notify(NOTIFICATION_ID, notification(work)) }
            .onSuccess { lastWork = work }
            .onFailure { Log.w("DraBornSlot", "Servis bildirimi güncellenemedi", it) }
    }

    private fun notification(work: Work): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val go = if (work.plan && work.connected) {
            packageManager.getLaunchIntentForPackage(SlotAccessibilityService.TARGET_PACKAGE)
        } else null
        val open = PendingIntent.getActivity(this, 1, go ?: Intent(this, MainActivity::class.java), flags)
        val title = if (work.plan) "Arka plan takibi" else "Bağlantı koruması"
        val message = when {
            !work.connected -> "Android erişilebilirlik bağlantısı bekleniyor."
            !work.plan -> "Erişilebilirlik servisi bağlı."
            else -> "Takip, telefon kilitsizken kurye uygulaması ekrana geldiğinde devam eder."
        }
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_recent_history)
            .setContentTitle("DraBornSlot · $title")
            .setContentText(message)
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setContentIntent(open)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        fun addAction(label: String, action: String, request: Int) {
            val intent = Intent(this, BackgroundTrackingService::class.java).setAction(action)
            val pending = PendingIntent.getService(this, request, intent, flags)
            builder.addAction(Notification.Action.Builder(
                Icon.createWithResource(this, android.R.drawable.ic_media_pause), label, pending
            ).build())
        }
        if (work.plan) addAction("Takibi durdur", PAUSE, 2)
        if (work.protection) addAction("Korumayı durdur", STOP_PROTECTION, 3)
        return builder.build()
    }

    companion object {
        private const val CHANNEL_ID = "slot_tracking"
        private const val NOTIFICATION_ID = 71
        private const val PAUSE = "com.draborneagle.drabornslot.PAUSE_TRACKING"
        private const val STOP_PROTECTION = "com.draborneagle.drabornslot.STOP_CONNECTION_PROTECTION"

        @Volatile
        private var active: BackgroundTrackingService? = null
        internal val isRunning get() = active != null

        internal fun refresh() {
            active?.updateNotification()
        }

        internal fun start(context: Context): Boolean = try {
            context.startForegroundService(Intent(context, BackgroundTrackingService::class.java))
            true
        } catch (error: IllegalStateException) {
            Log.w("DraBornSlot", "Arka plan takibi başlatılamadı", error)
            false
        } catch (error: SecurityException) {
            Log.w("DraBornSlot", "Arka plan takibi için servis izni alınamadı", error)
            false
        }

    }
}
