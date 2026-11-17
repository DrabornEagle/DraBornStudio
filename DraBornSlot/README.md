# DraBornSlot v0.4

Android Kotlin + AccessibilityService ile Trendyol GO uygulamasının **görünür** saat ekranını kullanıcının açık izniyle izlemek ve hedef saatler için yeşil `+` tuşlarına dokunmayı denemek üzere hazırlanmıştır.

## Kurulum
1. APK'yi Android 11+ cihaza yükle. v0.2 ile aynı uygulama kimliği ve GitHub Actions debug imzası kullanılır; imza farklıysa mevcut uygulamayı kaldırmadan önce tercihlerini not al.
2. Android ayarlarından DraBornSlot erişilebilirlik iznini ver.
3. Xiaomi/HyperOS cihazlarında uygulamaya arka plan çalıştırma izni ve uygun pil kısıtlaması istisnası tanımla.
4. DraBornSlot'ta tarih, saatler ve canlı modu seçip **KAYDET VE UYGULA** düğmesine bas.
5. **Aynı telefonda** Trendyol GO'yu aç; doğru tarihi ve tüm saatler ekranını göster. Ekranı açık ve kilitsiz tut.
6. Kayıtları incelemek için DraBornSlot'a dön; ardından tekrar Trendyol GO'ya geç.

## Sınırlamalar
- Telefon ekranı kilitliyken, cihaz kapalıyken veya uygulama başka bir ekrandayken görünür ekran otomasyonu işlemez.
- 1 saniyelik lokal kontrol, ağdaki slot açılışını aynı saniyede yakalamayı **garanti etmez**.
- Kırmızı `X` yalnızca arayüz işaretidir, rezervasyonun kesinleştiğini kanıtlamaz; **Kayıtlı Saatler** ile ayrıca doğrula.
- Trendyol GO'nun kullanıcı sözleşmesine uygunluk değerlendirmesi kullanıcı sorumluluğundadır; özel API / kimlik doğrulama atlatma yok.
- İşlem günlüğü hata, dokunma denemesi ve ekranda görülen seçimi ayırır; Android'de `Bu hizmet hatalı çalışıyor` uyarısı devam ederse **ADB logcat** ile istisna kaydı gerekir. Bu sürüm gerçek cihazda tam doğrulanmış değildir.


## v0.4 – Seçili saat koruması ve kullanıcı kontrollü kaldırma

- Yeşil `+` ve kırmızı `X` algılama alanı daraltıldı. İstenen bir saat kırmızı X gösteriyorsa bu satırdaki X'e dokunulmaz.
- Aynı gün daha önce kaydedilmiş hedef saati DraBornSlot'tan kaldırıp **Kaydet ve Uygula** dersen, yalnızca o saat için kaldırma isteği saklanır. Canlı modda Trendyol GO'nun doğru günü ve saat satırı görünüyorsa kırmızı X'e dokunulabilir. Yeşil + görülünce istek tamamlanır.
- Tarih değiştirmek, önceki tarihteki saatleri kaldırma isteği oluşturmaz.
- Yenileme aralığı artık **1–60 saniye**; v0.4'e ilk geçişte 1 sn. Sayfa yalnızca "Sayfayı Yenile" görünürken, seçim/kaldırma dokunuşlarıyla çakışmadan yenilenir.
- 1 saniye tarama veya yenileme, bir slotu açıldığı anda alma garantisi sağlamaz. Başka saatlere kaydırıldığında yenileme düğmesi görünmeyebilir.
- Kırmızı X kesin rezervasyon onayı değildir; Trendyol GO Kayıtlı Saatler ekranını kontrol et. Platformun otomasyon politikasına uyulmalıdır.
