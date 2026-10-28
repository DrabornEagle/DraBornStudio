# Coconut-app Web

28 Ekim 2026 · Masaüstü kaynakları `source/`, tek geliştirme kaynağı [DraBornStudio/Coconut-app](https://github.com/DrabornEagle/DraBornStudio/tree/main/Coconut-app) klasöründedir.
Kaynak commit: `e2f1a2ed0b5b1efaa363bc6419ac63b930cd3b78`.

Web arayüzü Coconut çarkı ve editörlerinden uyarlanmıştır. Dosya seçme, sürükleyerek bırakma, yapıştırma, çark düğmeleri, dokunarak düzenleme ve klavye kısayolları bulunur. Sonuçlar gerçek dosyalardır; çıktı kitaplığı IndexedDB ile bu tarayıcıda saklanır.

| Alan | Tarayıcı sürümü |
| --- | --- |
| Görsel | PNG/JPG/WebP, PDF dışa aktarma; FFmpeg desteklediğinde BMP/TIFF/AVIF; boyutlandırma, kırpma, döndürme, işaretleme, çerçeve, kolaj, sıkıştırma, metadata kaldırma ve gizleme |
| PDF | Görsellerden PDF, birleştirme, sayfa bölme/sıralama/döndürme/çıkarma, metadata temizleme ve yeniden sıkıştırarak kaydetme |
| Ses/video | FFmpeg WebAssembly ile desteklenen codec'ler arasında dönüşüm, trim, sesi kaldırma, crop, hız, birleştirme, bölme, kare çıkarma, ses eşitleme, kanal değiştirme, ses görselleştirme, sessizlik kaldırma |
| Gizleme | Videonun merkezindeki %50 alan, seçili aralıkta siyahla kapatılır. Sesin seçili aralığı susturulur. Masaüstündeki bütün blur/bleep seçenekleri aktarılmamıştır. |
| QR | Görsel veya PDF'nin ilk 100 sayfasında yerel tarama ve metin raporu |
| Metin | TXT/MD/HTML, CSV/TSV ve SRT/VTT arasında desteklenen basit dönüşümler. Karmaşık tablolar, Office/Pages ve belge mizanpajı için yerel uygulama gerekir. |
| Arşiv | ZIP oluşturma ve ZIP çıkarma; 1.000 dosya / toplam 250 MB açılmış boyut sınırı |
| Dosya işlemleri | Cihaza indirme, desteklenen sistemlerde paylaşım, görsel/metin panosu, dosya adı kopyalama ve Float rafı |

Tarayıcıda dosya başına 128 MB sınırı vardır. FFmpeg motoru ilk kullanımda CDN üzerinden yaklaşık 31 MB indirir; işleme cihazda yapılır. İşlemin bellek gereksinimi giriş boyutundan büyük olabilir; tabletlerde kısa videolar daha uygundur. Tarayıcının önizleyemediği bir medya dosyası yine Dönüştür çarkından işlenebilir. Codec desteği ve çıktı kalitesi kullanılan motora bağlıdır.

Terminal açma, Finder/Explorer entegrasyonu, sistem klasörü otomasyonu, yerel pencere yönetimi, Office/Pages/PowerPoint dönüşümleri ve sosyal medyadan indirme web sürümünde bulunmaz; özgün masaüstü kaynaklarında korunur. Bunlar tarayıcının doğrudan sağlayamadığı platform/sunucu özellikleridir. Web sürümü bunlar için sahte çıktı üretmez.

Kontroller: DOM üzerinde gerçek PNG imzası, kullanıcı CSV → TSV içeriği, kitaplık ve sekmeler arasında dosya korunması; medya komutlarının yerel FFmpeg ile trim, sessiz video, kare crop, hız ve ses eşitleme çıktıları doğrulandı. Canlı Chromium tarayıcısında MP4 → MP3 çıktısı ve dosya kitaplığı doğrulandı. 768 ve 1024 piksel tablet görünümü ile masaüstü görünümü kontrol edildi; fiziksel iPad/Safari doğrulaması yapılmadı.

## Coconut 1.0

Yeni hindistan cevizi logosu, lacivert/turkuaz tema, hızlı dosya ekleme, açıklamalı başlangıç adımları, araç araması ve filtreler; tablet menüsü, klavye erişimi ve kalıcı açık/koyu görünüm eklendi. Tarayıcı veri tabanı kimliği mevcut dosyaları korumak için sabit tutulur. Güncel adres `/DraBornStudio/Coconut-app/`; önceki web bağlantıları yeni adrese yönlendirilir.
