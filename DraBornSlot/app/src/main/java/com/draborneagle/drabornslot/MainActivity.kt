package com.draborneagle.drabornslot

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.provider.Settings
import android.text.InputType
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.time.LocalDate
import java.time.temporal.ChronoUnit

@Suppress("DEPRECATION")
class MainActivity : Activity() {
    private lateinit var dateEdit: EditText
    private lateinit var slotsEdit: EditText
    private lateinit var intervalEdit: EditText
    private lateinit var activeSwitch: Switch
    private lateinit var dryRunSwitch: Switch
    private lateinit var status: TextView
    private lateinit var logs: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(16, 23, 29)
        window.navigationBarColor = Color.rgb(16, 23, 29)
        val settings = SettingsStore.read(this)
        val scroll = ScrollView(this)
        val stack = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(20.dp(), 20.dp(), 20.dp(), 28.dp())
            setBackgroundColor(Color.rgb(247, 250, 248))
        }
        scroll.addView(stack)
        setContentView(scroll)

        stack.addView(label("DraBornSlot v0.1", 27, true))
        stack.addView(label("7/24 özel Android cihazında çalışan slot agent", 13, false))
        stack.addView(label("Tarih (YYYY-AA-GG)", 15, true))
        dateEdit = field(settings.date, 1)
        stack.addView(dateEdit)
        stack.addView(label("İstenen 30 dakikalık slotlar (satır başına bir adet, en çok 8)", 15, true))
        slotsEdit = field(settings.slots.joinToString("\n"), 6).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        }
        stack.addView(slotsEdit)
        stack.addView(label("Sayfayı yenileme aralığı (15–300 sn)", 15, true))
        intervalEdit = field(settings.refreshSeconds.toString(), 1).apply {
            inputType = InputType.TYPE_CLASS_NUMBER
        }
        stack.addView(intervalEdit)
        activeSwitch = Switch(this).apply {
            text = "Agent etkin (açıkça izin ver)"
            isChecked = settings.active
        }
        stack.addView(activeSwitch)
        dryRunSwitch = Switch(this).apply {
            text = "Test modu: Tıklama yapmadan algıla"
            isChecked = settings.dryRun
        }
        stack.addView(dryRunSwitch)
        stack.addView(button("Ayarları kaydet") { save() })
        stack.addView(button("Erişilebilirlik iznini aç") {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        })
        stack.addView(button("Trendyol GO'yu aç") {
            val launch = packageManager.getLaunchIntentForPackage("com.orangemobile")
            if (launch == null) toast("Trendyol GO bulunamadı.") else startActivity(launch)
        })
        stack.addView(button("Bu günün deneme sayaçlarını sıfırla") {
            SettingsStore.clearAttempts(this, dateEdit.text.toString().trim())
            EventLog.write(this, "Kullanıcı deneme sayaçlarını sıfırladı.")
            updateStatus()
        })
        status = label("", 14, true)
        stack.addView(status)
        stack.addView(label("İşlem kayıtları (son 100)", 16, true))
        stack.addView(button("Kayıtları yenile") { updateStatus() })
        logs = label("", 12, false)
        stack.addView(logs)
        stack.addView(label(
            "ÖNEMLİ: Ana telefon kapalı olabilir; bu uygulamanın kurulu olduğu ikinci cihazın " +
                "açık, kilidi çözülmüş, Trendyol GO saatler ekranında ve şarjda kalması gerekir. " +
                "Test modu varsayılan olarak açıktır. Otomasyonun platform kurallarına uygun olduğundan emin ol.", 12, false
        ))
        updateStatus()
    }

    override fun onResume() {
        super.onResume()
        if (::status.isInitialized) updateStatus()
    }

    private fun save() {
        val date = dateEdit.text.toString().trim()
        val parsedDate = try { LocalDate.parse(date) } catch (_: Exception) { null }
        if (parsedDate == null) { toast("Tarih biçimi YYYY-AA-GG olmalı."); return }
        val days = ChronoUnit.DAYS.between(LocalDate.now(), parsedDate)
        if (days !in 0..6) { toast("v0.1: Bugün ile 6 gün sonrası arasını seç."); return }
        val rawLines = slotsEdit.text.toString().lines().filter { it.isNotBlank() }
        val slots = SettingsStore.slotLines(slotsEdit.text.toString())
        if (slots.isEmpty() || slots.size != rawLines.size || slots.size > 8) {
            toast("Her satıra ör. 08:00-08:30 yaz. En fazla 8 farklı slot seç.")
            return
        }
        val rawInterval = intervalEdit.text.toString().toIntOrNull() ?: 15
        val interval = rawInterval.coerceIn(15, 300)
        SettingsStore.save(this, SettingsStore.Config(activeSwitch.isChecked, dryRunSwitch.isChecked, date, slots, interval))
        EventLog.write(this, "Tercihler kaydedildi: $date, ${slots.size} slot; " +
            (if (dryRunSwitch.isChecked) "TEST" else "CANLI") + ".")
        toast("Tercihler kaydedildi. Agent ayarları okuyacak.")
        updateStatus()
    }

    private fun updateStatus() {
        val accessibility = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
        val component = ComponentName(this, SlotAccessibilityService::class.java).flattenToString()
        val enabled = accessibility.split(':').any { it.equals(component, ignoreCase = true) }
        status.text = "Erişilebilirlik servisi: ${if (enabled) "AÇIK" else "KAPALI"}\n" +
            "Agent: ${if (SettingsStore.read(this).active) "ETKİN" else "DURDURULDU"}\n" +
            "Not: İşlem kayıtları rezervasyon onayı değil, deneme bilgisidir."
        logs.text = EventLog.read(this)
    }

    private fun button(text: String, onClick: () -> Unit) = Button(this).apply {
        this.text = text
        setOnClickListener { onClick() }
    }

    private fun label(text: String, size: Int, bold: Boolean) = TextView(this).apply {
        this.text = text
        textSize = size.toFloat()
        setTextColor(Color.rgb(22, 30, 27))
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setPadding(0, 9.dp(), 0, 9.dp())
    }

    private fun field(text: String, lines: Int) = EditText(this).apply {
        setText(text)
        minLines = lines
        maxLines = lines
        setSingleLine(lines == 1)
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
    }

    private fun toast(text: String) = Toast.makeText(this, text, Toast.LENGTH_LONG).show()
    private fun Int.dp(): Int = (this * resources.displayMetrics.density).toInt()
}
