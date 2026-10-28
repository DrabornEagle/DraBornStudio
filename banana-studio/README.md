# Banana-edits

**DrabornEagle ekosisteminin görsel, video ve yaratıcı medya çalışma alanı.** Galeri, klasörler, medya içe aktarma, görsel düzenleme ve sunucu destekli AI üretim akışlarını bir araya getirir.

[Web uygulamasını aç](https://www.draborneagle.com/Banana-edits/) · [Hata bildir](https://github.com/DrabornEagle/DraBornStudio/issues)

## Kullanım

Web sürümü yerel galeriyle açılır. Medya ve klasörler bu tarayıcıda saklanır; farklı cihazlar arasında otomatik eşitlenmez. AI üretimi, hesap ve bulut paylaşımı ayrıca yapılandırılmış bir sunucu, veritabanı, özel medya depolaması ve sağlayıcı anahtarı gerektirir. API anahtarlarını ön yüze veya repoya ekleme.

## Geliştirme

```sh
cd banana-studio
npm ci
npm run dev
```

Yerel geliştirme adresi `http://localhost:3000/Banana-edits/`. `npm test`, `npm run typecheck` ve `npm run build` doğrulamaları çalıştırır. [Web kurulumu](WEB_DEPLOYMENT.md), [masaüstü kurulumu](docs/en/desktop.md) ve [güvenlik](SECURITY.md) ek açıklamaları içerir.

Üretim derlemesi `dist/` klasörüne çıkar; statik dosyalar DrabornEagle_Web reposunun `Banana-edits/` klasörüne yayımlanır. `public/workspace.json` yalnızca herkese açık sunucu adresi ve çalışma modu taşır. Mevcut galeri, veritabanı ve köprü kimlikleri kullanıcı verilerinin korunması için sabittir.

macOS ve Windows kaynakları `desktop/` içindedir. DrabornEagle için imzalanmış masaüstü paketleri henüz yayımlanmamıştır.

## Geliştiren ve lisans

Bu sürümün geliştirme ve bakımı DrabornEagle tarafından yürütülür. Kaynak geçmişi [UPSTREAM.json](UPSTREAM.json), MIT lisansı [LICENSE](LICENSE), bileşen bildirimleri [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) içinde korunur. DrabornEagle değişiklikleri de MIT lisanslıdır.
