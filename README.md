# DraBornStudio

DrabornEagle ekosisteminin üretkenlik ve yaratıcı medya uygulamaları. Geliştirme, dokümantasyon ve sürüm bakımı bu depoda yapılır.

| Klasör | Uygulama | Platform | Aç |
| --- | --- | --- | --- |
| [Coconut-app](Coconut-app/) | **Coconut-app** | Web, macOS, Windows | [Web](https://www.draborneagle.com/DraBornStudio/Coconut-app/) |
| [Banana-edits](Banana-edits/) | **Banana-edits** | Web, macOS, Windows | [Web](https://www.draborneagle.com/DraBornStudio/Banana-edits/) |
| [clipboard-app](clipboard-app/) | **clipboard-app** | macOS, Windows | [Tanıtım ve kaynaklar](https://www.draborneagle.com/DraBornStudio/clipboard-app/) |

![Coconut-app dosya atölyesi](Coconut-app/docs/assets/coconut-web.jpg)

## Web ve kaynak eşitleme

`Coconut-app/web/` Coconut-app web kaynağıdır. `Banana-edits/` Banana-edits geliştirme kaynağıdır. `scripts/sync-web.py /path/to/DrabornEagle_Web` komutu statik dağıtımı ve kaynak kopyalarını hedef repodaki `DraBornStudio/` klasöründe günceller; Banana-edits için önce `npm run build` çalıştır. [DraBornStudio uygulamaları](https://www.draborneagle.com/DraBornStudio/) web reposundan yayımlanır.

Her uygulamanın README dosyası kendi kurulumunu, yeteneklerini ve sınırlarını açıklar. Galeriler cihazdaki tarayıcıya aittir; bulut ve AI özellikleri ayrıca sunucu/sağlayıcı kurulumu ister. Masaüstü kaynakları tam aktarılmıştır; bu repo henüz yeni marka altında imzalı masaüstü binary dağıtmaz.

## Geliştirme ve katkı

İş ve hata kayıtları [Issues](https://github.com/DrabornEagle/DraBornStudio/issues) üzerinden yönetilir. Her değişiklikte uygulamanın testleri çalıştırılır; API anahtarları, gerçek kullanıcı medyası, yerel veritabanları ve imzalama anahtarları commit edilmez.

## Lisans ve kaynak başlangıcı

Bu uygulamalar MIT lisanslı açık kaynak projelerden geliştirilmiştir. DrabornEagle bu sürümlerin bakımını ve yeni geliştirmelerini yürütür. Özgün telif ve lisans bildirimleri her uygulamanın `LICENSE` dosyasında değiştirilmeden korunur; kaynak adresleri ve commit bilgileri `UPSTREAM.json` dosyalarındadır. DrabornEagle tarafından eklenen kod da MIT lisanslıdır. [Bildirimler](THIRD_PARTY_NOTICES.md).
