# DraBornSlot v0.1 — Android Slot Agent (Deneysel MVP)

DraBornSlot, **yalnızca kullanıcının açıkça etkinleştirdiği**, ayrı bir Android cihaz üzerinde çalışan ve Trendyol GO (`com.orangemobile`) saatler ekranındaki seçili saatleri algılamaya çalışan yerel bir otomasyon aracıdır.

> **Durum:** Kaynak kodlu, derlenmek üzere hazırlanmış **deneysel prototip**. Gerçek cihazda Trendyol GO'nun erişilebilirlik ağacı ile uçtan uca test edilmedi; rezervasyon garantisi yoktur. APK bu pakette yer almaz. GitHub Actions ile derlenir.

## 1. Tam otomatik kullanım için gerekli mimari

- **Ana telefon:** Kapalı kalabilir.
- **İkinci Android telefon/tablet:** Android 11+ (API 30+), sürekli şarj ve Wi-Fi, ekranı açık, kilidi çözülmüş.
- İkinci cihazda **Trendyol GO** hesabına manuel giriş yapılmış ve **Tüm Saatler** sayfası açık olmalıdır.
- **DraBornSlot** ikinci cihaza yüklenir, erişilebilirlik servisi sistem ayarlarından kullanıcı tarafından açılır.
- Canlı otomasyonun desteklenmesi Trendyol'un kullanım şartlarına ve arayüzün gerçek erişilebilirlik yapısına bağlıdır.

Bu yaklaşım, uygulamayı kilitli ekranda çalıştırmaz; ana telefonun kapalı kalması **başka bir cihazın açık olmasıyla** sağlanır. Sunucu üzerinden doğrudan Trendyol API erişimi **yoktur**, iddia edilmez.

## 2. APK derleme (Android Studio yerine GitHub Actions)

1. Bu ZIP dosyasının **içeriğini** yeni, tercihen özel bir GitHub deposuna yükle (zip'i tek dosya olarak değil, klasör yapısıyla açarak).
2. GitHub'da **Actions → Build DraBornSlot debug APK → Run workflow**.
3. İşlem başarılıysa aynı iş akışının **Artifacts** bölümünde `DraBornSlot-v0.1-debug-APK` dosyasını indir.
4. İkinci Android cihaza APK'yı kur. APK, Debug imzalıdır; yalnızca kişisel test için tasarlanmıştır.

Gradle yapılandırması AGP 8.7.3, Kotlin 1.9.25, JDK 17, SDK 35, Gradle 8.9 kullanır. İnternet erişimi olan bir Android Studio ortamında `gradle :app:assembleDebug` de çalıştırılabilir.

## 3. İlk kurulum

1. İkinci cihazda Trendyol GO'yu kur ve **manuel** giriş yap. Kendi telefonundan değil, bu cihazdan işlem yapılacaktır.
2. Ekranın uykuya geçmemesini sağla; geliştirici seçeneklerindeki **şarjdayken ekran açık kalsın** seçeneği cihaz destekliyorsa kullanılabilir. Android üreticisi güç yönetimi kısıtlamalarını ayrı yapılandırmak gerekebilir.
3. DraBornSlot'ta gelecek **0–6 gün** aralığında bir tarih belirle (`2026-11-18` gibi).
4. Her satıra bir saat yaz: `08:00-08:30`. En çok 8 slot. `+` tıklamaları bu 8 slot için yapılabilir.
5. `Agent etkin` seçeneğini aç. **Test modu açık kalsın.** Kaydet.
6. Sistem Ayarları → Erişilebilirlik → DraBornSlot slot ekranı otomasyonu → **Etkinleştir**.
7. Trendyol GO'da tarih ve **Tüm Saatler** ekranını açık bırak; mümkünse önce tercih edilen tarihi elle seç.
8. Test logunda `TEST: ... için yeşil + algılandı` yazarsa ekran eşleştirmesi başarılı olmuştur.
9. Yalnızca kendine ait hesapta, platform kuralları ve yetkilerin uygunsa `Test modu`nu kapatıp ayarları kaydet.
10. Gerçek seçim için loglarda `SEÇİM DENEMESİ` ibaresi görünür. **Bu onay değildir**; Trendyol'un `Kayıtlı Saatler` sekmesinden sonucu kontrol et.

## 4. İşleyiş

- Android `AccessibilityService`, yalnızca `com.orangemobile` uygulamasının erişilebilirlik olaylarını dinler.
- Tercih edilen gün görünür tarih şeridinde değilse hiçbir seçim yapılmaz.
- Sürüm 0.1 yalnızca güncel 7 günlük aralıkla sınırlıdır; tarih şeridi kaydırma yoktur.
- Görüntüden **siyah seçili tarih kartı** ve her slotun sağındaki **yeşil/beyaz + butonu** doğrulanır. Doğrulama başarısız olursa **tıklama yapılmaz**.
- Canlı modda `Sayfayı Yenile` yazısı bulunursa 15–300 saniye aralığında sayfa yenileme dokunuşu yapılır.
- Slot için bir defada tek dokunuş yapılır, ardından yeni ekran görüntüsü okunur. Slot başına en fazla 2 otomatik dokunma denemesi kayıt altına alınır.
- `TEST` modunda **hiçbir dokunma yapılmaz**, sadece algılama kayıtları tutulur.
- Kullanıcı adı/şifre, cookie, session token, SMS, ekran görüntüsü veya kişisel veri internete gönderilmez. Projede ağ izni yoktur.

## 5. Sınırlar ve sonraki sürüm

**v0.1'de olmayanlar:** Trendyol hesabına giriş, kilidi otomatik açma, telefon kapalıyken *aynı cihazda* çalışma, resmi/özel API entegrasyonu, çoklu gün dinamik kaydırma, uzaktan yönetim, slotun kesin kaydedildiğini sunucu tarafından doğrulama, otomatik güncelleme, otomatik CAPTCHA/2FA çözme.

**v0.2 için öneri:** Gerçek cihazdan kullanıcı izniyle elde edilen **hassas bilgiler temizlenmiş** UIAutomator erişilebilirlik ağacı üzerinden sınıf/eşleştirme kalibrasyonu, kayıtlı slotların görünür UI üzerinde doğrulanması, çoklu gün ve öncelik sırası. Açık izinli operasyonlar dışında hesabı kısıtlayabilecek yüksek frekanslı istekler kullanılmamalıdır.

## 6. Güvenlik ve uyumluluk

- Trendyol GO'nun otomatik slot alma politikasını doğrula. Platform izin vermiyorsa canlı otomasyon kullanma.
- Rate limit / CAPTCHA / 2FA atlatma mekanizması yoktur.
- Aynı hesaba farklı cihazlardan eşzamanlı giriş yapılması oturumu sonlandırabilir.
- Android 11+ cihaz ve erişilebilirlik/screenshot izni gerekir.
- Uygulama Android sistem izinleri nedeniyle üreticiye göre durabilir. Tam kesintisiz 7/24 çalışma garantisi yoktur.

## Klasörler

```text
DraBornSlot/
  .github/workflows/build-apk.yml
  app/src/main/AndroidManifest.xml
  app/src/main/res/xml/accessibility_service.xml
  app/src/main/java/com/draborneagle/drabornslot/
    MainActivity.kt
    SettingsStore.kt
    EventLog.kt
    SlotAccessibilityService.kt
  app/build.gradle.kts
  build.gradle.kts
  settings.gradle.kts
  tests/
```
