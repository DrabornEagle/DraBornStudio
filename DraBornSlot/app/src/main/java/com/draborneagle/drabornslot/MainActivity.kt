package com.draborneagle.drabornslot

import android.app.Activity
import android.app.AlertDialog
import android.content.ComponentName
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** DraBornSlot 0.3 – single-device Android UI, clear service diagnostics. */
@Suppress("DEPRECATION")
class MainActivity : Activity() {
    private val bg = Color.rgb(8, 17, 31)
    private val card = Color.rgb(18, 32, 50)
    private val cardLift = Color.rgb(23, 44, 65)
    private val border = Color.rgb(48, 75, 101)
    private val white = Color.rgb(242, 248, 255)
    private val muted = Color.rgb(164, 185, 208)
    private val mint = Color.rgb(46, 216, 165)
    private val sky = Color.rgb(77, 190, 254)
    private val yellow = Color.rgb(255, 193, 91)
    private val rose = Color.rgb(255, 110, 138)
    private val dateFmt = DateTimeFormatter.ofPattern("d MMM", Locale("tr", "TR"))
    private val dowFmt = DateTimeFormatter.ofPattern("EEE", Locale("tr", "TR"))

    private lateinit var root: LinearLayout
    private lateinit var dateStrip: LinearLayout
    private lateinit var slotSections: LinearLayout
    private lateinit var statusText: TextView
    private lateinit var countText: TextView
    private lateinit var startButton: TextView
    private lateinit var logItems: LinearLayout
    private lateinit var intervalText: TextView
    private lateinit var liveButton: TextView
    private lateinit var testButton: TextView
    private lateinit var activeSwitch: Switch
    private var selectedDate = LocalDate.now()
    private val selectedSlots = linkedSetOf<String>()
    private var live = false
    private var interval = 10

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = bg
        window.navigationBarColor = bg
        window.decorView.systemUiVisibility = 0
        val config = SettingsStore.read(this)
        selectedDate = runCatching { LocalDate.parse(config.date) }.getOrDefault(LocalDate.now())
            .takeIf { !it.isBefore(LocalDate.now()) && !it.isAfter(LocalDate.now().plusDays(6)) } ?: LocalDate.now()
        selectedSlots.addAll(config.slots)
        live = !config.dryRun
        interval = config.refreshSeconds

