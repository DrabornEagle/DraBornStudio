# Repository name / Repo adı

The public clipboard-app repository is now
[`orkunisitmak/clipboardline`](https://github.com/orkunisitmak/clipboardline).
Its existing repository identity, source history, stars, issues, releases and
branch protection are retained. This is a rename of repository **1425566096**,
not a replacement repository or a change to the application's storage identity.

The English and Turkish demo pages are now at:

- [English](https://orkunisitmak.github.io/clipboardline/)
- [Türkçe](https://orkunisitmak.github.io/clipboardline/tr/)

Git origins should use `https://github.com/orkunisitmak/clipboardline.git`.
The old `clipboardline-desktop` and `clipboardline-app` repository names remain
reserved compatibility redirects. Do not create another repository under either
name: existing installed applications use those update addresses.

Existing signed update feeds and packages remain byte-for-byte unchanged.
In particular, Windows manifests and download URLs retain the exact
`clipboardline-desktop` wire identity expected by shipped clients. An old name
inside signed update metadata or internal package identifiers is intentional.
Public updates still need no GitHub account, token or reinstall.

After the rename, all three repository aliases resolved to the same repository
and Latest release. Both feeds matched their original signed bytes. The installed
Mac application's update check succeeded. The unchanged Windows 1.7.8 updater
discovered the latest version and downloaded/verified the actual installer through
its old URL within its original redirect limit; that network check ran on macOS
and did not execute a Windows installer. No new application version was published
for this repository-only operation.

Türkçe: Public reponun yeni adı **clipboardline**. Kaynak kod, sürümler,
yıldızlar ve koruma ayarları aynı repoda duruyor. Eski güncelleme adresleri
çalışmaya devam ediyor; uygulamayı silip yeniden kurmak veya yeniden izin vermek
gerekmiyor. İmzalı dosyalarda görünen eski repo adı uyumluluk için korunuyor.
Demo sayfasının yeni adresi yukarıdaki İngilizce/Türkçe bağlantılarda.
