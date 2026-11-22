# Storilex yayın süreci

Bu belge, uygulamanın kullanıcılara nasıl yayımlandığını anlatır. Kısaca: **derleme ve test otomatik, yayın elle ve onaylı.**

| İş akışı | Ne zaman çalışır | Ne yapar | Yayın yapar mı? |
|---|---|---|---|
| `build.yml` | Her PR, `main`'e her push (PR birleştirmesi dahil), elle başlatma | Testler, ses kontrolü, 5 platformun derlemesi, yayın paketlerinin kuru çalıştırması (`package` işi) | **Hayır.** Belirteci salt okunur (`contents: read`). |
| `release.yml` | Yalnızca elle: Actions > release > Run workflow | Seçilen `build.yml` çalıştırmasının dosyalarını alır, yeniden kontrol eder, `latest` yayınını değiştirir | **Evet**, ama yalnızca onaydan sonra |

Uygulamalar güncellemeyi her zaman `releases/tags/latest` adresinden okur (`lib/online/update_check.dart`). `release.yml` aynı `latest` etiketini, aynı 10 dosya adını (`tools/release/release_files.txt`) ve aynı "Sürüm X · Build: N" metnini kullanır. Bu yüzden eski uygulamalar, VocaBloom adlı eski kurulumlar dahil, güncellenmeye devam eder.

## Bir kez yapılacak ayar: "production" ortamı

`release.yml`, bu ortamda **zorunlu onaylayıcı** tanımlı değilse yayına başlamaz. Bu kontrolü `prepare` işindeki "Approval is really required" adımı yapar.

1. GitHub'da depo > **Settings > Environments > New environment**, adı: `production`.
2. **Required reviewers**: `hamitgk-beep` (ve isterseniz başka biri). **Prevent self-review** kutusunu işaretlemeyin. Tek onaylayıcı siz olduğunuz için o kutu işaretliyse yayını hiç onaylayamazsınız; iş akışı bu durumu da yakalayıp durur.
3. **Deployment branches and tags**: *Selected branches and tags* > `main`.
4. Önerilir: **Settings > Actions > General > Workflow permissions** = *Read repository contents and packages permissions*. İzinlerini kendisi yazmayan iş akışları (`ai-key-smoke`, `voice-perf`, `update-windows`, `voice-windows`, `tutor-inspect`) zaten hiçbir şey yazmıyor. Yazan iş akışları gerekli izni dosyalarında açıkça istiyor, bu yüzden bu ayar bir şeyi bozmaz.

## Yeni sürümü yayımlamak

1. Değişiklik PR olarak açılır. `build.yml` testleri, derlemeleri ve **yayın kuru çalıştırmasını** geçmelidir. `package` işinin özetinde sürüm, build numarası ve 10 dosyanın SHA-256 değerleri görünür; `release-preview` artefaktında yayın metni (`body.md`) vardır.
2. PR `main`'e birleştirilir. Bu adım **yayın yapmaz**, yalnızca `main` için `build.yml` çalışır.
3. Bu `build.yml` çalıştırması tamamen yeşil olunca: **Actions > release > Run workflow** (dal: `main`).
   - `confirm`: `YAYINLA`
   - `build_run_id`: boş bırakılırsa `main`'in en son başarılı derlemesi alınır. Belirli bir derleme için çalıştırma numarasını değil, adres çubuğundaki uzun **run id**'yi yazın.
   - `allow_older`: yalnızca geri almada işaretlenir.
4. `prepare` işi her şeyi kontrol eder: başlatan kişi, onay ayarı, derlemenin `main`'den ve başarılı olması, build numarasının yayındakinden büyük olması. Sonra `publish` işi **onay bekler**. Özetteki sürüm ve build numarasını kontrol edip **Review deployments > Approve** ile onaylayın.
5. `publish` işi dosyaları indirir, paketler, yeniden doğrular ve eski `latest` yayınının kaydını `release-record` artefaktına koyar. Ardından yayını değiştirir ve yayımlanan dosyaların boyutlarını, hedef commit'i ve build numarasını tekrar kontrol eder.

Yeniden derleme yapılmaz. Kullanıcıya giden dosyalar, testleri geçen `build.yml` çalıştırmasının dosyalarıdır. Build numarası da o çalıştırmanın numarasıdır, yani uygulamanın içine gömülü sayıyla aynıdır.

## Neler yayını başlatamaz

