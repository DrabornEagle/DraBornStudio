# Banana-edits web dağıtımı

Geliştirme kaynağı `DraBornStudio/banana-studio`; statik dağıtım `DrabornEagle_Web/Banana-edits/` klasöründedir. Web uygulaması GitHub Pages üzerinde çalışır. GitHub Pages sunucu API fonksiyonlarını çalıştırmaz.

## Yerel galeri

`npm ci`, `npm test`, `npm run typecheck` ve `npm run build` komutlarını bu uygulama klasöründe çalıştır. Derleme `dist/` altına çıkar. `public/workspace.json` varsayılan olarak `mode: "browser"` içerir. Bu modda medya, klasörler ve tercihler bu tarayıcıda tutulur; AI istekleri sunucuya gönderilmez. Anahtar gerekmez.

## AI ve bulut modu

`api/` işlevlerini ve gerekli veritabanı/özel medya depolamasını ayrı, HTTPS sunucuda kur. Sağlayıcı anahtarlarını yalnızca o sunucunun gizli ortam değişkenlerine ekle. Sunucu kimlik doğrulamasını ve origin izinlerini yapılandır. Ön yüzde gerçek sağlayıcı anahtarı veya servis rolü anahtarı bulunmamalıdır.

`public/workspace.json` içindeki `mode` değerini `cloud`, `apiBase` değerini yapılandırdığın HTTPS API köküne değiştir. Bu dosya herkese açıktır. Adrese erişim anahtarı veya gizli query parametresi ekleme. Mevcut web köprüsü kullanılıyorsa sunucuda `BANANA_WORKSPACE_ORIGIN` ayarlanır. Verileri korumak için `/api/banana-studio` köprü yolu ve tarayıcı veritabanı kimlikleri korunmuştur; ürün adresi `/Banana-edits/` olarak değişmiştir.

AI sağlayıcı bağlantısı bu kaynak aktarımında kurulmuş varsayılmaz; çalışma modu yerel galeri olarak kalır. Hazır olmayan üretim, oturum ve paylaşım akışları kurulum gerektiğini açıkça belirtir.

## Yayımla ve doğrula

Derlemeden sonra depo kökünde `python3 scripts/sync-web.py /path/to/DrabornEagle_Web` çalıştır, değişiklikleri gözden geçir ve hedef web reposuna aktar. `/Banana-edits/` ana uygulama; `/Banana-edits/share.html` paylaşım girişidir. Eski `/banana-studio/` ve `/banana-studio/share.html` bağlantıları query ve hash değerlerini koruyarak yönlendirilir.

Tarayıcıda klasör oluşturma, sayfa yenileme sonrası kalıcılık, medya içe aktarma, arama ve en az 768/1024/1440 piksel yerleşimi doğrulanmalıdır. `npm run audit` geçmişi de denetler; yayımlanan kodun geçmişinde gizli bilgi bulunmamalıdır.
