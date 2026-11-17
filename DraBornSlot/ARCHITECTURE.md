# DraBornSlot — Teknik Mimari, v0.1

## Dağıtım

```text
[Asıl telefon] (kapalı olabilir)
             |
             | [v0.1'de bağlantı yok]
             v
  +-----------------------------------------------------+
  | DAİMA AÇIK İKİNCİ ANDROID (Android 11+)              |
  |                                                     |
  |  Trendyol GO: kullanıcı manuel giriş yapmış         |
  |       ^             erişilebilir Saatler ekranı     |
  |       |                                             |
  |  Android AccessibilityService                       |
  |       ^                    |                        |
  |       |                    v                        |
  |  UI ağacı + görüntü -> tarih / + doğrulama           |
  |                            |                        |
  |                         Karar motoru                 |
  |                         1 tıklama / tekrar tarama    |
  |                            |                        |
  |                  Şifre içermeyen yerel loglar        |
  +-----------------------------------------------------+
```

## Temel sınıflar

| Bileşen | İşlev |
|---|---|
| `MainActivity` | Yerel tercih ve izin arayüzü |
| `SettingsStore` | `SharedPreferences` içinde gün/slot/aralık/deneme sayacı |
| `SlotAccessibilityService` | Hedef ekran, tarih, yeşil-beyaz + algılama, tekli dokunma |
| `EventLog` | Son 100 yerel olay |
| `build-apk.yml` | GitHub Actions ile debug APK |

## Durum akışı

```text
Agent kapalı / test / canlı
        |
        +--- cihazda Trendyol görünmüyor --> bekle
        |
        +--- tarih 0..6 gün dışında --> bekle
        |
        +--- UI ağacında hedef tarih ve slot yok --> bekle
        |
        +--- screenshot alınamadı --> bekle
        |
        +--- hedef tarih seçili değil
        |              |
        |              +-- test: yalnızca log
        |              +-- canlı: tarih düğmesine dokun, yeniden tara
        |
        +--- hedef tarihte yeşil + ve beyaz çapraz çizgiler var mı?
                       |
                       +-- hayır: bekle
                       +-- test: log, dokunma yok
                       +-- canlı: bir dokunma, deneme sayacı, tekrar tara
```

## Güvenlik kabulleri

1. Yetki yalnızca kullanıcı tarafından Android Ayarları'ndan verilir.
2. Paket filtresi `com.orangemobile` olarak sabittir.
3. Kimlik bilgileri alınmaz veya saklanmaz.
4. Oturum atlatma, CAPTCHA çözme, imza taklidi veya özel API kullanımı yoktur.
5. Screenshot bellek içindedir; dosyaya veya buluta kaydedilmez.
6. Her slot için en fazla iki otomatik tıklama denemesi; 90 saniye tekrar bekleme.
7. Canlı modda sayfa yenileme en erken 15 saniyede bir denenir.
8. Gerçek rezervasyon onayının UI üzerinden kontrol edilmesi v0.2'ye bırakılmıştır.

## Eksiklikler / riskler

- Uçtan uca test **yapılmadı**. Kullanıcının örnek görüntüsündeki renk algılama, tüm cihazlara genellenemez.
- React Native erişilebilirlik ağacı saat metinlerini ayrı görünür düğümler olarak sunmayabilir.
- `Sayfayı Yenile` metni uygulamanın farklı sürümünde erişilebilir olmayabilir.
- Android arka plan/kilit/üretici güç yönetimi sınırlamaları vardır.
- İkinci cihazda uygulamanın açık ve ekranın kullanılabilir kalması gerekir.
- Trendyol GO hesabının / çalışma saatlerinin otomasyonu için kullanım koşulları kontrol edilmelidir.
- Ekrandaki `+` dokunuşu yalnızca **denemedir**; başarılı kayıt kanıtı değildir.

## v0.2 öncelikleri

1. Kullanıcının izinli ikinci cihazında UIAutomator erişilebilirlik ağacıyla ekran kalibrasyonu.
2. Kayıtlı slotların, Trendyol'un görünen `Kayıtlı Saatler` ekranından doğrulanması.
3. Birden fazla gün, gün şeridi kaydırma, tarih bazlı program.
4. Sağlık kontrolleri, güvenli hata bildirimi ve kullanıcıya açık durdurma butonu.
5. İzin varsa uçtan uca yönetim için kimlik doğrulamalı, şifrelenmiş uzak panel.