- `main`'e push, PR birleştirmesi, `build.yml`'yi elle başlatmak.
- `dictionary-data` (şu an kapalı). Açılırsa `main`'e push edip `build.yml`'yi başlatır; bu artık yalnızca derleme demektir.
- Başka bir iş akışı veya bot. `release.yml` yalnızca `workflow_dispatch` ile çalışır ve başlatan kişi depo sahibi değilse durur; `GITHUB_TOKEN` ile başlatılan çalıştırmalarda başlatan `github-actions[bot]` olur. Ayrıca `build.yml`'deki kontrol (`release_check.py check-workflows`), `release.yml` dışındaki hiçbir iş akışının `latest` yayınını değiştiren veya `release.yml`'yi başlatan bir komut içermediğini her PR'da doğrular.
- Başka yayınlar bu süreçten etkilenmez ve onlara dokunulmaz: `voice-models` (ses paketleri), `data-*`, `tutor-models`. Bunları kendi iş akışları yönetir.

## Geri alma

Uygulamalar yalnızca **daha büyük** build numarasına güncellenir. Kötü bir sürümü düzeltmenin iki yolu var:

1. **Önerilen, ileri düzeltme:** Hata düzeltilir, PR birleştirilir, yeni derleme yayımlanır. Bozuk sürümü kurmuş olanlar da düzeltmeyi alır.
2. **Hızlı geri dönüş:** `release.yml` önceki iyi derlemenin run id'siyle ve `allow_older` işaretli çalıştırılır. Yeni indirenler eski iyi sürümü alır. Bozuk sürümü **zaten kurmuş** cihazlar geri inmez (numaraları daha büyük), onlar için yine 1. yol gerekir.

Önceki yayının adı, metni, hedef commit'i ve dosya listesi her yayında `release-record` artefaktında 90 gün saklanır. Derleme dosyaları ise `build.yml` çalıştırmasında GitHub'ın varsayılan süresince (90 gün) durur. Daha eski bir derleme yeniden yayımlanamaz; onun için o commit'ten yeni bir derleme gerekir.

## Hata durumları

| Durum | Ne olur | Ne yapılır |
|---|---|---|
| `confirm` yanlış, başlatan sahibi değil, dal `main` değil | `prepare` durur, hiçbir şey değişmez | Doğru değerlerle yeniden başlatın |
| `production` ortamında onaylayıcı yok, ortam yok ya da okunamıyor | `prepare` durur, hiçbir şey değişmez | Yukarıdaki bir kerelik ayarı yapın |
| Derleme başarısız, PR derlemesi veya başka daldan | `prepare` durur | Yeşil bir `main` derlemesi seçin |
| Build numarası yayındakinden küçük veya aynı | `prepare` durur | Daha yeni derleme seçin, geri alma ise `allow_older` işaretleyin |
| Onay verilmez veya reddedilir | `publish` hiç başlamaz, yayın aynen kalır | Gerek yok |
| Dosya eksik, bozuk, iOS çeviri paketi yok, metinde build yanlış | `publish` yayına dokunmadan önce durur | Derlemeyi düzeltin |
| Eski yayın silindikten sonra yükleme yarıda kalır | Kısa süre `latest` yok ya da eksik dosyalı. Uygulamalar güncelleme bulamaz, bir şey bozulmaz. Kullanıcı verisi etkilenmez | Aynı `build_run_id` ile `release.yml`'yi yeniden çalıştırın (aynı build olduğu için `allow_older` işaretleyin). Kayıt `release-record` artefaktında |
| Yayın tamamlandı ama son kontrol uyuşmazlık buldu | İş kırmızı olur | Aynı şekilde yeniden çalıştırın |

## Bilinen sınırlar

- Yayımlama, eski yöntemle aynıdır: `latest` önce silinir, sonra yeniden oluşturulur. Arada kısa bir boşluk olur. Bu, mevcut uygulamaların okuduğu yapıyı değiştirmemek için bilerek korundu.
- `release.yml` ancak `main`'de olduğunda başlatılabilir. Bu yüzden ilk gerçek deneme birleştirmeden sonra yapılabilir. Mantığı `tools/release/test_release_check.py` testleri ve PR'daki kuru çalıştırma sınar.
- #103 eski `release` işine dosya ekliyor (işlemciye göre APK, Windows manifesti). Bu PR birleşince #103'ün bu kısmı `tools/release/package.sh`, `release_files.txt` ve `release.yml`'ye taşınmalıdır.
