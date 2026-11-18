package com.draborneagle.drabornslot

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.Service
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.ServiceInfo
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.widget.Switch
import android.widget.TextView
import java.time.LocalDate
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ResetAndServiceTest {
    @Test
    fun clearsSavedAndDraftPlanWithoutChangingAndroidGrant() {
        val context = RuntimeEnvironment.getApplication()
        val component = configureAccessibility(context)
        val tomorrow = LocalDate.now().plusDays(1).toString()
        val slot = "15:00-15:30"
        SettingsStore.save(context, SettingsStore.Config(true, true, tomorrow, listOf(slot), 20), listOf("15:30-16:00"))
        SettingsStore.markUiConfirmed(context, tomorrow, slot)
        SettingsStore.addAttempt(context, tomorrow, slot)
        EventLog.write(context, "Önceki deneme")
        val diagnostics = context.getSharedPreferences(SettingsStore.RUNTIME, Context.MODE_PRIVATE)
        diagnostics.edit().putString("last_error", "Önceki hata").commit()

        Robolectric.buildActivity(MainActivity::class.java).setup().use { controller ->
            val activity = controller.get()
            awaitUi { activity.button("Planı düzenle") != null }
            activity.button("Planı düzenle")!!.performClick()
            assertTrue(activity.button("1 saat seçili") != null)
            assertTrue(activity.button("İzleme")!!.isSelected)
            activity.button("Temizle")!!.performClick()
            awaitUi { activity.button("0 saat seçili") != null }

            val config = SettingsStore.read(context)
            assertFalse(config.active)
            assertFalse(config.dryRun)
            assertFalse(config.background)
            assertEquals(LocalDate.now().toString(), config.date)
            assertTrue(config.slots.isEmpty())
            assertEquals(1, config.refreshSeconds)
            assertTrue(SettingsStore.pendingRemovals(context, tomorrow).isEmpty())
            assertFalse(SettingsStore.isUiConfirmed(context, tomorrow, slot))
            assertTrue(EventLog.read(context).isEmpty())
            assertTrue(diagnostics.all.isEmpty())
            assertEquals(component, Settings.Secure.getString(context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES))
            assertTrue(activity.button("0 saat seçili") != null)
            assertNull(activity.button("Planı düzenle"))
            assertTrue((activity.button("Kaydedince takibi başlat") as Switch).isChecked)
            assertTrue(activity.button("Canlı seçim")!!.isSelected)

            controller.recreate()
            assertTrue(controller.get().button("0 saat seçili") != null)
            assertFalse(SettingsStore.read(context).active)
            assertNull(controller.get().button("Planı düzenle"))
            assertTrue(controller.get().button("Canlı seçim")!!.isSelected)
        }
    }

    @Test
    fun serviceStaysBoundWhenActivePlanIsClearedAndActivityIsReopened() {
        val context = RuntimeEnvironment.getApplication()
        configureAccessibility(context)
        val client = SlotStateClient(context)
        val today = LocalDate.now().toString()
        val slot = "08:00-08:30"
        assertTrue(client.save(SettingsStore.Config(true, false, today, listOf(slot), 10), emptyList()))
        val service = Robolectric.buildService(SlotAccessibilityService::class.java).create()
        try {
            connect(service.get())
            awaitUi { (client.read()?.lastCheck ?: 0L) > 0 }
            val boundSince = client.read()!!.boundSince
            Robolectric.buildActivity(MainActivity::class.java).setup().use { activity ->
                awaitUi { activity.get().button("●  Canlı seçim açık") != null }
                activity.get().button("Temizle")!!.performClick()
                awaitUi { activity.get().button("●  Takip duraklatıldı") != null }
            }

            val idle = client.read()!!
            assertEquals(boundSince, idle.boundSince)
            assertEquals(0L, idle.lastCheck)
            assertTrue(idle.plan.slots.isEmpty())
            assertFalse(idle.plan.active)

            Robolectric.buildActivity(MainActivity::class.java).setup().use { activity ->
                assertTrue(activity.get().button("Canlı seçim")!!.isSelected)
                awaitUi { activity.get().button("●  Takip duraklatıldı") != null }
                activity.get().button("08:00 – 08:30")!!.performClick()
                activity.get().applyOption("Yalnızca kaydet")
                awaitUi { activity.get().button("●  Canlı seçim açık") != null }
                assertEquals(listOf(slot), client.read()!!.plan.slots)
                assertEquals(boundSince, client.read()!!.boundSince)
                awaitUi { (client.read()?.lastCheck ?: 0L) > 0 }
            }
        } finally {
            service.destroy()
        }
    }

    @Test
    fun showsConfiguredButDisconnectedAndSupportsSecondBind() {
        val context = RuntimeEnvironment.getApplication()
        configureAccessibility(context)
        val client = SlotStateClient(context)
        Robolectric.buildActivity(MainActivity::class.java).setup().use { activityController ->
            val activity = activityController.get()
            val disconnected = "●  Erişilebilirlik açık · servis bağlantısı kesik"
            awaitUi { activity.button(disconnected) != null }
            repeat(2) { round ->
                activity.button("Bağlantıyı yenile")!!.performClick()
                assertTrue(activity.button("Yenileniyor…") != null)
                assertNull(shadowOf(activity).nextStartedActivity)
                val fallback = if (round == 1) {
                    awaitUi { ShadowDialog.getLatestDialog()?.isShowing == true }
                    ShadowDialog.getLatestDialog()
                } else null
                val service = Robolectric.buildService(SlotAccessibilityService::class.java).create()
                try {
                    connect(service.get())
                    awaitUi { activity.button("●  Takip duraklatıldı") != null }
                    assertTrue(client.read()!!.isBound)
                    assertEquals(0L, client.read()!!.lastCheck)
                    if (fallback == null) assertNull(ShadowDialog.getLatestDialog())
                    else assertFalse(fallback.isShowing)
                } finally {
                    service.destroy()
                }
                assertEquals(0L, client.read()!!.boundSince)
                awaitUi { activity.button(disconnected) != null }
            }
        }
    }

    @Test
    fun offersAndroidSettingsAfterAnUnsuccessfulReconnect() {
        val context = RuntimeEnvironment.getApplication()
        val component = configureAccessibility(context)
        Robolectric.buildActivity(MainActivity::class.java).setup().use { controller ->
            val activity = controller.get()
            awaitUi { activity.button("Bağlantıyı yenile") != null }
            activity.button("Bağlantıyı yenile")!!.performClick()
            assertNull(ShadowDialog.getLatestDialog())
            assertNull(shadowOf(activity).nextStartedActivity)
            awaitUi { ShadowDialog.getLatestDialog()?.isShowing == true }
            assertEquals(component, Settings.Secure.getString(context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES))
            val popup = ShadowDialog.getLatestDialog().window!!.decorView
            assertTrue(popup.findText("Erişilebilirlik bağlantısı") != null)
            popup.findText("Ayarları aç")!!.performClick()
            awaitUi { shadowOf(activity).peekNextStartedActivity() != null }
            assertEquals(Settings.ACTION_ACCESSIBILITY_SETTINGS, shadowOf(activity).nextStartedActivity.action)
        }
    }

    @Test
    fun manualRetryKeepsAnEmptyPlanProtectedAcrossServiceRestart() {
        val context = RuntimeEnvironment.getApplication()
        val component = configureAccessibility(context)
        val client = SlotStateClient(context)
        val app = shadowOf(context)
        Robolectric.buildActivity(MainActivity::class.java).setup().use { controller ->
            val activity = controller.get()
            awaitUi { activity.button("Bağlantıyı yenile") != null }
            activity.button("Bağlantıyı yenile")!!.performClick()
            assertTrue(SettingsStore.connectionProtectionEnabled(context))
        }
        val start = app.nextStartedService
        assertEquals(ComponentName(context, BackgroundTrackingService::class.java), start.component)
        val initial = Robolectric.buildService(BackgroundTrackingService::class.java).create()
        try {
            assertEquals(Service.START_STICKY, initial.get().onStartCommand(start, 0, 1))
            assertTrue(BackgroundTrackingService.isRunning)
            assertTrue(client.read()!!.plan.slots.isEmpty())
        } finally {
            initial.destroy()
        }

        Robolectric.buildActivity(MainActivity::class.java).setup().use {
            awaitUi { app.peekNextStartedService() != null }
            assertEquals(start.component, app.nextStartedService.component)
        }

        val restored = Robolectric.buildService(BackgroundTrackingService::class.java).create()
        val accessibility = Robolectric.buildService(SlotAccessibilityService::class.java).create()
        try {
            assertEquals(Service.START_STICKY, restored.get().onStartCommand(null, 0, 2))
            assertTrue(client.reset())
            assertTrue(SettingsStore.connectionProtectionEnabled(context))
            assertTrue(BackgroundTrackingService.isRunning)
            connect(accessibility.get())
            val service = shadowOf(restored.get())
            val notifications = shadowOf(context.getSystemService(NotificationManager::class.java))
            val notification = notifications.getNotification(service.lastForegroundNotificationId)
            assertEquals("Erişilebilirlik servisi bağlı.", notification.extras.getString(Notification.EXTRA_TEXT))
            val stop = notification.actions.single()
            assertEquals("Korumayı durdur", stop.title.toString())
            val stopIntent = shadowOf(stop.actionIntent).savedIntent
            assertEquals(Service.START_NOT_STICKY, restored.get().onStartCommand(stopIntent, 0, 3))
            assertFalse(SettingsStore.connectionProtectionEnabled(context))
            assertTrue(client.read()!!.isBound)
            assertEquals(component, Settings.Secure.getString(context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES))
        } finally {
            accessibility.destroy()
            restored.destroy()
        }
    }

    @Test
    fun planUpdatePopupDistinguishesLocalSaveFromGoRemoval() {
        val context = RuntimeEnvironment.getApplication()
        val date = LocalDate.now().toString()
        val removed = "08:00-08:30"
        val retained = "08:30-09:00"
        val client = SlotStateClient(context)
        for (removeFromGo in listOf(false, true)) {
            assertTrue(client.save(SettingsStore.Config(true, false, date, listOf(removed, retained), 1), emptyList()))
            Robolectric.buildActivity(MainActivity::class.java).setup().use { controller ->
                val activity = controller.get()
                awaitUi { activity.button("Planı düzenle") != null }
                activity.button("Planı düzenle")!!.performClick()
                activity.button("✓  08:00 – 08:30")!!.performClick()
                activity.applyOption("Yalnızca kaydet")
                val popup = ShadowDialog.getLatestDialog().window!!.decorView
                assertTrue(popup.findText("Kayıtlı planı güncelle") != null)
                assertTrue(popup.findText("08:00 – 08:30") != null)
                val action = if (removeFromGo) "GO’da da kaldır" else "Kaldırmadan kaydet"
                popup.findText(action)!!.performClick()
                awaitUi { client.read()?.plan?.slots == listOf(retained) }
                val expected = if (removeFromGo) listOf(removed) else emptyList()
                assertEquals(expected, SettingsStore.pendingRemovals(context, date))
            }
        }
    }

    @Test
    fun diagnosticsPopupCopiesThePermissionAndConnectionStates() {
        val context = RuntimeEnvironment.getApplication()
        configureAccessibility(context)
        Robolectric.buildActivity(MainActivity::class.java).setup().use { controller ->
            val activity = controller.get()
            awaitUi { activity.button("Bağlantıyı yenile") != null }
            activity.button("Servis tanısı")!!.performClick()
            val popup = ShadowDialog.getLatestDialog().window!!.decorView
            assertTrue(popup.findText("Servis tanısı") != null)
            assertTrue(popup.findText("Bağlantı koruması") != null)
            popup.findText("Kopyala")!!.performClick()
            val report = context.getSystemService(ClipboardManager::class.java)
                .primaryClip!!.getItemAt(0).text.toString()
            assertTrue(report.contains("Android erişilebilirlik izni · Açık"))
            assertTrue(report.contains("Servis bağlantısı · Kesik"))
        }
    }

    @Test
    fun recoveringAConnectedServiceKeepsThePlanAndRestartsChecks() {
        val context = RuntimeEnvironment.getApplication()
        val component = configureAccessibility(context)
        val client = SlotStateClient(context)
        val plan = SettingsStore.Config(true, false, LocalDate.now().toString(), listOf("08:00-08:30"), 10)
        assertTrue(client.save(plan, emptyList()))
        val service = Robolectric.buildService(SlotAccessibilityService::class.java).create()
        try {
            connect(service.get())
            awaitUi { (client.read()?.lastCheck ?: 0L) > 0 }
            val before = client.read()!!
            val recovered = client.recover()!!
            assertEquals(before.boundSince, recovered.boundSince)
            assertEquals(plan, recovered.plan)
            assertEquals(0L, recovered.lastCheck)
            assertEquals(TrackingState.WAITING_FOR_GO, recovered.trackingState)
            awaitUi { (client.read()?.lastCheck ?: 0L) > 0 }
            assertEquals(component, Settings.Secure.getString(context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES))
        } finally {
            service.destroy()
        }
    }

    @Test
    fun goChoiceSavesAnActivePlanAndOpensTheCourierAppOnce() {
        val context = RuntimeEnvironment.getApplication()
        configureAccessibility(context)
        val launcher = installGoLauncher(context)
        val service = Robolectric.buildService(SlotAccessibilityService::class.java).create()
        try {
            connect(service.get())
            Robolectric.buildActivity(MainActivity::class.java).setup().use { controller ->
                val activity = controller.get()
                val shadow = shadowOf(activity)
                awaitUi { activity.button("●  Takip duraklatıldı") != null }
                activity.button("08:00 – 08:30")!!.performClick()
                activity.applyOption("Uber/Trendyol GO aç")
                awaitUi { shadow.peekNextStartedActivity() != null }
                assertEquals(launcher, shadow.nextStartedActivity.component)
                shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(4))
                assertNull(shadow.nextStartedActivity)
            }
        } finally {
            service.destroy()
        }
    }

    @Test
    fun savingAnObservationPlanDoesNotOpenTrendyolGo() {
        val context = RuntimeEnvironment.getApplication()
        configureAccessibility(context)
        installGoLauncher(context)
        val service = Robolectric.buildService(SlotAccessibilityService::class.java).create()
        try {
            connect(service.get())
            Robolectric.buildActivity(MainActivity::class.java).setup().use { controller ->
                val activity = controller.get()
                awaitUi { activity.button("●  Takip duraklatıldı") != null }
                activity.button("İzleme")!!.performClick()
                activity.button("08:00 – 08:30")!!.performClick()
                activity.applyOption("Yalnızca kaydet")
                awaitUi { activity.button("●  İzleme açık") != null }
                assertNull(shadowOf(activity).nextStartedActivity)
            }
        } finally {
            service.destroy()
        }
    }

    @Test
    fun canReadTheSavedPlanAfterReopeningWithoutAnAndroidBinding() {
        val context = RuntimeEnvironment.getApplication()
        configureAccessibility(context)
        val client = SlotStateClient(context)
        val plan = SettingsStore.Config(true, true, LocalDate.now().toString(), listOf("08:00-08:30"), 5)
        assertTrue(client.save(plan, emptyList()))

        repeat(2) {
            Robolectric.buildActivity(MainActivity::class.java).setup().use { controller ->
                val activity = controller.get()
                awaitUi { activity.button("Planı düzenle") != null }
                activity.button("Planı düzenle")!!.performClick()
                assertTrue(activity.button("1 saat seçili") != null)
                assertTrue(activity.button("İzleme")!!.isSelected)
                assertFalse(client.read()!!.isBound)
                assertEquals(plan, client.read()!!.plan)
            }
        }
    }

    @Test
    fun backgroundChoiceStartsAForegroundServiceWithAPauseAction() {
        val context = RuntimeEnvironment.getApplication()
        configureAccessibility(context)
        val app = shadowOf(context)
        app.grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val client = SlotStateClient(context)
        Robolectric.buildActivity(MainActivity::class.java).setup().use { controller ->
            val activity = controller.get()
            awaitUi { activity.button("Bağlantıyı yenile") != null }
            activity.button("08:00 – 08:30")!!.performClick()
            activity.applyOption("Slotları arka planda yakala")
            awaitUi { app.peekNextStartedService() != null }
            val start = app.nextStartedService
            assertEquals(ComponentName(context, BackgroundTrackingService::class.java), start.component)
            assertTrue(client.read()!!.shouldRunInBackground)
            assertNull(shadowOf(activity).nextStartedActivity)

            val service = Robolectric.buildService(BackgroundTrackingService::class.java).create()
            try {
                assertEquals(Service.START_STICKY, service.get().onStartCommand(start, 0, 1))
                assertTrue(client.read()!!.backgroundRunning)
                val notification = shadowOf(service.get()).lastForegroundNotification
                assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
                val pause = notification.actions.single()
                assertEquals("Takibi durdur", pause.title.toString())
                val pauseIntent = shadowOf(pause.actionIntent).savedIntent
                assertEquals(Service.START_NOT_STICKY, service.get().onStartCommand(pauseIntent, 0, 2))
                assertFalse(client.read()!!.plan.active)
                assertFalse(client.read()!!.plan.background)
                assertEquals(listOf("08:00-08:30"), client.read()!!.plan.slots)
            } finally {
                service.destroy()
            }
        }
    }

    @Test
    fun stopsScreenChecksWhileLockedAndResumesOnUnlock() {
        val context = RuntimeEnvironment.getApplication()
        val client = SlotStateClient(context)
        val power = shadowOf(context.getSystemService(PowerManager::class.java))
        power.setIsInteractive(true)
        val plan = SettingsStore.Config(true, false, LocalDate.now().toString(), listOf("08:00-08:30"), 5,
            background = true)
        assertTrue(client.save(plan, emptyList()))
        val service = Robolectric.buildService(SlotAccessibilityService::class.java).create()
        try {
            connect(service.get())
            awaitUi { client.read()!!.lastCheck > 0 }
            power.setIsInteractive(false)
            context.sendBroadcast(Intent(Intent.ACTION_SCREEN_OFF))
            awaitUi { client.read()!!.trackingState == TrackingState.WAITING_FOR_UNLOCK }
            val pausedAt = client.read()!!.lastCheck
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(3))
            assertEquals(pausedAt, client.read()!!.lastCheck)
            assertEquals(plan, client.read()!!.plan)

            power.setIsInteractive(true)
            context.sendBroadcast(Intent(Intent.ACTION_USER_PRESENT))
            awaitUi { client.read()!!.trackingState == TrackingState.WAITING_FOR_GO }
            assertTrue(client.read()!!.lastCheck > pausedAt)
        } finally {
            service.destroy()
        }
    }

    @Test
    fun manifestKeepsBothServicesInTheActivityProcess() {
        val context = RuntimeEnvironment.getApplication()
        val manager = context.packageManager
        val activity = manager.getActivityInfo(ComponentName(context, MainActivity::class.java), 0)
        val service = manager.getServiceInfo(ComponentName(context, SlotAccessibilityService::class.java), 0)
        val background = manager.getServiceInfo(ComponentName(context, BackgroundTrackingService::class.java), 0)
        assertEquals(activity.processName, service.processName)
        assertEquals(activity.processName, background.processName)
        assertEquals(Manifest.permission.BIND_ACCESSIBILITY_SERVICE, service.permission)
        assertEquals(0, service.flags and ServiceInfo.FLAG_STOP_WITH_TASK)
        assertEquals(0, background.flags and ServiceInfo.FLAG_STOP_WITH_TASK)
        assertFalse(background.exported)
        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE, background.foregroundServiceType)
        assertNull(manager.resolveContentProvider("${context.packageName}.slot-state", 0))
    }

    private fun connect(service: SlotAccessibilityService) {
        SlotAccessibilityService::class.java.getDeclaredMethod("onServiceConnected").apply {
            isAccessible = true
            invoke(service)
        }
    }

    private fun awaitUi(condition: () -> Boolean) {
        val main = shadowOf(Looper.getMainLooper())
        val deadline = System.nanoTime() + Duration.ofSeconds(5).toNanos()
        do {
            main.idleFor(Duration.ofMillis(50))
            if (condition()) return
            Thread.sleep(5)
        } while (System.nanoTime() < deadline)
        assertTrue("Uygulama beklenen duruma dönmedi", condition())
    }

    private fun configureAccessibility(context: Context): String {
        val component = ComponentName(context, SlotAccessibilityService::class.java).flattenToShortString()
        Settings.Secure.putString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, component)
        return component
    }

    private fun installGoLauncher(context: Context): ComponentName {
        val goPackage = SlotAccessibilityService.TARGET_PACKAGE
        val launcher = ComponentName(goPackage, "$goPackage.Launcher")
        val app = ApplicationInfo().apply {
            packageName = goPackage
            enabled = true
        }
        val manager = shadowOf(context.packageManager)
        manager.installPackage(PackageInfo().apply {
            packageName = goPackage
            applicationInfo = app
        })
        manager.addOrUpdateActivity(ActivityInfo().apply {
            applicationInfo = app
            packageName = goPackage
            name = launcher.className
            exported = true
            enabled = true
        })
        manager.addIntentFilterForActivity(launcher, IntentFilter(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        })
        return launcher
    }

    private fun MainActivity.applyOption(label: String) {
        button("Kaydet ve uygula")!!.performClick()
        val dialog = ShadowDialog.getLatestDialog()
        assertTrue(dialog.isShowing)
        dialog.window!!.decorView.findText(label)!!.performClick()
    }

    private fun MainActivity.button(text: String): TextView? = window.decorView.findText(text)

    private fun View.findText(label: String): TextView? {
        if (this is TextView && visibility == View.VISIBLE && text.toString().substringBefore('\n') == label) return this
        if (this is ViewGroup) {
            for (index in 0 until childCount) getChildAt(index).findText(label)?.let { return it }
        }
        return null
    }
}
