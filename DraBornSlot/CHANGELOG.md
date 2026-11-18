# Sürüm geçmişi

## v0.7.2

- **Erişilebilirlik bağlantısı**, **Servis tanısı** ve **Kayıtlı planı güncelle** pencereleri DraBornSlot tasarımını kullanır. Plan güncellemede çıkarılacak saatler gösterilir.
- **Bağlantıyı yenile** tarama oturumunu tazeler ve bağlantı korumasını açar. Koruma, plan boşken ve ana ekran kapalıyken de servis durumunu takip eder. **Korumayı durdur** bildirimin içinden veya **Servis tanısı** üzerinden kullanılabilir.
- Servis tanısı, Android’in sağladığı süreç kapanış açıklamasını ve bağlantı korumasının durumunu gösterir.

## v0.7.1

- Plan ve servis durumu uygulamanın kendi sürecinde okunur. Erişilebilirlik henüz bağlanmadığında kayıtlı plan açılışta gösterilir.
- **Kaydet ve uygula** farklı işlem seçeneklerini bir menüde açar. Arka plan seçildiğinde bildirimden kurye uygulamasına geçilebilir veya takip durdurulabilir.
- Telefon kilitliyken plan hazır bekler. Kilit açılıp GO tekrar göründüğünde tarama devam eder. **Temizle** veya **Takibi durdur** arka plan servisini de durdurur.

## v0.7

- **Bağlantıyı yenile** erişilebilirlik önbelleğini ve tarama oturumunu yeniler. Android servisi yeniden bağlarken durumu birkaç saniye kontrol eder. Android bağlantıyı geri getiremezse ayarları açma seçeneği sunulur.
- **Temizle** takibi durdurur, kayıtlı planı siler ve servis oturumunu sıfırlar. Canlı seçim, bugün ve 1 saniyelik aralık varsayılan olarak seçilir.
- DraBornSlot ana ekranı kapalıyken erişilebilirlik servisi ayrı süreçte plana devam eder. Trendyol GO arka plandaysa veya telefon kilitliyse tarama bekler ve Trendyol GO yeniden görünür olduğunda devam eder.

## v0.6.2

- Erişilebilirlik servisi ana ekrandan ayrı bir Android sürecinde çalışır. **Temizle** kayıtlı planı siler ve taramayı durdurur. Android servis bağlantısını yönetmeye devam eder.
- **Temizle** sonrasında **Canlı seçim** ve **Kaydedince takibi başlat** seçili gelir. Yeni bir plan kaydedilene kadar takip durur.
- Servis bağlı değilse ana ekrandaki **Bağlantıyı yenile** düğmesi Android ayarlarına yönlendirir. **Servis tanısı** Android’in kaydettiği son servis süreci kapanışını gösterir.

## v0.6.1

- **Temizle** kayıtlı takibi durdurur, çalışma gününü bugüne ve yenilemeyi 1 saniyeye döndürür. Yeni plan düzenleyicisi İzleme modunda, seçimler boş ve **Kaydedince takibi başlat** açık gelir.
- Erişilebilirlik durumu Android’deki izin ayarını ve servis bağlantısını ayrı gösterir. Boş planda tarama durur. Her servis bağlantısında tarama oturumu yeniden başlar.

## v0.6

- **Kaydedince takibi başlat** seçeneği plan düzenleyicide varsayılan olarak açık.
- Aktif planla Trendyol GO açıldığında, Canlı seçim **Tüm Saatler** sekmesine geçer.
- Ajan, açıkça etkin erişilebilirlik düğmelerine öncelik verir. Görsel kontrolde uygun saatlerin renkli `+` düğmelerini arar.

- Android’in erişilebilirlik olaylarıyla hızlı saat denetimi. Görünür slot kontrolleri öncelikli işlenir.
- Hedef saat ekran dışındayken ileri veya geri kaydırma. Uygun saat için görünür `+` kontrolü kullanılır.
- İstek üzerine yenileme. Takip, görülmemiş saatleri taradıktan sonra sayfadaki yenileme düğmesini kullanır.
- Yeni renk paleti, kartal ve saat logosu, hareketli açılış, bölümlere ayrılmış saat seçimi ve servis tanısı.

## v0.4 – Seçili saat koruması ve kullanıcı kontrollü kaldırma

- Yeşil `+` ve kırmızı `X` algılama alanı daraltıldı. İstenen bir saat kırmızı X gösteriyorsa bu satırdaki X'e dokunulmaz.
- Aynı gün daha önce kaydedilmiş hedef saati DraBornSlot'tan kaldırıp **Kaydet ve Uygula** dersen, yalnızca o saat için kaldırma isteği saklanır. Canlı modda Trendyol GO'nun doğru günü ve saat satırı görünüyorsa kırmızı X'e dokunulabilir. Yeşil + görülünce istek tamamlanır.
- Tarih değiştirmek, önceki tarihteki saatleri kaldırma isteği oluşturmaz.
- Yenileme aralığı artık **1–60 saniye**; v0.4'e ilk geçişte 1 sn. Sayfa yalnızca "Sayfayı Yenile" görünürken, seçim/kaldırma dokunuşlarıyla çakışmadan yenilenir.
- 1 saniye tarama veya yenileme, bir slotu açıldığı anda alma garantisi sağlamaz. Başka saatlere kaydırıldığında yenileme düğmesi görünmeyebilir.
- Kırmızı X kesin rezervasyon onayı değildir; Trendyol GO Kayıtlı Saatler ekranını kontrol et. Platformun otomasyon politikasına uyulmalıdır.
