# Security / Güvenlik

## English

Report security problems through the public repository's **Security → Report a vulnerability** feature when available. If private reporting is unavailable, open an issue requesting a private reporting channel; do not publish an exploit involving someone else's data, a credential, a clipboard sample or a private screenshot. Include the platform, published version, a synthetic reproduction and the expected result. Remove account names, paths, URLs with credentials, tokens and session cookies from evidence.

We evaluate reports against the latest published build for each platform. The macOS and Windows implementations have different operating-system integrations; a fix on one platform does not establish that the other was tested.

### Trust boundaries

- The source code is public. Official macOS release downloads and their update feed are signed. The official updater pins its release verification key; a source commit alone is not an application update.
- Self-built **clipboard-app Dev** is a separate application with a different bundle identifier and storage folder. Its updater is disabled. It cannot impersonate an official signed release or reuse the official application's frozen credential helper.
- Neither source builds nor official public updates need a GitHub token. Release-signing keys, signing profiles, Keychain material, user data and rollback backups must never be committed or included in an issue or pull request.
- Clipboard history can contain confidential material. File permissions are a local access restriction, not encryption, a password vault or protection from processes running as the same user.
- Optional link enrichment makes network requests. macOS metadata uses HTTPS, validates every DNS answer, and connects to a validated numeric public address while verifying TLS against the original hostname and system trust. Every redirect and thumbnail goes through the same checks; reserved/private addresses, credentials and known secret query parameters are rejected. HTML is parsed as bounded text without executing scripts or loading a web view. The community Dev builder defaults this feature to off; enable it explicitly only if you want these requests.
- Opening a link, exporting a file, and pasting into another application cross application boundaries. The receiving application determines which formats it accepts.

Do not disable Gatekeeper, grant broad system permissions, change Keychain trust, or share signing credentials to work around an installation problem. Development builds may need their own macOS permission decisions; their ad-hoc identity does not provide persistent authorization across rebuilds. Official releases preserve their signing identity separately.

## Türkçe

Güvenlik sorunlarını, varsa public reponun **Security → Report a vulnerability** bölümünden özel olarak bildirin. Bu seçenek yoksa özel iletişim kanalı istemek için issue açın; başkasının verisini, anahtarını, pano içeriğini veya özel ekran görüntüsünü yayımlamayın. Platformu, yayımlanmış sürümü, yapay verilerle tekrar adımlarını ve beklenen sonucu ekleyin. Kanıtlardan kullanıcı adlarını, özel yolları, kimlik bilgili URL'leri, tokenları ve oturum çerezlerini çıkarın.

Raporlar her platformun en son yayımlanan sürümüne göre değerlendirilir. macOS ve Windows işletim sistemiyle farklı yöntemlerle çalışır; bir platformdaki düzeltme diğerinin test edildiği anlamına gelmez.

- Resmî macOS paketleri ve güncelleme akışı imzalıdır. Kaynak kod commit'i tek başına uygulama güncellemesi değildir.
- Kendiniz derlediğiniz **clipboard-app Dev**, farklı uygulama kimliği ve veri klasörü kullanır. Güncelleyicisi kapalıdır; resmî imzanın veya kimlik bilgisi yardımcısının yerini alamaz.
- Public güncellemeler ve kaynak koddan derleme GitHub tokenı istemez. İmza anahtarlarını, Keychain verilerini, kişisel geçmişi ve yedekleri Git'e veya hata raporlarına eklemeyin.
- Pano geçmişi hassas bilgi içerebilir. Yerel dosya izinleri şifreleme değildir; aynı kullanıcıyla çalışan diğer süreçlere karşı bir parola kasası sağlamaz.
- İsteğe bağlı link önizlemesi ağ isteği yapar. macOS, HTTPS kullanır; DNS cevaplarını denetler ve TLS'i özgün alan adı ile sistem güven zincirine göre doğrulayarak denetlenmiş sayısal public IP'ye bağlanır. Yönlendirmeler ve thumbnail'ler de aynı kontrollerden geçer; özel/rezerve adresler, kimlik bilgileri ve bilinen hassas sorgu alanları reddedilir. HTML sınırlı metin olarak işlenir; JavaScript veya web görünümü çalıştırılmaz. Community Dev derlemesinde özellik varsayılan olarak kapalıdır; bu istekleri istiyorsanız kendiniz açın.

Kurulum sorununu aşmak için Gatekeeper'ı kapatmayın, Keychain güvenini değiştirmeyin ve imza anahtarı paylaşmayın. Geliştirme uygulamasının macOS izinleri ayrıdır; yeniden derlemeler, resmî sürümün sabit imzasıyla aynı izin devamlılığını sağlamaz.
