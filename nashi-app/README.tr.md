# Coconut-app

**DrabornEagle ekosisteminin dosya dönüştürme ve düzenleme atölyesi.** Görsel, PDF, ses, video, belge ve arşiv araçlarını tek çalışma alanında toplar.

- [Web uygulamasını aç](https://www.draborneagle.com/Coconut-app/)
- Geliştirme ve hata bildirimleri: [DraBornStudio](https://github.com/DrabornEagle/DraBornStudio/issues)

## Klasörler

`web/` tablet ve bilgisayar için yenilenmiş Coconut web uygulamasıdır. `Sources/`, `Resources/`, `Configuration/` ve `Package.swift` macOS kaynaklarını; `windows/` Windows kaynaklarını içerir.

## Web sürümünü çalıştırma

Depo kökünde `python3 -m http.server 8080` komutunu çalıştırıp `http://localhost:8080/nashi-app/web/` adresini aç. Web sürümü derleme gerektirmez. FFmpeg motoru ilk kullanımda indirilir; desteklenen işlemler cihazda çalışır. Kitaplık aynı tarayıcıda saklanır. Önemli çıktıları cihazına indir.

Araç kapsamı ve sınırlar için [web/WEB_STATUS.md](web/WEB_STATUS.md) dosyasına bak. İşletim sistemi entegrasyonları masaüstü uygulamasına aittir.

## Masaüstü geliştirme

macOS: Swift 6, Xcode ve macOS 13+. `swift test`, ardından `scripts/build-app.sh`. Windows: [.NET proje yönergeleri](windows/README.md). Bu depodaki kaynak kopyası imzalanmış DrabornEagle masaüstü sürümü yayımlandığı anlamına gelmez.

Yeni marka kullanıcı arayüzüne uygulanmıştır; Swift/.NET modül adları ve mevcut yerel kayıt kimlikleri uyumluluk için korunur. Masaüstü güncelleme kanalları henüz DrabornEagle imzalı paket dağıtmaz.

## Geliştiren ve lisans

Bu sürüm DrabornEagle tarafından geliştirilir ve sürdürülür. Açık kaynak başlangıcı, kaynak commit ve yazar bildirimleri [UPSTREAM.json](UPSTREAM.json), [LICENSE](LICENSE) ve [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) içinde korunur. DrabornEagle değişiklikleri MIT lisansıyla sunulur.
