# DraBornSlot v0.2 — Android Slot Kontrol Merkezi

DraBornSlot, kullanıcının bizzat seçip etkinleştirdiği saatleri **Trendyol GO'nun görünür uygulama ekranı** üzerinden kontrol eden Android erişilebilirlik otomasyonu. Resmî Trendyol GO API bağlantısı yoktur. Bu sürüm canlı tıklama yapabilen **deneysel** bir yapı sunar; gerçek hesapta uçtan uca rezervasyon onayı henüz doğrulanmamıştır.

## Yeni arayüz
- Modern koyu lacivert / mint / mavi tasarım; panel, durum göstergesi ve daha okunur işlem geçmişi.
- Önümüzdeki 7 gün için seçilebilir tarih kartları.
- 30 dakikalık dokun-seç slotlar, 08:00–23:30 arası, **23:30–23:59** dahil ve uygulama ekranındaki gibi **00:00–00:30 / 00:30–01:00** gece yarısı aralıkları.
- En fazla 8 slot; seçilenler yeşil renkte. Önceden kaydedilen tercihleri korur.
- Güncelleme aralığı için 15–300 saniyelik kaydırıcı (1 saniye girilmesi artık mümkün değil).
- İzleme modu / açık onay sonrası Canlı seçim modu.
- Erişilebilirlik durumunu gösterir; uygulama olay kayıtlarını saklar.

## Canlı mod ve sınırlamalar

1. DraBornSlot'u erişilebilirlik servisi üzerinden aç; oturum açılmış Trendyol GO'da *Tüm Saatler* ekranını aç.
2. Gün ve saatleri seç. **Canlı seçim** bölümünü açıp onayla; ajan anahtarını etkinleştir ve **Kaydet ve Uygula**'ya bas.
3. İkinci Android cihaz açık, şarjda, ekranı kilitsiz, Trendyol GO ön planda kalsın. **Ana telefonun kapalı olabilir**, ancak ajan cihazı kapalı olamaz.
4. Canlı mod yalnızca görünür ve yeşil `+` olan hedef slotlara dokunur. Kırmızı `X` görünürse bunu arayüz düzeyinde seçildi olarak kaydeder; kesin rezervasyon onayı için Trendyol GO **Kayıtlı Saatler** sekmesini elle kontrol et.
5. Ekran dışındaki tercihler için kontrollü dikey kaydırma yapmayı dener. Bu davranış tüm telefonlarda doğrulanmamıştır. Android arka plan, kilit, batarya ve üretici sınırlarına tabidir.

**Önemli:** Otomasyon platformun hizmet koşulları ile uyumlu olmalıdır. CAPTCHA, 2FA, rate-limit ya da erişim engeli aşma, özel API'lere bağlanma, token/cookie alma yoktur. Ajanın telefon kapalıyken aynı telefonda çalışması mümkün değildir. Rezervasyon garantisi verilmez.

## APK

GitHub Actions üzerinden Gradle 8.9 + JDK 17 + Android SDK 35 ile debug APK derlenir. GitHub Release dosyası **DraBornSlot-v0.2-debug.apk** adıyla yayımlanır. Derleme tamamlandıktan sonra `https://github.com/DrabornEagle/DraBornStudio/releases/tag/drabornslot-v0.2` bağlantısından indirilebilir.

## Teknik notlar

- Paket adı: `com.draborneagle.drabornslot`
- Min SDK: 30, target SDK: 35.
- Kod: Kotlin, platform Android Views, AccessibilityService, Screenshot API, GestureDescription.
- Ses, fotoğraf, hesap şifresi ya da gizli session verisi bir sunucuya gönderilmez.
- Ekran görüntüsü örnekli algılayıcı, telefonların erişilebilirlik metin ağacına bağlıdır; görünmeyen slotlar için resmî API mevcut değildir.
