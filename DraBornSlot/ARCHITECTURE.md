# DraBornSlot v0.3 mimari

**Tek cihaz:** Ana arayüz (`MainActivity`) + Android `AccessibilityService`. Trendyol GO aynı cihazda **önde açık** kalır; servis onun erişilebilirlik ağacını ve izin verilen ekran görüntülerini inceler.

**Tarama:** `Handler` döngüsü 1000 ms. `takeScreenshot` için 1100 ms sınır ve Android'in `ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT` geri dönüşünde kibarca atlama. Sayfa yenileme ayrı 5–60 sn.

**Güvenli seçim:** Doğrulanmış tarih, hedef satır, satırla sınırlı yeşil `+`, `dispatchGesture`, sonrasında kırmızı `X` görseli ile *arayüz durumu*. 15 sn en az tekrar dokunma beklemesi. Red X kesin rezervasyon değildir.

**Hata dayanıklılığı:** Ana tarama ve ekran görüntüsü değerlendirmesi hata yakalar; `EventLog` yapılandırılmış kartlara çevrilir; `SettingsStore` kalp atışı ön yüzde gösterir. Bağlantı kesilirse Android yeniden servis bağlantısı gerektirebilir.

**Sınırlama:** Aygıt kilitliyken / telefon kapalıyken ekran kontrolü yok; internette slotların ne zaman yayınlandığı bilinmez; anlık yakalama garanti edilmez.
