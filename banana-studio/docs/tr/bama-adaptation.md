# BAMA incelemesi ve Banana’ya uyarlamalar

27 Ekim 2026 · [English: kaynaklar, karşılaştırma ve ölçümler](../en/bama-adaptation.md)

## Kurulum ve kapsam

[BAMA](https://github.com/daveebbelaar/bama), bir görsel üretim uygulaması değil; Mac uygulaması geliştirmeye yönelik 21 ajan becerisinden oluşuyor. `9b986714f248036cdf3bdf458b93cd4b67fe120f` sürümü incelendi ve 21 beceri Codex’e kuruldu. Banana’ya çalışma zamanı bağımlılığı eklenmedi.

Özellikle araştırma, ölçerek performans iyileştirme, küçük ve test edilebilir bileşenler, işletim sistemi entegrasyonu ve geçici veriyle doğrulama yöntemleri kullanıldı. BAMA’nın yeni uygulama şablonunun macOS 26 şartını Banana’ya taşımadık. Mevcut Mac/Windows ortak arayüzü ve macOS 13.5 dağıtım alt sınırı korunuyor.

## Uygulanan geliştirmeler

| Geliştirme | Kullanıcıya etkisi | Doğrulama |
| --- | --- | --- |
| Görsel yakınlaştırma | Açık görselde + / − ile yakınlaştırma, 0 ile ekrana sığdırma; aynı işlemler için görünür düğmeler. | Gerçek bileşen testleri; yazı alanı, tarayıcı zoom’u, menüler ve diğer pencereler kendi tuşlarını koruyor. Görsel dosyası değişmiyor. |
| Klasör hesabını indeksleme | Her klasör için bütün kayıtları tekrar tarama kaldırıldı; adet ve toplam maliyet tek indeksten okunuyor. | Eski sonuçlarla birebir karşılaştırma; döngülü ve 20.000 seviyeli klasörler; kaynak kayıtlar değişmiyor. |
| Pencereyi hatırlama | Mac ve Windows normal pencere boyutunu/konumunu hatırlıyor. Önceki monitör yoksa pencere görünür ekrana sığıyor. | Geçici dosyayla yükleme/kaydetme, bozuk ayar, küçük ekran ve çıkarılmış monitör testleri. Tam ekran/büyütülmüş mod otomatik geri açılmıyor. |
| Mac açılış sınırı | Yerel sunucu açılmazsa sonsuz beklemek yerine 30 saniyede açıklama gösteriliyor ve başarısız alt süreç durduruluyor. | Hazır, hata, zaman aşımı ve kapanış durumları; geç gelen olaylar ikinci hata oluşturmuyor. |

Galeri içindeki büyük görsel bileşeni ayrı bir dosyaya taşındı. Bu, doğrudan üretimde kullanılan zoom davranışını bağımsız test etmeyi sağlıyor.

## Performans ölçümünün anlamı

Sentetik 300 klasör / 20.000 kayıt testinde bağımsız uygulamanın klasör bilgisi hesabı **32,955 ms → 0,248 ms**, web sürümünün hesabı **1,118 ms → 0,229 ms** ölçüldü. Web sürümünde önceki indeksleme zaten bulunduğu için başlangıç noktaları farklı.

Ölçüm Node 24.19.0 ile, beş ısınma turundan sonra on bir turun medyanı alınarak yapıldı. Testler sırayla çalıştırıldı. Bunlar gerçek kullanıcı galerisi, tüm sayfanın çizim süresi veya AI üretim hızı ölçümleri değildir; aynı sentetik metadata üzerinde klasör hesaplarının karşılaştırmasıdır. Derin klasör örneği ve tekrar üretim komutu İngilizce raporda bulunuyor.

## Araştırmanın gösterdiği diğer fırsatlar

Draw Things ve DiffusionBee gibi uygulamalardaki maskeli düzenleme, varyasyon ve geçmiş özellikleri Banana’da zaten var. Bunları ikinci bir motorla tekrar yapmak yerine mevcut akışı korumak daha yararlı. Pixelmator Pro ve Eagle’daki hızlı klavye inceleme yaklaşımı yakınlaştırma kontrolüne taşındı. ComfyUI Desktop’ın pencere/alt süreç sorunlarına dair açık kayıtları, pencere ve açılış testlerini önceliklendirmemize yardımcı oldu. Bunlar tekil kullanıcı raporlarıdır; bir uygulamanın tüm kullanıcıları hakkında sonuç çıkarılmadı. Altı uygulamanın kaynaklı karşılaştırması İngilizce raporda.

Sonraki adaylar: ortak komut listesinden yerel Search/Library menüleri, yalnızca kayıtlı medya kimliğiyle Finder/Explorer’da orijinali gösterme, SQLite üzerinden masaüstü taslağı/konumunu geri getirme ve üretim sırasında kapatıp açma testlerini genişletme. Bunlar bu sürümde tamamlanmış özellik olarak sunulmuyor.

## Güvenlik ve sınırlar

Yeni model, prompt, maske genişletme veya piksel işleme kuralı eklenmedi. Maske dışını koruma ve edit/generation ayrımı değişmedi. API anahtarları mevcut güvenli depolarında kalıyor. Ekran kaydı izni, arka planda pano izleme, genel klavye dinleyicisi veya dışarı açık ajan kontrol portu eklenmedi.

Mac kodu Swift testleriyle derleniyor; Windows CI kendi paketini derleyip izole pencere testini çalıştırıyor. Fiziksel Windows cihazındaki monitör/DPI etkileşimi ayrıca manuel test gerektirir. Arayüz için gerçek hesap veya ücretli üretim yerine sentetik görselli test sayfası kullanıldı.
