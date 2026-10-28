# clipboard-app

**DrabornEagle ekosistemi için yerel pano geçmişi ve kaydedilmiş içerik kitaplığı.** Metinleri, görselleri ve dosya referanslarını klavye odaklı raflarda düzenleyen macOS ve Windows uygulaması.

[Kaynak depo](https://github.com/DrabornEagle/DraBornStudio/tree/main/clipboardline) · [Hata bildir](https://github.com/DrabornEagle/DraBornStudio/issues)

## Kaynaklar ve geliştirme

- `Sources/`, `Package.swift`: macOS uygulaması, Swift 5.9+, macOS 14+.
- `windows/`: Electron tabanlı Windows uygulaması. `cd windows && npm ci && npm test`.
- `contracts/`: iki platformun ortak davranış sözleşmeleri.
- `docs/`: kurulum, mimari ve platform eşitliği belgeleri.

macOS kontrolleri `swift test`; Windows kaynak kontrolleri `npm test` ile çalışır. Yerel sürüm ve güvenlik betikleri `scripts/` altındadır. İmzalanmış uygulama yayını için gerçek macOS ve Windows ortamlarında doğrulama gerekir; bu aktarım bir masaüstü binary yayını değildir.

Uygulamanın görünen adı clipboard-app olarak güncellenmiştir. Derleyici modülleri, mevcut depolama ve protokol kimlikleri korunmuştur. Özgün projeye ait güncelleme imzaları veya yayın varlıkları DrabornEagle yayını olarak sunulmaz.

Sistem genelinde pano izleme ve kısayollar yerel işletim sistemi izinleri gerektirir; bu kaynakların tarayıcı uygulaması yoktur. Bu repoya gerçek pano içeriği, yerel kitaplık veya kişisel ayar dosyası ekleme.

## Geliştiren ve lisans

DrabornEagle tarafından geliştirilen ve sürdürülen MIT lisanslı sürüm. Kaynak başlangıcı [UPSTREAM.json](UPSTREAM.json), özgün yazar bildirimi [LICENSE](LICENSE), bağımlılıklar [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) içinde korunur. DrabornEagle değişiklikleri MIT lisanslıdır.
