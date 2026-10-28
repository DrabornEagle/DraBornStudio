# Banana-edits web dağıtımı

Geliştirme kaynağı `DraBornStudio/Banana-edits`; statik dağıtım `DrabornEagle_Web/DraBornStudio/Banana-edits/` klasöründedir. Web uygulaması statik barındırmada çalışır. GitHub Pages sunucu API fonksiyonlarını çalıştırmaz; Vercel dağıtımı web köprüsünü çalıştırabilir.

## Yerel galeri

`npm ci`, `npm test`, `npm run typecheck` ve `npm run build` komutlarını bu uygulama klasöründe çalıştır. Derleme `dist/` altına çıkar. `public/workspace.json` varsayılan olarak `mode: "browser"` içerir. Bu modda medya, klasörler ve tercihler bu tarayıcıda tutulur; AI istekleri sunucuya gönderilmez. Anahtar gerekmez.

## AI ve bulut modu

`api/` işlevlerini ve gerekli veritabanı/özel medya depolamasını ayrı, HTTPS sunucuda kur. Sağlayıcı anahtarlarını yalnızca o sunucunun gizli ortam değişkenlerine ekle. Sunucu kimlik doğrulamasını ve origin izinlerini yapılandır. Ön yüzde gerçek sağlayıcı anahtarı veya servis rolü anahtarı bulunmamalıdır.

`public/workspace.json` içindeki `mode` değerini `cloud`, `apiBase` değerini yapılandırdığın HTTPS API köküne değiştir. Bu dosya herkese açıktır. Adrese erişim anahtarı veya gizli query parametresi ekleme. Web köprüsü kullanılıyorsa sunucuda `BANANA_WORKSPACE_ORIGIN` ayarlanır; güncel API kökü `/api/banana-edits` olur. Tarayıcı veritabanı kimlikleri mevcut galeriyi korumak için sabit tutulur. Giriş sağlayıcısının izin verilen dönüş adreslerine `https://www.draborneagle.com/DraBornStudio/Banana-edits/` eklenmelidir.

AI sağlayıcı bağlantısı bu kaynak aktarımında kurulmuş varsayılmaz; çalışma modu yerel galeri olarak kalır. Hazır olmayan üretim, oturum ve paylaşım akışları kurulum gerektiğini açıkça belirtir.

## Yayımla ve doğrula

Derlemeden sonra depo kökünde `python3 scripts/sync-web.py /path/to/DrabornEagle_Web` çalıştır, değişiklikleri gözden geçir ve hedef web reposuna aktar. `/DraBornStudio/Banana-edits/` ana uygulama; `/DraBornStudio/Banana-edits/share.html` paylaşım girişidir. Önceki web bağlantıları sunucu yönlendirmeleri ve statik 404 uyumluluğu üzerinden yeni adrese taşınır; eski adlarla proje klasörü tutulmaz.

Tarayıcıda klasör oluşturma, sayfa yenileme sonrası kalıcılık, medya içe aktarma, arama ve en az 768/1024/1440 piksel yerleşimi doğrulanmalıdır. `npm run audit` geçmişi de denetler; yayımlanan kodun geçmişinde gizli bilgi bulunmamalıdır.
