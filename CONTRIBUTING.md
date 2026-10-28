# DrabornEagle geliştirme akışı

Uygulama kaynakları ilgili ürün klasöründedir. Kaynak kökenini belirten `UPSTREAM.json`, `LICENSE` ve üçüncü taraf bildirimlerini koru. Yeni uygulama metinleri DrabornEagle ürün adlarını kullanır; eski derleyici ve veri formatı kimliklerini toplu arama/değiştirmeyle yeniden adlandırma.

Web değişikliklerinde gerçek dosya çıktısını ve kalıcılığı doğrula. Coconut için kökte `npm ci && npm test`; Banana-edits için `cd banana-studio && npm ci && npm test && npm run typecheck && npm run build` çalıştır. Statik dağıtım `scripts/sync-web.py` ile güncellenir.

clipboard-app ve Coconut masaüstü değişiklikleri ilgili macOS ve Windows araç zincirleriyle ayrıca test edilmelidir. Kaynak aktarımı imzalı masaüstü sürüm yayımlamakla aynı işlem değildir. Binary sürümü yayımlamadan önce platform kabul testleri, imzalama ve güncelleme kanalları doğrulanmalıdır.

Anahtar, oturum verisi, gerçek kullanıcı içeriği, yerel medya kitaplığı veya kişisel veritabanını commit etme. Hatalar ve geliştirme istekleri bu deponun Issues bölümünde tutulur.