        val scroll = ScrollView(this).apply { setFillViewport(true); setBackgroundColor(bg) }
        root = vertical().apply { setPadding(16.dp(), 20.dp(), 16.dp(), 28.dp()) }
        scroll.addView(root)
        setContentView(scroll)
        buildUi(config.active)
    }

    override fun onResume() {
        super.onResume()
        if (::statusText.isInitialized) refreshStatus()
    }

    private fun buildUi(active: Boolean) {
        val brand = horizontal().apply { gravity = Gravity.CENTER_VERTICAL }
        brand.addView(text("◉", 28, mint, true))
        brand.addView(text("  DraBornSlot", 25, white, true), LinearLayout.LayoutParams(0, -2, 1f))
        brand.addView(pill("v0.3", mint, Color.rgb(12, 61, 58), 12))
        root.addView(brand)
        root.addView(text("SLOT KONTROL MERKEZİ", 11, muted, true).apply { letterSpacing = 0.18f }, pad(top = 3, bottom = 15))

        val hero = vertical().apply {
            setPadding(18.dp(), 17.dp(), 18.dp(), 17.dp())
            background = GradientDrawable(GradientDrawable.Orientation.TL_BR, intArrayOf(Color.rgb(19, 67, 80), Color.rgb(26, 44, 83))).apply { cornerRadius = 22.dp().toFloat() }
        }
        hero.addView(text("●  AKILLI TAKİP", 12, mint, true))
        hero.addView(text("Tek telefondan slot takibi", 21, white, true), pad(top = 7))
        hero.addView(text("Trendyol GO öndeyken ekran 1 saniyede bir kontrol edilir. Telefon kilitliyken işlem yapılamaz.", 12, Color.rgb(204, 226, 239), false), pad(top = 5))
        val heroStats = horizontal().apply { gravity = Gravity.CENTER_VERTICAL; setPadding(0, 15.dp(), 0, 0) }
        countText = text("", 16, white, true)
        heroStats.addView(countText, LinearLayout.LayoutParams(0, -2, 1f))
        statusText = text("", 11, sky, true)
        heroStats.addView(statusText)
        hero.addView(heroStats)
        root.addView(hero, pad(bottom = 10))
        root.addView(pill("●  1 sn ekran kontrolü    ●  Tek Android cihaz", sky, Color.rgb(18, 35, 54), 11), pad(bottom = 18))

        root.addView(sectionHeader("01", "Çalışma günü", "Bugünden itibaren 7 gün"))
        dateStrip = horizontal().apply { gravity = Gravity.CENTER_VERTICAL }
        val dateScroll = HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(dateStrip) }
        root.addView(dateScroll, pad(bottom = 18))
        updateDateStrip()

        val topRow = horizontal().apply { gravity = Gravity.CENTER_VERTICAL }
        topRow.addView(sectionHeader("02", "Saat tercihleri", "En fazla 8 seçim"), LinearLayout.LayoutParams(0, -2, 1f))
        val selectAll = pill("Temizle", rose, Color.rgb(69, 34, 52), 11).apply {
            setOnClickListener { selectedSlots.clear(); updateSlots(); updateCount() }
        }
        topRow.addView(selectAll)
        root.addView(topRow)
        root.addView(text("Saatleri tek dokunuşla seç. 00:00 sonrası aralıklar da dahil.", 12, muted), pad(bottom = 11))
        slotSections = vertical()
        root.addView(slotSections, pad(bottom = 18))
        updateSlots()

        root.addView(sectionHeader("03", "Otomasyon ayarları", "Çalıştırma kontrolü"))
        val controlCard = panel()
        controlCard.addView(text("ÇALIŞMA MODU", 11, muted, true))
        val modeRow = horizontal().apply { gravity = Gravity.CENTER_VERTICAL }
        testButton = modeChoice("◌  İzleme", false)
        liveButton = modeChoice("⚡  Canlı seçim", true)
        modeRow.addView(testButton, LinearLayout.LayoutParams(0, 46.dp(), 1f).apply { rightMargin = 8.dp() })
        modeRow.addView(liveButton, LinearLayout.LayoutParams(0, 46.dp(), 1f))
        controlCard.addView(modeRow, pad(top = 8, bottom = 10))
        controlCard.addView(text("Canlı mod seçiliyse Trendyol GO öndeyken yeşil + butonuna dokunulur. Kırmızı X yalnızca ekranda seçildiğini gösterir; kaydı ayrıca doğrula.", 12, muted), pad(bottom = 14))
        val swRow = horizontal().apply { gravity = Gravity.CENTER_VERTICAL }
        swRow.addView(text("Ajanı etkinleştir", 15, white, true), LinearLayout.LayoutParams(0, -2, 1f))
        activeSwitch = Switch(this).apply { isChecked = active; thumbTintList = android.content.res.ColorStateList.valueOf(mint) }
        swRow.addView(activeSwitch)
        controlCard.addView(swRow)
        controlCard.addView(divider(), LinearLayout.LayoutParams(-1, 1.dp()).apply { topMargin = 10.dp(); bottomMargin = 13.dp() })
        controlCard.addView(text("GÖRÜNÜR EKRAN TARAMASI", 11, sky, true))
        controlCard.addView(text("Her 1 saniyede kontrol (Android sınırları içinde)", 12, white), pad(bottom = 12))
        intervalText = text("Sayfayı yenile: ${interval} sn", 13, white, true)
        controlCard.addView(intervalText)
        val seek = SeekBar(this).apply {
            max = 11
            progress = ((interval - 5) / 5).coerceIn(0, 11)
            progressTintList = android.content.res.ColorStateList.valueOf(mint)
            thumbTintList = android.content.res.ColorStateList.valueOf(mint)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    interval = 5 + progress * 5
                    intervalText.text = "Sayfayı yenile: ${interval} sn"
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
                override fun onStopTrackingTouch(seekBar: SeekBar?) = Unit
            })
        }
        controlCard.addView(seek)
        controlCard.addView(text("5 sn (hızlı)                      60 sn (seyrek)", 10, muted))
        controlCard.addView(text("Not: 1 saniyelik tarama, sunucudan her saniye yeni slot bilgisi alınacağı anlamına gelmez.", 11, muted), pad(top = 10))
        root.addView(controlCard, pad(bottom = 15))
        setModeButtons()

        startButton = action("✓  KAYDET VE UYGULA", mint, bg) { save() }
        root.addView(startButton, pad(bottom = 9))
        root.addView(action("↗  TRENDYOL GO'YU AÇ", cardLift, white) {
            val target = packageManager.getLaunchIntentForPackage("com.orangemobile")
            if (target == null) toast("Trendyol GO yüklü değil") else startActivity(target)
        }, pad(bottom = 9))
        root.addView(action("⚙  ERİŞİLEBİLİRLİK AYARLARI", cardLift, white) {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }, pad(bottom = 18))

        root.addView(sectionHeader("04", "İşlem geçmişi", "Son 35 kayıt • Son olay en üstte"))
        val logCard = panel()
        logCard.addView(text("Durumlar: TARAMA → DOKUNMA → SEÇİM GÖRÜLDÜ. Hata varsa kırmızı gösterilir.", 12, muted), pad(bottom = 12))
        logItems = vertical()
        logCard.addView(logItems)
        logCard.addView(action("↻  KAYITLARI YENİLE", cardLift, sky) { refreshStatus() }, pad(top = 12))
        root.addView(logCard, pad(bottom = 15))
        root.addView(text("Tek telefon: DraBornSlot arka planda, Trendyol GO önde olmalı. Android ekran kilidindeyken veya telefon kapalıyken erişilebilirlik işlemi yapılamaz. Platform kurallarını kontrol et.", 11, muted))
        updateCount()
        refreshStatus()
    }

    private fun updateDateStrip() {
        dateStrip.removeAllViews()
        (0..6).forEach { n ->
            val date = LocalDate.now().plusDays(n.toLong())
            val selected = date == selectedDate
            val chip = vertical().apply {
                gravity = Gravity.CENTER
                setPadding(15.dp(), 10.dp(), 15.dp(), 10.dp())
                background = shape(if (selected) mint else card, 15, if (selected) mint else border)
                addView(text(date.format(DateTimeFormatter.ofPattern("dd")), 19, if (selected) bg else white, true).apply { gravity = Gravity.CENTER })
                addView(text(date.format(dowFmt).uppercase(Locale("tr", "TR")), 11, if (selected) bg else muted, true).apply { gravity = Gravity.CENTER })
                setOnClickListener { selectedDate = date; updateDateStrip(); updateCount() }
            }
            dateStrip.addView(chip, LinearLayout.LayoutParams(63.dp(), 66.dp()).apply { rightMargin = 8.dp() })
        }
    }

    private fun updateSlots() {
        slotSections.removeAllViews()
        val sections = listOf(
            "SABAH" to (8 until 12).flatMap { hourSlots(it) },
            "ÖĞLE" to (12 until 17).flatMap { hourSlots(it) },
            "AKŞAM" to (17 until 23).flatMap { hourSlots(it) },
            "GECE" to listOf("23:00-23:30", "23:30-23:59", "00:00-00:30", "00:30-01:00")
        )
        for ((title, slots) in sections) {
            val label = text(title, 11, sky, true).apply { letterSpacing = 0.12f }
            slotSections.addView(label, pad(top = 8, bottom = 7))
            var index = 0
            while (index < slots.size) {
                val row = horizontal()
                for (j in 0..1) {
                    val pos = index + j
                    if (pos >= slots.size) {
                        row.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))
                        continue
                    }
                    val slot = slots[pos]
                    val chosen = slot in selectedSlots
                    val tile = horizontal().apply {
                        gravity = Gravity.CENTER_VERTICAL
                        setPadding(11.dp(), 12.dp(), 8.dp(), 12.dp())
                        background = shape(if (chosen) Color.rgb(20, 70, 64) else card, 13, if (chosen) mint else border)
                    }
                    tile.addView(text(if (chosen) "✓" else "+", 17, if (chosen) mint else muted, true), inlinePad(7))
                    tile.addView(text(slot.replace("-", " – "), 12, if (chosen) mint else white, true), LinearLayout.LayoutParams(0, -2, 1f))
                    tile.setOnClickListener {
                        if (chosen) selectedSlots.remove(slot)
                        else if (selectedSlots.size >= 8) toast("En fazla 8 saat seçebilirsin")
                        else selectedSlots.add(slot)
                        updateSlots(); updateCount()
                    }
                    row.addView(tile, LinearLayout.LayoutParams(0, 48.dp(), 1f).apply { if (j == 0) rightMargin = 8.dp() })
                }
                slotSections.addView(row, pad(bottom = 8))
                index += 2
            }
        }
    }

    private fun hourSlots(hour: Int): List<String> {
        val h = "%02d".format(Locale.US, hour)
        val next = "%02d".format(Locale.US, (hour + 1) % 24)
        return listOf("$h:00-$h:30", "$h:30-$next:00")
    }

    private fun save() {
        if (selectedSlots.isEmpty()) { toast("Önce en az bir saat seç"); return }
        val config = SettingsStore.Config(activeSwitch.isChecked, !live, selectedDate.toString(), selectedSlots.toList(), interval)
        SettingsStore.save(this, config)
        EventLog.write(this, "v0.3 ayarlar kaydedildi: ${config.date}, ${config.slots.size} slot, ${if (live) "CANLI" else "İZLEME"}; tarama 1 sn, yenileme ${interval} sn")
        toast(if (live) "Canlı mod kaydedildi. Trendyol GO saat ekranını aç." else "İzleme tercihleri kaydedildi")
        refreshStatus()
    }

    private fun setModeButtons() {
        for ((view, chosen, accent) in listOf(Triple(testButton, !live, sky), Triple(liveButton, live, yellow))) {
            view.background = shape(if (chosen) Color.rgb(32, 65, 84) else cardLift, 12, if (chosen) accent else border)
            view.setTextColor(if (chosen) accent else muted)
        }
    }

    private fun modeChoice(caption: String, isLive: Boolean) = text(caption, 13, white, true).apply {
        gravity = Gravity.CENTER
        setOnClickListener {
            if (isLive && !live) {
                AlertDialog.Builder(this@MainActivity)
                    .setTitle("Canlı seçim etkinleştirilsin mi?")
                    .setMessage("DraBornSlot artık Trendyol GO'daki uygun slotların + butonlarına dokunmayı deneyebilir. Bu platformun koşullarına uygun olmalı; slotların kesin alındığını garanti etmez. Açmak istiyor musun?")
                    .setNegativeButton("Vazgeç", null)
                    .setPositiveButton("Canlı modu aç") { _, _ -> live = true; setModeButtons() }
                    .show()
            } else { live = isLive; setModeButtons() }
        }
    }

    private fun refreshStatus() {
        val enabled = (Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: "")
            .split(':').any { it.equals(ComponentName(this, SlotAccessibilityService::class.java).flattenToString(), true) }
        val saved = SettingsStore.read(this)
        val heartbeat = SettingsStore.lastHeartbeat(this)
        val alive = enabled && heartbeat > 0L && System.currentTimeMillis() - heartbeat < 9_000L
        statusText.text = when {
            !enabled -> "● İzin kapalı"
            !alive -> "● Servis yanıt vermiyor"
            !saved.active -> "● Ajan duraklatıldı"
            saved.dryRun -> "● İzleme aktif"
            else -> "● Canlı mod aktif"
        }
        statusText.setTextColor(if (alive && saved.active) mint else yellow)
        updateLogCards()
    }

    private fun updateLogCards() {
        if (!::logItems.isInitialized) return
        logItems.removeAllViews()
        val records = EventLog.entries(this)
        if (records.isEmpty()) {
            logItems.addView(text("Henüz işlem yok. Trendyol GO saat ekranını açtığında tarama başlayacak.", 12, muted))
            return
        }
        for ((position, item) in records.withIndex()) {
            val accent = when (item.level) {
                3 -> rose
                2 -> mint
                1 -> sky
                else -> muted
            }
            val itemPanel = vertical().apply {
                setPadding(12.dp(), 10.dp(), 12.dp(), 10.dp())
                background = shape(Color.rgb(23, 42, 61), 11, border)
            }
            val metaRow = horizontal().apply { gravity = Gravity.CENTER_VERTICAL }
            metaRow.addView(pill(item.label, accent, Color.rgb(35, 55, 72), 10), LinearLayout.LayoutParams(0, -2, 1f).apply { rightMargin = 8.dp() })
            metaRow.addView(text(item.timestamp, 10, muted))
            itemPanel.addView(metaRow)
            itemPanel.addView(text(item.message, 12, white), pad(top = 7))
            logItems.addView(itemPanel, pad(bottom = if (position == records.lastIndex) 0 else 8))
        }
    }

    private fun updateCount() { if (::countText.isInitialized) countText.text = "${selectedSlots.size} / 8 hedef saat" }
    private fun sectionHeader(number: String, title: String, detail: String): View {
        val row = horizontal().apply { gravity = Gravity.CENTER_VERTICAL }
        row.addView(pill(number, sky, Color.rgb(20, 48, 70), 11), inlinePad(9))
        val labels = vertical().apply {
            addView(text(title, 17, white, true))
            addView(text(detail, 11, muted))
        }
        row.addView(labels)
        row.setPadding(0, 0, 0, 10.dp())
        return row
    }
    private fun panel() = vertical().apply { background = shape(card, 18, border); setPadding(15.dp(), 15.dp(), 15.dp(), 15.dp()) }
    private fun text(value: String, size: Int, color: Int, bold: Boolean = false) = TextView(this).apply {
        text = value
        textSize = size.toFloat()
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        includeFontPadding = true
    }
    private fun pill(value: String, color: Int, fill: Int, size: Int) = text(value, size, color, true).apply {
        gravity = Gravity.CENTER
        setPadding(10.dp(), 6.dp(), 10.dp(), 6.dp())
        background = shape(fill, 10)
    }
    private fun action(title: String, fill: Int, ink: Int, click: () -> Unit) = text(title, 14, ink, true).apply {
        gravity = Gravity.CENTER
        background = shape(fill, 14)
        setPadding(8.dp(), 16.dp(), 8.dp(), 16.dp())
        setOnClickListener { click() }
    }
    private fun shape(fill: Int, radius: Int, stroke: Int? = null) = GradientDrawable().apply {
        setColor(fill); cornerRadius = radius.dp().toFloat()
        if (stroke != null) setStroke(1.dp(), stroke)
    }
    private fun divider() = View(this).apply { setBackgroundColor(border); layoutParams = LinearLayout.LayoutParams(-1, 1.dp()) }
    private fun vertical() = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    private fun horizontal() = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
    private fun inlinePad(right: Int) = LinearLayout.LayoutParams(-2, -2).apply { rightMargin = right.dp() }
    private fun pad(top: Int = 0, bottom: Int = 0, right: Int = 0) = LinearLayout.LayoutParams(-1, -2).apply {
        topMargin = top.dp(); bottomMargin = bottom.dp(); rightMargin = right.dp()
    }
    private fun Int.dp() = (this * resources.displayMetrics.density).toInt()
    private fun toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_LONG).show()
}
