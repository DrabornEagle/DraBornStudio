package com.draborneagle.drabornslot

import android.Manifest
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.app.ActivityManager
import android.app.AlertDialog
import android.app.ApplicationExitInfo
import android.app.Dialog
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.View
import android.view.Window
import android.view.WindowInsets
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class MainActivity : Activity() {
    private val night = Color.rgb(5, 12, 32)
    private val surface = Color.rgb(16, 28, 56)
    private val raised = Color.rgb(24, 39, 72)
    private val outline = Color.rgb(49, 66, 105)
    private val ink = Color.rgb(248, 249, 255)
    private val muted = Color.rgb(176, 190, 221)
    private val mint = Color.rgb(98, 243, 199)
    private val lilac = Color.rgb(190, 171, 255)
    private val sky = Color.rgb(127, 207, 255)
    private val peach = Color.rgb(255, 195, 131)
    private val rose = Color.rgb(255, 154, 175)
    private val locale = Locale.forLanguageTag("tr-TR")
    private val shortDate = DateTimeFormatter.ofPattern("d MMMM", locale)
    private val weekday = DateTimeFormatter.ofPattern("EEE", locale)
    private val dayMonth = DateTimeFormatter.ofPattern("d MMM", locale)
    private val timeFormatter = DateTimeFormatter.ofPattern("d MMM HH:mm:ss", locale)

    private lateinit var content: LinearLayout
    private lateinit var dashboardScroll: ScrollView
    private lateinit var status: TextView
    private lateinit var choiceCount: TextView
    private lateinit var chosenDateLabel: TextView
    private lateinit var planText: TextView
    private lateinit var planEdit: TextView
    private lateinit var stopButton: TextView
    private lateinit var reconnectButton: TextView
    private lateinit var dateStrip: LinearLayout
    private lateinit var groupStrip: LinearLayout
    private lateinit var slotGrid: LinearLayout
    private lateinit var modeWatch: TextView
    private lateinit var modeLive: TextView
    private lateinit var speedLabel: TextView
    private lateinit var speedSlider: SeekBar
    private lateinit var activeSwitch: Switch
    private lateinit var logs: LinearLayout
    private lateinit var moreLogs: TextView

    private val handler = Handler(Looper.getMainLooper())
    private val stateClient by lazy { SlotStateClient(applicationContext) }
    private val stateWorker = Executors.newSingleThreadExecutor()
    private var planChangesPending = 0
    private var statusReadPending = false
    private var checkedStatus = false
    private var resumed = false
    private var checkConnectionOnResume = false
    private var adoptSavedSettings = true
    private var currentState: SlotState? = null
    private var lastState: SlotState? = null
    private var selectedDate = LocalDate.now()
    private val selectedSlots = linkedSetOf<String>()
    private var selectedGroup = 0
    private var live = !SettingsStore.DEFAULT_DRY_RUN
    private var wantedActive = true
    private var editingPlan = false
    private var refreshSeconds = SettingsStore.MIN_REFRESH_SECONDS
    private var showAllLogs = false
    private var renderedLogKey: Pair<String, Boolean>? = null

    private class Recovery(val showSettings: Boolean)
    private enum class ApplyAction { OPEN_GO, BACKGROUND, SAVE_ONLY }

    private var recovery: Recovery? = null
    private var connectionPopup: Dialog? = null
    private val recoveryTimeout = Runnable {
        finishRecovery(SlotAccessibilityService.boundSince > 0 && isSlotAccessibilityEnabled())
    }
    private val statusCheck = object : Runnable {
        override fun run() {
            readStatus()
            handler.postDelayed(this, if (recovery == null) 1_200 else 450)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        setTheme(R.style.Theme_DraBornSlot)
        super.onCreate(savedInstanceState)
        window.setDecorFitsSystemWindows(false)
        window.isStatusBarContrastEnforced = false
        window.isNavigationBarContrastEnforced = false
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = 0
        adoptSavedSettings = savedInstanceState == null
        selectedDate = readDate(savedInstanceState?.getString("date"))
        savedInstanceState?.getStringArrayList("slots")?.let(selectedSlots::addAll)
        selectedGroup = savedInstanceState?.getInt("group") ?: 0
        editingPlan = savedInstanceState?.getBoolean("editing") ?: false
        live = savedInstanceState?.getBoolean("live") ?: !SettingsStore.DEFAULT_DRY_RUN
        wantedActive = savedInstanceState?.getBoolean("active", true) ?: true
        refreshSeconds = savedInstanceState?.getInt("speed") ?: SettingsStore.MIN_REFRESH_SECONDS

        val frame = FrameLayout(this).apply {
            setBackgroundColor(night)
            setOnApplyWindowInsetsListener { view, insets ->
                val system = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
                view.setPadding(system.left, system.top, system.right, system.bottom)
                insets
            }
        }
        val layout = vertical()
        dashboardScroll = ScrollView(this).apply {
            isFillViewport = true
            clipToPadding = false
            isVerticalScrollBarEnabled = false
        }
        content = vertical().apply { setPadding(18.dp(), 18.dp(), 18.dp(), 22.dp()) }
        dashboardScroll.addView(content)
        layout.addView(dashboardScroll, LinearLayout.LayoutParams(-1, 0, 1f))
        buildDashboard()
        layout.addView(buildFooter())
        frame.addView(layout, FrameLayout.LayoutParams(-1, -1))
        setContentView(frame)
        renderStatus()
        if (savedInstanceState == null && ValueAnimator.areAnimatorsEnabled()) animateLaunch(frame)
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        checkConnectionOnResume = true
        handler.removeCallbacks(statusCheck)
        handler.post(statusCheck)
    }

    override fun onPause() {
        resumed = false
        cancelRecovery()
        handler.removeCallbacks(statusCheck)
        super.onPause()
    }

    override fun onDestroy() {
        connectionPopup?.dismiss()
        stateWorker.shutdown()
        super.onDestroy()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("date", selectedDate.toString())
        outState.putStringArrayList("slots", ArrayList(selectedSlots))
        outState.putInt("group", selectedGroup)
        outState.putBoolean("editing", editingPlan)
        outState.putBoolean("live", live)
        outState.putBoolean("active", activeSwitch.isChecked)
        outState.putInt("speed", refreshSeconds)
        super.onSaveInstanceState(outState)
    }

    private fun buildDashboard() {
        val header = horizontal()
        header.addView(mark(52), LinearLayout.LayoutParams(52.dp(), 52.dp()).apply { marginEnd = 12.dp() })
        val name = vertical()
        name.addView(text("DraBornSlot", 24, ink, "sans-serif-black"))
        name.addView(text("Saat planı ve canlı takip", 13, muted), block(top = 3))
        header.addView(name, weight())
        header.addView(badge(getString(R.string.app_version), lilac, Color.rgb(45, 37, 84)))
        content.addView(header, block(bottom = 18))

        val hero = vertical().apply {
            setPadding(18.dp(), 17.dp(), 18.dp(), 14.dp())
            background = gradient(intArrayOf(Color.rgb(31, 39, 91), Color.rgb(22, 44, 81), Color.rgb(13, 68, 74)), 24)
        }
        status = text("", 13, sky, "sans-serif-medium")
        hero.addView(status)
        choiceCount = text("", 31, ink, "sans-serif-black")
        hero.addView(choiceCount, block(top = 7))
        chosenDateLabel = text("", 14, Color.rgb(220, 231, 255))
        hero.addView(chosenDateLabel, block(top = 3, bottom = 11))
        planText = text("", 13, muted).apply { setLineSpacing(3.dp().toFloat(), 1f) }
        hero.addView(planText)
        val planActions = horizontal()
        planEdit = action("Planı düzenle", raised, ink, 13, ::loadPlan)
        stopButton = action("Takibi durdur", Color.rgb(66, 40, 63), rose, 13, ::pausePlan)
        planActions.addView(planEdit, weight(end = 8))
        planActions.addView(stopButton, weight())
        hero.addView(planActions, block(top = 10))
        reconnectButton = action("Bağlantıyı yenile", raised, peach, 13) { recoverConnection(showSettings = true) }
        hero.addView(reconnectButton, block(top = 9))
        content.addView(hero, block(bottom = 23))

        content.addView(heading("Çalışma günü"), block(bottom = 9))
        dateStrip = horizontal()
        content.addView(horizontalScroll(dateStrip), block(bottom = 22))
        renderDates()

        content.addView(heading("Saat tercihleri"))
        val selectionActions = horizontal()
        selectionActions.addView(action("Tümünü seç", Color.rgb(21, 65, 66), mint, 13) {
            adoptSavedSettings = false
            selectedSlots.addAll(SettingsStore.displayedSlots)
            renderSlots()
        }, weight(end = 8))
        selectionActions.addView(action("Temizle", raised, muted, 13, ::resetApplication), weight())
        content.addView(selectionActions, block(top = 9, bottom = 11))
        groupStrip = horizontal()
        content.addView(horizontalScroll(groupStrip), block(bottom = 9))
        slotGrid = vertical()
        content.addView(slotGrid, block(bottom = 23))
        renderSlots()

        content.addView(heading("Takip ayarları"), block(bottom = 9))
        val panel = panel()
        val modes = horizontal()
        modeWatch = action("İzleme", raised, sky, 14) {
            adoptSavedSettings = false
            live = false
            renderModes()
        }
        modeLive = action("Canlı seçim", raised, peach, 14, ::chooseLive)
        modes.addView(modeWatch, weight(end = 8))
        modes.addView(modeLive, weight())
        panel.addView(modes, block(bottom = 8))
        panel.addView(text("İzleme görünür durumu kaydeder. Canlı seçim Tüm Saatler sekmesini açar ve uygun saatin + düğmesine dokunur.", 13, muted))
        activeSwitch = Switch(this).apply {
            text = "Kaydedince takibi başlat"
            textSize = 15f
            setTextColor(ink)
            isChecked = wantedActive
            minHeight = 52.dp()
            setOnCheckedChangeListener { _, _ -> adoptSavedSettings = false }
        }
        panel.addView(activeSwitch, block(top = 7, bottom = 9))
        panel.addView(View(this).apply { setBackgroundColor(outline) }, LinearLayout.LayoutParams(-1, 1.dp()))
        speedLabel = text("", 15, ink, "sans-serif-medium")
        panel.addView(speedLabel, block(top = 14))
        speedSlider = SeekBar(this).apply {
            max = SettingsStore.MAX_REFRESH_SECONDS - SettingsStore.MIN_REFRESH_SECONDS
            progress = refreshSeconds - SettingsStore.MIN_REFRESH_SECONDS
            contentDescription = "Trendyol GO sayfa yenileme aralığı"
            progressTintList = ColorStateList.valueOf(mint)
            thumbTintList = ColorStateList.valueOf(mint)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar?, value: Int, fromUser: Boolean) {
                    if (fromUser) adoptSavedSettings = false
                    refreshSeconds = value + SettingsStore.MIN_REFRESH_SECONDS
                    renderSpeed()
                }
                override fun onStartTrackingTouch(bar: SeekBar?) = Unit
                override fun onStopTrackingTouch(bar: SeekBar?) = Unit
            })
        }
        panel.addView(speedSlider)
        val speeds = horizontal()
        for ((index, preset) in listOf(1, 5, 15).withIndex()) {
            speeds.addView(action("$preset sn", raised, if (preset == 1) mint else muted, 13) {
                adoptSavedSettings = false
                speedSlider.progress = preset - SettingsStore.MIN_REFRESH_SECONDS
            }, weight(end = if (index < 2) 8 else 0))
        }
        panel.addView(speeds, block(bottom = 9))
        panel.addView(text("Takip, telefon kilitsizken Uber/Trendyol GO ekranda olduğunda çalışır.", 13, muted))
        content.addView(panel, block(bottom = 12))
        renderModes()
        renderSpeed()

        val serviceActions = horizontal()
        serviceActions.addView(action("Erişilebilirlik", raised, sky, 13, ::openAccessibility), weight(end = 8))
        serviceActions.addView(action("Servis tanısı", raised, lilac, 13, ::showDiagnostics), weight())
        content.addView(serviceActions, block(bottom = 24))

        content.addView(heading("İşlem geçmişi"), block(bottom = 9))
        val logPanel = panel()
        logs = vertical()
        logPanel.addView(logs)
        moreLogs = action("Tüm kayıtları göster", raised, sky, 13) {
            showAllLogs = !showAllLogs
            renderLogs(lastState?.history.orEmpty())
        }
        logPanel.addView(moreLogs, block(top = 8))
        content.addView(logPanel)
    }

    private fun buildFooter() = horizontal().apply {
        setBackgroundColor(surface)
        setPadding(14.dp(), 8.dp(), 14.dp(), 8.dp())
        addView(action("Uber/Trendyol GO aç", raised, ink, 13, ::openTrendyol), weight(end = 8))
        addView(action("Kaydet ve uygula", mint, night, 15, ::showApplyOptions), weight())
    }

    private fun readDate(value: String?): LocalDate {
        val today = LocalDate.now()
        val date = value?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: today
        return if (date in today..today.plusDays(6)) date else today
    }

    private fun renderDates() {
        dateStrip.removeAllViews()
        val today = LocalDate.now()
        for (offset in 0L..6L) {
            val date = today.plusDays(offset)
            val picked = date == selectedDate
            val label = if (offset == 0L) "Bugün" else date.format(weekday)
            val choice = vertical().apply {
                gravity = Gravity.CENTER
                minimumHeight = 65.dp()
                setPadding(6.dp(), 6.dp(), 6.dp(), 6.dp())
                background = ripple(if (picked) mint else surface, 15, if (picked) mint else outline)
                contentDescription = date.format(shortDate) + " " + label
                isSelected = picked
                addView(text(date.format(dayMonth), 16, if (picked) night else ink, "sans-serif-medium").apply {
                    gravity = Gravity.CENTER
                })
                addView(text(label, 12, if (picked) night else muted, "sans-serif-medium"))
                setOnClickListener {
                    if (selectedDate == date) return@setOnClickListener
                    adoptSavedSettings = false
                    selectedDate = date
                    selectedSlots.clear()
                    editingPlan = false
                    renderDates()
                    renderSlots()
                }
            }
            dateStrip.addView(choice, LinearLayout.LayoutParams(73.dp(), -2).apply { marginEnd = 7.dp() })
        }
    }

    private fun renderSlots() {
        val extraSlots = selectedSlots - SettingsStore.displayedSlots.toSet()
        val groups = if (extraSlots.isEmpty()) SettingsStore.slotGroups else
            SettingsStore.slotGroups + SettingsStore.SlotGroup("Diğer", extraSlots.sortedBy(SettingsStore::slotMinute))
        selectedGroup = selectedGroup.coerceIn(groups.indices)
        val groupColors = listOf(peach, mint, lilac, sky, rose)
        groupStrip.removeAllViews()
        groups.forEachIndexed { index, group ->
            val picked = selectedGroup == index
            val count = group.slots.count { it in selectedSlots }
            val accent = groupColors[index]
            val title = if (count > 0) "${group.title}  $count" else group.title
            val item = action(title, if (picked) accent else surface, if (picked) night else muted, 13) {
                selectedGroup = index
                renderSlots()
            }.apply {
                isSelected = picked
                minimumWidth = 70.dp()
                contentDescription = "${group.title}, $count saat seçili"
            }
            groupStrip.addView(item, LinearLayout.LayoutParams(-2, -2).apply { marginEnd = 7.dp() })
        }

        slotGrid.removeAllViews()
        val accent = groupColors[selectedGroup]
        for (pair in groups[selectedGroup].slots.chunked(2)) {
            val row = horizontal()
            pair.forEachIndexed { index, slot ->
                val picked = slot in selectedSlots
                val label = slot.replace("-", " – ")
                val tile = action(if (picked) "✓  $label" else label,
                    if (picked) Color.rgb(23, 68, 72) else surface, if (picked) accent else ink, 14) {
                    adoptSavedSettings = false
                    if (!selectedSlots.add(slot)) selectedSlots.remove(slot)
                    renderSlots()
                }.apply {
                    isSelected = picked
                    stateDescription = if (picked) "Seçili" else "Seçilmedi"
                    contentDescription = label
                }
                row.addView(tile, weight(end = if (index == 0) 8 else 0))
            }
            if (pair.size == 1) row.addView(View(this), weight())
            slotGrid.addView(row, block(bottom = 7))
        }
        choiceCount.text = "${selectedSlots.size} saat seçili"
        chosenDateLabel.text = selectedDate.format(shortDate)
    }

    private fun renderModes() {
        modeWatch.background = ripple(if (live) raised else sky, 13)
        modeWatch.setTextColor(if (live) muted else night)
        modeWatch.isSelected = !live
        modeLive.background = ripple(if (live) peach else raised, 13)
        modeLive.setTextColor(if (live) night else muted)
        modeLive.isSelected = live
    }

    private fun chooseLive() {
        if (live) return
        AlertDialog.Builder(this).setTitle("Canlı seçim")
            .setMessage("Takip açıkken DraBornSlot, Trendyol GO’nun saat ekranında seçtiğin uygun saatleri işaretlemek için dokunur. Kayıtlı saatlerini Trendyol GO içinde doğrula.")
            .setNegativeButton("Vazgeç", null)
            .setPositiveButton("Canlı seçimi kullan") { _, _ ->
                adoptSavedSettings = false
                live = true
                renderModes()
            }
            .show()
    }

    private fun renderSpeed() {
        speedLabel.text = "Sayfayı yenileme · $refreshSeconds sn"
    }

    private fun loadPlan() {
        if (planChangesPending > 0) return
        val saved = lastState?.plan ?: return toast("Kayıtlı plan okunamadı.")
        adoptSavedSettings = false
        selectedDate = readDate(saved.date)
        selectedSlots.clear()
        selectedSlots.addAll(saved.slots)
        live = !saved.dryRun
        activeSwitch.isChecked = true
        speedSlider.progress = saved.refreshSeconds - SettingsStore.MIN_REFRESH_SECONDS
        selectedGroup = 0
        editingPlan = true
        renderDates()
        renderSlots()
        renderModes()
    }

    private fun showApplyOptions() {
        if (planChangesPending > 0) return
        val selection = "${selectedDate.format(shortDate)} · ${selectedSlots.size} saat seçili"
        showPopup("Kaydet ve uygula", selection) { sheet, dialog ->
            sheet.addView(popupAction("Uber/Trendyol GO aç", "Seçimlerini kaydet ve kurye uygulamasına geç.") {
                dialog.dismiss()
                savePlan(ApplyAction.OPEN_GO)
            }, block(bottom = 8))
            sheet.addView(popupAction("Slotları arka planda yakala",
                "Plan hazır bekler. Telefon kilitsizken GO ekrana geldiğinde takip devam eder.",
                Color.rgb(20, 66, 67), mint) {
                dialog.dismiss()
                savePlan(ApplyAction.BACKGROUND)
            }, block(bottom = 8))
            sheet.addView(popupAction("Yalnızca kaydet", "Planı kaydet ve bu ekranda kal.") {
                dialog.dismiss()
                savePlan(ApplyAction.SAVE_ONLY)
            }, block(bottom = 8))
            sheet.addView(action("Vazgeç", surface, muted, 14, dialog::dismiss), block(top = 2))
        }
    }

    private fun showPopup(title: String, summary: String? = null, body: (LinearLayout, Dialog) -> Unit): Dialog {
        val dialog = Dialog(this)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        val sheet = vertical().apply {
            background = gradient(intArrayOf(surface, Color.rgb(21, 41, 67)), 24)
            setPadding(18.dp(), 19.dp(), 18.dp(), 14.dp())
            addView(heading(title), block(bottom = if (summary == null) 14 else 6))
            if (summary != null) addView(text(summary, 14, muted).apply {
                setLineSpacing(3.dp().toFloat(), 1f)
            }, block(bottom = 15))
        }
        body(sheet, dialog)
        dialog.setContentView(ScrollView(this).apply {
            setPadding(18.dp(), 15.dp(), 18.dp(), 15.dp())
            addView(sheet)
        })
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        dialog.show()
        dialog.window?.setDimAmount(0.62f)
        val width = minOf(windowManager.currentWindowMetrics.bounds.width(), 510.dp())
        dialog.window?.setLayout(width, -2)
        return dialog
    }

    private fun popupAction(label: String, detail: String, fill: Int = raised, accent: Int = ink,
                            onClick: () -> Unit): TextView =
        action(label, fill, accent, 15, onClick).apply {
            val caption = SpannableString("$label\n$detail")
            val spanFlags = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            caption.setSpan(StyleSpan(Typeface.BOLD), 0, label.length, spanFlags)
            caption.setSpan(ForegroundColorSpan(muted), label.length + 1, caption.length, spanFlags)
            caption.setSpan(RelativeSizeSpan(0.87f), label.length + 1, caption.length, spanFlags)
            text = caption
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = 64.dp()
            setLineSpacing(3.dp().toFloat(), 1f)
            setPadding(14.dp(), 11.dp(), 14.dp(), 11.dp())
            isFocusable = true
        }

    private fun popupField(label: String, value: String, accent: Int = ink): LinearLayout =
        vertical().apply {
            background = shape(raised, 12)
            setPadding(12.dp(), 9.dp(), 12.dp(), 9.dp())
            addView(text(label, 12, muted, "sans-serif-medium"), block(bottom = 4))
            addView(text(value, 14, accent).apply { setLineSpacing(2.dp().toFloat(), 1f) })
        }

    private fun savePlan(choice: ApplyAction) {
        if (planChangesPending > 0) return
        if (selectedSlots.isEmpty() && !editingPlan) {
            if (choice == ApplyAction.OPEN_GO) openTrendyol()
            else toast("Saat seç veya kayıtlı planı düzenle.")
            return
        }
        val previous = lastState?.plan ?: return toast("Plan bilgisi okunuyor. Biraz sonra tekrar dene.")
        val config = SettingsStore.Config(
            active = choice == ApplyAction.BACKGROUND || activeSwitch.isChecked,
            dryRun = !live,
            date = selectedDate.toString(),
            slots = selectedSlots.sortedBy(SettingsStore::slotMinute),
            refreshSeconds = refreshSeconds,
            background = choice == ApplyAction.BACKGROUND
        )
        val removed = if (previous.date == config.date) previous.slots - config.slots.toSet() else emptyList()
        if (removed.isEmpty() || !live) {
            persistPlan(config, emptyList(), choice)
            return
        }
        val preview = removed.take(4).joinToString("\n") { it.replace("-", " – ") }
        val remainder = if (removed.size > 4) "\n+${removed.size - 4} saat" else ""
        showPopup("Kayıtlı planı güncelle", "${selectedDate.format(shortDate)} · ${removed.size} saat yeni planda yer almıyor.") { sheet, dialog ->
            sheet.addView(popupField("Plandan çıkarılacak saatler", preview + remainder), block(bottom = 12))
            sheet.addView(popupAction("Kaldırmadan kaydet", "Seçimlerini DraBornSlot planına kaydet.",
                Color.rgb(20, 66, 67), mint) {
                dialog.dismiss()
                persistPlan(config, emptyList(), choice)
            }, block(bottom = 8))
            sheet.addView(popupAction("GO’da da kaldır", "Bu saatler için Trendyol GO’da kaldırma isteği oluştur.",
                Color.rgb(66, 40, 63), rose) {
                dialog.dismiss()
                persistPlan(config, removed, choice)
            }, block(bottom = 8))
            sheet.addView(action("Vazgeç", surface, muted, 14, dialog::dismiss))
        }
    }

    private fun persistPlan(config: SettingsStore.Config, removed: List<String>, choice: ApplyAction) {
        cancelRecovery()
        changePlan({ stateClient.save(config, removed) }) { current ->
            activeSwitch.isChecked = current?.plan?.active ?: config.active
            editingPlan = true
            if (!resumed || planChangesPending > 0) return@changePlan
            if (choice == ApplyAction.BACKGROUND && current?.shouldRunInBackground == true) {
                startBackgroundTracking()
            } else {
                toast("Plan kaydedildi.")
                if (choice == ApplyAction.OPEN_GO) openTrendyol()
            }
        }
    }

    private fun startBackgroundTracking() {
        if (!ensureBackgroundService()) {
            toast("Plan kaydedildi. Android, arka plan takibini başlatamadı.")
            return
        }
        if (needsNotificationPermission()) askForNotifications()
        val message = if (isSlotAccessibilityEnabled()) "Arka plan takibi hazırlanıyor."
            else "Takibi başlatmak için Android’den erişilebilirlik iznini aç."
        toast(message)
    }

    private fun needsNotificationPermission() = Build.VERSION.SDK_INT >= 33 &&
        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED

    private fun askForNotifications() = requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 71)

    private fun ensureBackgroundService(): Boolean {
        if (!BackgroundTrackingService.isRunning) return BackgroundTrackingService.start(this)
        BackgroundTrackingService.refresh()
        return true
    }

    private fun pausePlan() {
        if (planChangesPending > 0) return
        changePlan(stateClient::pause) { activeSwitch.isChecked = false }
    }

    private fun changePlan(update: () -> Boolean, onSaved: (SlotState?) -> Unit) {
        planChangesPending++
        stateWorker.execute {
            val saved = update()
            val current = stateClient.read()
            handler.post {
                if (isDestroyed) return@post
                planChangesPending--
                showState(current)
                if (saved) onSaved(current) else toast("Plan değişikliği kaydedilemedi. Tekrar dene.")
            }
        }
    }

    private fun openTrendyol() {
        val target = packageManager.getLaunchIntentForPackage(SlotAccessibilityService.TARGET_PACKAGE)
        if (target == null) {
            toast("Trendyol GO uygulaması cihazda bulunamadı.")
            return
        }
        try {
            startActivity(target)
        } catch (_: ActivityNotFoundException) {
            toast("Trendyol GO açılamadı.")
        } catch (_: SecurityException) {
            toast("Android, Trendyol GO’yu açamadı.")
        }
    }

    private fun openAccessibility() {
        try {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        } catch (_: ActivityNotFoundException) {
            toast("Erişilebilirlik ayarları açılamadı.")
        }
    }

    private fun readStatus() {
        if (statusReadPending || planChangesPending > 0) return
        val attempt = recovery
        statusReadPending = true
        stateWorker.execute {
            val state = if (attempt != null && SlotAccessibilityService.boundSince > 0) stateClient.recover()
                else stateClient.read()
            handler.post {
                statusReadPending = false
                if (isDestroyed || !resumed || planChangesPending > 0) return@post
                showState(state)
                if (attempt != null && recovery === attempt && state?.isBound == true &&
                    isSlotAccessibilityEnabled()) {
                    finishRecovery(true)
                } else if (checkConnectionOnResume) {
                    checkConnectionOnResume = false
                    if (state?.shouldRunInBackground == true ||
                        (SettingsStore.connectionProtectionEnabled(this) && isSlotAccessibilityEnabled())) {
                        ensureBackgroundService()
                    }
                    if (state?.isBound != true) recoverConnection()
                }
            }
        }
    }

    private fun recoverConnection(showSettings: Boolean = false) {
        if (!resumed || planChangesPending > 0 || (recovery != null && !showSettings)) return
        if (!isSlotAccessibilityEnabled()) {
            if (showSettings) openAccessibility()
            return
        }
        if (showSettings) {
            SettingsStore.setConnectionProtection(this, true)
            if (!ensureBackgroundService()) toast("Android, bağlantı korumasını başlatamadı.")
        }
        checkConnectionOnResume = false
        cancelRecovery()
        recovery = Recovery(showSettings)
        renderStatus()
        handler.removeCallbacks(statusCheck)
        handler.post(statusCheck)
        handler.postDelayed(recoveryTimeout, if (showSettings) 5_000 else 3_000)
    }

    private fun cancelRecovery() {
        recovery = null
        handler.removeCallbacks(recoveryTimeout)
    }

    private fun finishRecovery(bound: Boolean) {
        val attempt = recovery ?: return
        cancelRecovery()
        renderStatus()
        if (!resumed || isFinishing) return
        if (bound) {
            if (attempt.showSettings) toast("Erişilebilirlik bağlantısı hazır.")
        } else if (attempt.showSettings) {
            showReconnectHelp()
        }
    }

    private fun showReconnectHelp() {
        val popup = showPopup("Erişilebilirlik bağlantısı",
            "Android servisi henüz bağlamadı. Ayarlarda DraBornSlot hizmetini kapatıp aç ve uygulamaya dön.") { sheet, dialog ->
            sheet.addView(popupField("Bağlantı koruması", connectionProtectionStatus(), sky), block(bottom = 12))
            sheet.addView(popupAction("Ayarları aç", "Android erişilebilirlik ayarlarına git.",
                Color.rgb(20, 66, 67), mint) {
                dialog.dismiss()
                openAccessibility()
            }, block(bottom = 9))
            val buttons = horizontal()
            buttons.addView(action("Tekrar dene", raised, sky, 14) {
                dialog.dismiss()
                recoverConnection(showSettings = true)
            }, weight(end = 8))
            buttons.addView(action("Kapat", surface, muted, 14, dialog::dismiss), weight())
            sheet.addView(buttons)
        }
        connectionPopup = popup
        popup.setOnDismissListener { if (connectionPopup === popup) connectionPopup = null }
    }

    private fun resetApplication() {
        cancelRecovery()
        adoptSavedSettings = false
        changePlan(stateClient::reset) { current ->
            selectedDate = LocalDate.now()
            selectedSlots.clear()
            selectedGroup = 0
            live = !SettingsStore.DEFAULT_DRY_RUN
            editingPlan = false
            activeSwitch.isChecked = true
            refreshSeconds = SettingsStore.MIN_REFRESH_SECONDS
            speedSlider.progress = 0
            showAllLogs = false
            renderedLogKey = null
            renderDates()
            renderSlots()
            renderModes()
            renderSpeed()
            (dateStrip.parent as? HorizontalScrollView)?.scrollTo(0, 0)
            (groupStrip.parent as? HorizontalScrollView)?.scrollTo(0, 0)
            dashboardScroll.post { dashboardScroll.scrollTo(0, 0) }
            toast("Takip durdu. Plan ve uygulama ayarları sıfırlandı.")
            if (current?.isBound != true) recoverConnection()
        }
    }

    private fun connectionProtectionStatus(): String = when {
        !SettingsStore.connectionProtectionEnabled(this) -> "Kapalı"
        !isSlotAccessibilityEnabled() -> "Android erişilebilirlik izni bekleniyor"
        BackgroundTrackingService.isRunning -> "Açık"
        else -> "Servis başlatılıyor"
    }

    private fun showState(current: SlotState?) {
        checkedStatus = true
        currentState = current
        if (current != null) {
            lastState = current
            if (current.isBound && connectionPopup?.isShowing == true) {
                connectionPopup?.dismiss()
                toast("Erişilebilirlik bağlantısı hazır.")
            }
            if (adoptSavedSettings) {
                adoptSavedSettings = false
                selectedDate = readDate(current.plan.date)
                live = !current.plan.dryRun
                speedSlider.progress = current.plan.refreshSeconds - SettingsStore.MIN_REFRESH_SECONDS
                renderDates()
                renderSlots()
                renderModes()
            }
        }
        renderStatus()
    }

    private fun renderStatus() {
        val current = currentState
        val shown = lastState
        val saved = shown?.plan ?: SettingsStore.defaults()
        val bound = current?.isBound == true
        val allowed = isSlotAccessibilityEnabled()
        val (label, color) = when {
            !allowed -> "Erişilebilirlik izni kapalı" to peach
            recovery != null -> "Erişilebilirlik bağlantısı yenileniyor" to sky
            !checkedStatus -> "Servis durumu kontrol ediliyor" to sky
            current == null -> "Plan durumu okunamadı" to peach
            !bound -> "Erişilebilirlik açık · servis bağlantısı kesik" to peach
            !saved.active -> "Takip duraklatıldı" to sky
            saved.dryRun -> "İzleme açık" to sky
            else -> "Canlı seçim açık" to mint
        }
        status.text = "●  $label"
        status.setTextColor(color)
        val pending = shown?.pendingRemovals ?: 0
        val hasPlan = saved.slots.isNotEmpty() || pending > 0
        planText.text = if (hasPlan) {
            val confirmed = shown?.confirmedSlots ?: 0
            val date = runCatching { LocalDate.parse(saved.date).format(shortDate) }.getOrDefault(saved.date)
            val waitingMessage = when (current?.trackingState) {
                TrackingState.WAITING_FOR_GO -> "\nTakip için Trendyol GO’yu aç."
                TrackingState.WAITING_FOR_UNLOCK -> "\nTelefon kilitsiz ve GO ekrandayken takip devam eder."
                else -> ""
            }
            val backgroundMessage = when {
                shown?.shouldRunInBackground == true && current?.backgroundRunning == true -> "\nArka plan takibi hazır"
                shown?.shouldRunInBackground == true -> "\nArka plan servisi bekleniyor"
                else -> ""
            }
            "Kayıtlı plan · $date · $confirmed/${saved.slots.size} ekranda görüldü" +
                (if (pending == 0) "" else "\n$pending kaldırma isteği bekliyor") + backgroundMessage + waitingMessage
        } else {
            "Saatlerini seçip kaydederek takibi başlat."
        }
        planEdit.visibility = if (hasPlan) View.VISIBLE else View.GONE
        stopButton.visibility = if (hasPlan && saved.active) View.VISIBLE else View.GONE
        reconnectButton.visibility = if (!allowed || !bound || recovery != null) View.VISIBLE else View.GONE
        reconnectButton.text = when {
            !allowed -> "Erişilebilirlik ayarları"
            recovery != null -> "Yenileniyor…"
            else -> "Bağlantıyı yenile"
        }
        reconnectButton.isEnabled = recovery == null
        renderLogs(shown?.history.orEmpty())
    }

    private fun renderLogs(history: String) {
        val key = history to showAllLogs
        if (key == renderedLogKey) return
        renderedLogKey = key
        logs.removeAllViews()
        val entries = EventLog.entries(history)
        moreLogs.visibility = if (entries.size > 5) View.VISIBLE else View.GONE
        moreLogs.text = if (showAllLogs) "Son beş kaydı göster" else "Tüm kayıtları göster"
        if (entries.isEmpty()) {
            logs.addView(text("İşlem kayıtları burada görünür.", 14, muted))
            return
        }
        for (entry in entries.take(if (showAllLogs) 35 else 5)) {
            val accent = when (entry.level) {
                3 -> rose
                2 -> mint
                1 -> sky
                else -> lilac
            }
            val line = vertical().apply {
                background = shape(raised, 13)
                setPadding(12.dp(), 10.dp(), 12.dp(), 10.dp())
            }
            val header = horizontal()
            header.addView(text(entry.label, 11, accent, "sans-serif-medium"), weight())
            header.addView(text(entry.timestamp, 11, muted))
            line.addView(header)
            line.addView(text(entry.message, 13, ink), block(top = 5))
            logs.addView(line, block(bottom = 7))
        }
    }

    private fun showDiagnostics() {
        val state = currentState
        val bound = state?.isBound == true
        fun time(epoch: Long): String = if (epoch == 0L) "Henüz yok"
            else Instant.ofEpochMilli(epoch).atZone(ZoneId.systemDefault()).format(timeFormatter)
        val lastExit = runCatching {
            getSystemService(ActivityManager::class.java).getHistoricalProcessExitReasons(packageName, 0, 20)
                .firstOrNull { it.processName == packageName || it.processName == "$packageName:accessibility" }
        }.getOrNull()
        val exit = lastExit?.let { info ->
            val description = info.description?.trim()?.take(220).orEmpty()
            val event = "${time(info.timestamp)} · ${exitReason(info.reason)}"
            if (description.isBlank()) event else "$event\n$description"
        } ?: "Kayıt yok"
        val connection = if (state == null) "Alınamadı" else if (bound) "Bağlı" else "Kesik"
        val allowed = isSlotAccessibilityEnabled()
        val permission = if (allowed) "Açık" else "Kapalı"
        val protected = SettingsStore.connectionProtectionEnabled(this)
        val fields = listOf(
            "Bağlantı koruması" to connectionProtectionStatus(),
            "Son bağlantı" to time(state?.lastConnection ?: 0L),
            "Son takip kontrolü" to time(state?.lastCheck ?: 0L),
            "Son ayrılma" to time(state?.lastDisconnection ?: 0L),
            "Son süreç kapanışı" to exit,
            "Son hata" to (state?.lastError ?: "Kayıt yok")
        )
        val report = (listOf("Android erişilebilirlik izni" to permission, "Servis bağlantısı" to connection) + fields)
            .joinToString("\n") { (label, value) -> "$label · $value" }

        showPopup("Servis tanısı") { sheet, dialog ->
            val stateRow = horizontal()
            stateRow.addView(popupField("Android izni", permission, if (allowed) mint else peach), weight(end = 8))
            stateRow.addView(popupField("Servis bağlantısı", connection, if (bound) mint else peach), weight())
            sheet.addView(stateRow, block(bottom = 8))
            for ((label, value) in fields) {
                sheet.addView(popupField(label, value), block(bottom = 6))
            }
            sheet.addView(action("Bağlantıyı yenile", mint, night, 14) {
                dialog.dismiss()
                recoverConnection(showSettings = true)
            }, block(top = 6, bottom = 6))
            if (protected) {
                val protectionActions = horizontal()
                if (needsNotificationPermission()) {
                    protectionActions.addView(action("Bildirim izni ver", raised, sky, 13) {
                        dialog.dismiss()
                        askForNotifications()
                    }, weight(end = 8))
                }
                protectionActions.addView(action("Korumayı durdur", raised, peach, 13) {
                    dialog.dismiss()
                    SettingsStore.setConnectionProtection(this, false)
                    BackgroundTrackingService.refresh()
                    toast("Bağlantı koruması durduruldu.")
                }, weight())
                sheet.addView(protectionActions, block(bottom = 6))
            }
            val footer = horizontal()
            footer.addView(action("Kopyala", raised, ink, 14) {
                getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText("DraBornSlot servis tanısı", report))
                dialog.dismiss()
            }, weight(end = 8))
            footer.addView(action("Kapat", surface, muted, 14, dialog::dismiss), weight())
            sheet.addView(footer)
        }
    }

    private fun exitReason(reason: Int) = when (reason) {
        ApplicationExitInfo.REASON_CRASH, ApplicationExitInfo.REASON_CRASH_NATIVE -> "Servis çöktü"
        ApplicationExitInfo.REASON_ANR -> "Servis yanıt vermedi"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "Bellek yetersiz"
        ApplicationExitInfo.REASON_USER_REQUESTED, ApplicationExitInfo.REASON_USER_STOPPED -> "Sistem veya kullanıcı durdurdu"
        ApplicationExitInfo.REASON_OTHER -> "Android işlemi sonlandırdı (kod 13)"
        else -> "Android kapanış kodu $reason"
    }

    private fun animateLaunch(frame: FrameLayout) {
        val overlay = FrameLayout(this).apply {
            background = gradient(intArrayOf(night, Color.rgb(19, 33, 79), Color.rgb(9, 49, 63)), 0)
            isClickable = true
        }
        val splash = vertical().apply {
            gravity = Gravity.CENTER
            setPadding(32.dp(), 0, 32.dp(), 0)
        }
        val logo = mark(108)
        logo.scaleX = 0.86f
        logo.scaleY = 0.86f
        logo.alpha = 0.45f
        splash.addView(logo, LinearLayout.LayoutParams(108.dp(), 108.dp()))
        splash.addView(text("DraBornSlot", 30, ink, "sans-serif-black"), LinearLayout.LayoutParams(-2, -2).apply { topMargin = 18.dp() })
        splash.addView(text("Yükleniyor", 14, muted), LinearLayout.LayoutParams(-2, -2).apply { topMargin = 6.dp() })
        val progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progressTintList = ColorStateList.valueOf(mint)
            progressBackgroundTintList = ColorStateList.valueOf(outline)
            contentDescription = "DraBornSlot yükleniyor"
        }
        splash.addView(progress, LinearLayout.LayoutParams(148.dp(), 6.dp()).apply { topMargin = 14.dp() })
        overlay.addView(splash, FrameLayout.LayoutParams(-1, -2, Gravity.CENTER))
        frame.addView(overlay, FrameLayout.LayoutParams(-1, -1))
        logo.animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(350).start()
        ObjectAnimator.ofInt(progress, "progress", 0, 100).apply { duration = 440 }.start()
        overlay.postDelayed({
            overlay.animate().alpha(0f).setDuration(160).withEndAction { frame.removeView(overlay) }.start()
        }, 440)
    }

    private fun mark(size: Int) = ImageView(this).apply {
        setImageResource(R.drawable.slot_mark)
        scaleType = ImageView.ScaleType.FIT_CENTER
        background = shape(night, size / 4)
        clipToOutline = true
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private fun heading(value: String) = text(value, 20, ink, "sans-serif-medium").apply {
        isAccessibilityHeading = true
    }

    private fun text(value: String, size: Int, color: Int, font: String = "sans-serif") = TextView(this).apply {
        text = value
        textSize = size.toFloat()
        setTextColor(color)
        setTypeface(Typeface.create(font, Typeface.NORMAL))
        includeFontPadding = false
    }

    private fun badge(value: String, color: Int, fill: Int) = text(value, 12, color, "sans-serif-medium").apply {
        setPadding(10.dp(), 7.dp(), 10.dp(), 7.dp())
        background = shape(fill, 10)
    }

    private fun action(label: String, fill: Int, color: Int, size: Int, onClick: () -> Unit) =
        text(label, size, color, "sans-serif-medium").apply {
            background = ripple(fill, 13, if (fill == surface) outline else null)
            gravity = Gravity.CENTER
            minimumHeight = 48.dp()
            setPadding(9.dp(), 8.dp(), 9.dp(), 8.dp())
            setOnClickListener { onClick() }
        }

    private fun panel() = vertical().apply {
        background = shape(surface, 19, outline)
        setPadding(14.dp(), 14.dp(), 14.dp(), 14.dp())
    }

    private fun shape(fill: Int, radius: Int, border: Int? = null) = GradientDrawable().apply {
        setColor(fill)
        cornerRadius = radius.dp().toFloat()
        if (border != null) setStroke(1.dp(), border)
    }

    private fun gradient(colors: IntArray, radius: Int) =
        GradientDrawable(GradientDrawable.Orientation.TL_BR, colors).apply { cornerRadius = radius.dp().toFloat() }

    private fun ripple(fill: Int, radius: Int, border: Int? = null) =
        RippleDrawable(ColorStateList.valueOf(Color.argb(41, 255, 255, 255)), shape(fill, radius, border), null)

    private fun horizontalScroll(child: View) = HorizontalScrollView(this).apply {
        isHorizontalScrollBarEnabled = false
        clipToPadding = false
        addView(child)
    }

    private fun vertical() = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    private fun horizontal() = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    private fun weight(end: Int = 0) = LinearLayout.LayoutParams(0, -2, 1f).apply { marginEnd = end.dp() }
    private fun block(top: Int = 0, bottom: Int = 0) = LinearLayout.LayoutParams(-1, -2).apply {
        topMargin = top.dp()
        bottomMargin = bottom.dp()
    }

    private fun Int.dp() = (this * resources.displayMetrics.density).roundToInt()
    private fun toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
}
