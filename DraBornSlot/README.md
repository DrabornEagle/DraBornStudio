# DraBornSlot v0.3 — Tek telefonda slot ekranı ajanı

Android Kotlin + AccessibilityService ile Trendyol GO uygulamasının **görünür** saat ekranını kullanıcının açık izniyle izlemek ve hedef saatler için yeşil `+` tuşlarına dokunmayı denemek üzere hazırlanmıştır.

## Yeni
- Ekran kontrolü yaklaşık **1 saniye aralıklarla**; Android'in ekran görüntüsü hız sınırlamalarına uyar. Bu **1 saniyede sunucudan slot çekileceği** anlamına gelmez.
- Sayfayı yenileme aralığı **5–60 saniye** olarak ayrı kontrol edilir (varsayılan 10 saniye).
- Artık **iki başarısız girişimden sonra kalıcı engelleme** yok; 15 saniyelik en az deneme aralığı var.
- Seçili gün başlığı aşağı kaydırılıp görünmez olduğunda aynı uygulama oturumundaki doğrulanmış tarih korunur. Uygulama değişince tarih doğrulaması sıfırlanır.
- Yeşil `+` ve kırmızı `X` görsel taraması **ilgili satırla sınırlandırıldı**.
- Son 35 kayıt, renkli sınıflandırılmış işlem kartlarıyla gösterilir.
- Erişilebilirlik hizmeti ana ekranında bir **kalp atışı** kontrolü yapılır. Android izin anahtarı açık fakat servis çalışmıyorsa bu ayrımı gösterir.
- Günler: bugünden itibaren 7 gün; slotlar 08:00 ile 23:59 arasında ve sonraki 00:00–01:00 dilimi; 8 hedef slot.

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
