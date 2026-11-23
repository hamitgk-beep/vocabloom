# Deyim içindeki kelime kartlarının otomatik onayı (Görev 5J)

Tarih: 23 Kasım 2026. Temel: PR #119 (Görev 5I) head `cc6a9ae`; bu dal onun üstünde (stacked: #116 → #117 → #118 → #119 → 5J).
Flutter 3.50.0 (bulut makinesi, Linux). Önceki PR'lar birleştirilmedi, rebase edilmedi.

## 1. Kısa sonuç

- **Kök neden bulundu:** tekrar kartı (`ReviewQuiz` → `SenseEngine.fit`) kelimeyi cümlede **tek başına** çözüyor
  (`resolve`), kelime panelinin kullandığı `resolveTap` yolunu (cümledeki kalıplara bakan) hiç kullanmıyor. Bu yüzden
  panel "ayırt edemiyor" derken kart aynı cümlede "run = koşmak"ı doğru sayıyordu.
- **Genel bir koruma yazıldı** (`SenseEngine.wordCardGuard` + `cardCarries`): kelime, cümlede eşleşen ve motorun kalıp
  olarak okuduğu (ya da ayırt edemediği) bir kalıbın içindeyse ve kalıbın kendi **kontrollü Türkçesi** kartın cevabını
  taşımıyorsa ("in prison" = "hapiste" ⊃ "hapis" taşır; "give up" = "vazgeçmek" "vermek"i taşımaz), kart otomatik
  puanlanmıyor; düz kart olarak gösteriliyor, nedenini söylüyor, öğrenci kendisi puanlıyor. Kelime paneli de bu durumda
  karta "kesin" anlam kaydetmiyor. Özel liste, cümle, eşik yok.
- **Ama kilitli finalde kabul kriterini geçemedi → varsayılan KAPALI** (`defaultWordCardGuard = WordCardGuard.off`).
  Üretim davranışı 5I ile birebir aynı. Neden: finalde engellenen 17 "deyimsel cümlede kelime onayı"nın elle okununca
  yalnız ~3'ü gerçekten yanlıştı ("catch fire"da "fire = ateş", "in the long term"de "long = uzun" doğru); buna karşılık
  düz cümlelerde 93 doğru onaydan 70'i kayboldu. MAGPIE'nin "deyimsel" etiketi kartın cevabının yanlış olduğunu
  kanıtlamıyor (görev tanımının uyardığı gibi).
- Dar yedek aday (`WordCardGuard.undecided`: yalnız panelin "ayırt edemiyor" dediği yerde puanlama) hiçbir kümede
  kayda değer doğru onay kaybettirmedi ama finalde yalnız 1 kartı değiştirdi (p = 1) → o da kriter gereği **kapalı**.
- Yanlış "kesin" anlam, yanlış otomatik kalıp kartı onayı, kalıp okumaları: hiçbir ayarda değişmiyor (0 yeni onay).
  İki DB'nin SHA-256'sı başta ve sonda aynı. Yeni bağımlılık, ağ, model, veri yok.

## 2. Akış haritası (koddan)

| adım | dosya:satır (bu dal) | ne yapıyor |
|---|---|---|
| kelime paneli kartı | `lib/ui/context_sense_card.dart` `ContextSenseCard.resolve` | kelime tıklanınca `senses.resolveTap(q, ctx.matches)`: kelimeyi tutan kalıp düz okunduysa onun okuması, "ayırt edemiyor"sa o, yoksa kelime tek başına |
| panelin karta kaydettiği anlam | `lib/ui/word_sheet.dart` `_savedMeaning` | "Öğreneceğim/Öğrendim": cümlede **sure**, AI taslağı değil ve kelimenin kendisi ise anlam kaydedilir; yoksa `null` (tekrar karar verir) |
| kart kaydı | `AppState.setWord` → `UserDb` | lemma, durum, cümle, kitap, anlam; hangi token'a dokunulduğu **kaydedilmiyor** |
| kartın cevabı | `lib/data/review_quiz.dart` `_answerFor` | kayıtlı anlam ya da sözlüğün yaygın anlamı; cümle varsa `confirms` → `fit` |
| otomatik onay kararı | `lib/nlp/context_sense.dart` `SenseEngine.fit` | tek kelime: `indexOfLemma` (ilk geçiş) → `resolve(q)` → seçilen anlam cevapla aynı/eşanlamlı ise `confirmed`; kalıp: yalnız `sure` ve düz değilse |
| puanlama | `lib/ui/review_page.dart` `_choiceFor`, `_pick`, `_answer` | `choice` true ise dört şık; doğru şık → otomatik `good` → `review.answer` + gerekirse `learned`. `choice` false: düz kart, öğrenci "Hatırlamadım/Zorlandım/Bildim" ile kendisi puanlar (manuel) |
| "Öğrendim" | `word_sheet.dart` `word-learned` | öğrencinin bilinçli manuel işlemi; otomatik kararla ilgisi yok, değiştirilmedi |

Ayrımlar: `sure/likely/none` panelin güveni; kalıp kartı (`lemma` boşluk içerir) yalnız `sure` kalıp anlamıyla onaylanır
(5F'den beri pratikte hiç onaylanmıyor: finalde 0); kelime kartı **`likely` bir anlamla da** onaylanabiliyor. AI taslağı
tek başına onay vermiyor (5B). Provenance kontrolü kartta yok (#114 ayrı).

### Neden 5F–5I korumaları bunu önlemedi (trace)

"The prisoner was on the run for three weeks.", kart `run`, cevap "koşmak":
1. `fit` → `indexOfLemma` → token 4 → `resolve(SenseQuery(index: 4))` (ifade yok) → `_resolveWord`: WordNet/ft
   adayları, "koşma, koşu" önde → `confirmed / same`.
2. Aynı cümlede panel: `resolveTap` → "on the run" kalıbını çözer → 5H `literalGuard`: `SenseGap.idiomOrWords`
   ("ayırt edemiyor") → panel boş. Kart bu yolu hiç çağırmıyor.
3. 5F/5G/5H/5I korumaları yalnız **kalıp okumasını** (ve kalıp kartını) değiştiriyor; `fit`'in tek-kelime dalı
   `fit` içindeki "kelime bir kalıbın parçasıysa" kontrolünü (`(q.expr == null) != (c.cat == null)`) asla tetiklemiyor,
   çünkü `resolve` tek kelimede `cat` her zaman `null` döndürüyor. Kontrol ölü koddu.

### Kenar durumlar (testler: `test/word_card_guard_5j_test.dart`)

- Kısmi/çoklu/örtüşen eşleşme: kelimeyi tutan **iki ve daha fazla sözcüklü** her kalıba bakılıyor; biri yeterli
  ("let the cat out of the bag" + "let out" + "out of").
- Phrasal verb, ayrık ("gave it up"), çekimli, olumsuz ("were not on the run"): matcher'ın bulduğu gibi.
- Alıntı/bahsetme ("The idiom "on the run" means…"): kalıp okunuyor → puanlanmıyor (temkinli).
- Cümle sınırı: matcher `text:` ile cümle içinde kalıyor ("on the. Run home now." eşleşmiyor).
- Aynı kelime iki kez (biri kalıpta): kart hangi geçiş için olduğunu bilmiyor → puanlanmıyor.
- Tek kelime tıklama / dilbilgisi sözcüğü: kendi nedeni ("grammar word") korunuyor.
- Önbellek / sıra: koruma hiçbir okumayı değiştirmiyor, önbellek anahtarına girmiyor; kelime→kalıp→kelime sırası ile
  taze motor aynı sonucu veriyor. (Ölçümde 1 cümlede yalnız tanı metni "pos:-" / "pos:afterPrep" farklı çıktı: kalıp
  önbellek anahtarı tıklanan token'ı içermiyor, önceden var olan durum; karar, güven ve anlam aynı.)
- Cümlesiz eski kartlar: `mainMeaning` yolu, değişmedi.

## 3. Adaylar

| aday | kural | not |
|---|---|---|
| C `undecided` | yalnız panelin "ayırt edemiyor" dediği kalıp (aynı `resolve` kararı) | paneldeki çelişkiyi kaldırır; ikinci motor yok |
| A `idiom` | + motor kalıp anlamını gösteriyorsa (olası/kesin) | |
| B `notLiteral` | motor kalıbı düz okumadıkça | bu verilerde A ile aynı sonuç (motor kalıbı hiç "kesin" okumuyor) |
| D `+c` (`cardCarries`) | kalıbın kontrollü Türkçesi cevabı taşıyorsa engelleme | kalıp Türkçesi + kısa ek / fiil kökü / p-ç-t-k yumuşaması; AI taslağı asla |

Hepsi aynı `SenseEngine.resolve` kalıp kararını kullanıyor (C maddesi); yeni bağımsız karar motoru yok; bayrak
deneysel ve geri alınabilir (D). "Kalıp sözlükte var diye engelle" sonucu, A'nın `+c`'siz hâlidir: sıradan cümlelerde
kartların %6,5'ini kaybettiriyordu ("have breakfast", "make a list", "in prison"); `+c` bunu %2,5'e indirdi.

## 4. Kümeler ve bağımsızlık

| küme | cümle (deyimsel/düz) | kelime kartı | kaynak | kullanım |
|---|---|---|---|---|
| `dev5h`, `tune5h` | 2.666 / 1.419 | 4.503 / 2.559 | 5H kümeleri, hash kontrollü (`5e81b1be…`, `197f7faf…`) | aday seçimi |
| review audit | sözlüğün 1.500 sık kelimesinin örnek cümlesi | 1.496 | `dict.db` `exs` (review_quiz_test ile aynı sorgu) | sıradan cümle regresyonu (geliştirmede de görüldü) |
| **`final5j`** | 240 (49 / 191), 138'inde kalıp bulundu | **229** (60 / 169) | MAGPIE, uzlaşma 0,70–0,99, **5F–5I'nın 9 kümesinin hiçbirinde olmayan** cümleler; deyimler 5F/5G final deyimleri (dev/tune'da yok); deyim+etiket başına ≤ 8 | **tek ölçüm** |
| `hold5j` | 577 (297 / 280) | 550 (385 / 165) | aynı süzgeç, ama deyimler dev/tune deyimleri (yeni cümle, görülmüş deyim) | yalnız rapor, karar dışı |

- Üretim: `tools/nlp_research_5j/build_sets_5j.py` (seed 20261125). 5F/5G/5H/5I kümeleri kendi betikleriyle yeniden
  üretildi ve kilitleriyle doğrulandı (5I final `a50d77ca…` dahil). MAGPIE_unfiltered.jsonl `541ee535…`.
- **Kilit:** `final5j` `27034bd8…`, `hold5j` `1cd67546…`; hiçbir sistem çalışmadan commit edildi (`719dfe6`).
  Kabul kuralı (`tools/nlp_research_5j/ACCEPTANCE_5J.md`) ve aday kod finalden önce donduruldu (`7369d10`). Final ve
  hold bir kez çalıştı; sonra kural/eşik değişmedi, yalnız varsayılan bayrak kuralın sonucuna göre kapatıldı.
- **Sınır:** final deyim *türleri* 5F–5I finallerinde ölçülmüştü (ayar yapılmadı); MAGPIE'de hiç kullanılmamış sözlük
  deyimi yok. Uzlaşma 1,0 cümleler 5A/5B/5E tarafından çekildiği (listeleri yerel) için alınmadı. Final küçük
  (60 deyimsel kelime kartı) ve deyim/düz oranı doğal değil (%26 deyimsel).
- **Etiketler:** MAGPIE yalnız *kalıbın* deyimsel/düz kullanımını etiketliyor (insan, kitle, gürültülü); **kartın
  cevabının doğru olup olmadığını etiketlemiyor**. Bu yüzden değişen kartların bir örneklemi cevabın doğruluğu için
  **Claude (AI) tarafından elle okundu**; bu insan etiketi değildir (§5.3). Testlerdeki cümleleri Claude yazdı, ölçüme
  katılmadılar.
- **Lisans:** MAGPIE etiketleri CC BY 4.0; cümleler BNC, yeniden dağıtılamaz: depoya, teste, rapora cümle konmadı
  (yalnız kalıp adları ve sayılar). Ölçümler bu bulut makinesinde yerel; CI'da koşmaz.

## 5. Sonuçlar (5I motoru = `off` → aday), eşleştirilmiş

Birim: kelime kartı (eşleşen kalıbın her içerik sözcüğü, bir cümlede). "Kart" = gerçek akış: `ReviewQuiz.answerFor`
(cümleli kart, kayıtlı anlam yok) → `choice` (dört şık = otomatik puan). Köşeli parantez Wilson %95 GA; −/+ kaybolan/
eklenen onay; p McNemar kesin. Koruma yalnız veto eder: hiçbir kümede **0 yeni onay**.

### 5.1 Geliştirme (dev + tune, karar burada)

| ölçü | off | C undecided+c | A idiom+c | A idiom (c'siz) |
|---|---|---|---|---|
| deyimsel cümlede kelime onayı | 3.113/6.491 = %48,0 [46,7–49,2] | 3.025 (−88) | **657 (−2.456)** | 286 (−2.827) |
| düz cümlede kelime onayı | 261/571 = %45,7 [41,7–49,8] | 256 (−5, p = 0,06) | 113 (−148) | 74 (−187) |
| sıradan cümle (audit) onayı | 841/1.496 | 841 (0) | 820 (−21 = %2,5) | 786 (−55 = %6,5) |
| panel "ayırt edemiyor" derken kart onaylı | 95 | 0 | 0 | 0 |

Claude'un dev örneklem okuması (30'ar kart): A ile engellenen deyimsel-cümle onaylarının ~19'u yanlış, ~7'si doğru,
~4'ü kısmen; engellenen düz-cümle onaylarının ~28'i doğru; `+c`'nin geri bıraktığı deyimsel-cümle onaylarının ~23'ü
doğru ("buy time"da "time", "green light"ta "green"), ~3'ü yanlış ("hot air"da "sıcak": sözlük girdisi iki anlamı
birleştiriyor). Seçilen aday: **A idiom + carries**; yedek: **C undecided + carries**.

### 5.2 Kilitli final (bir kez)

| ölçü | off | C undecided+c | A idiom+c |
|---|---|---|---|
| deyimsel cümlede kelime onayı (ana güvenlik ölçüsü, MAGPIE vekili) | 29/60 = %48,3 [36,2–60,7] | 28 (−1, p = 1) | **12/60 (−17, p = 1,5·10⁻⁵)** |
| düz cümlede kelime onayı (kayıp = yanlış veto) | 93/169 = %55,0 [47,5–62,3] | 93 (0) | **23/169 (−70, p = 1,7·10⁻²¹)** |
| otomatik puanlanan kartların payı | 122/229 | 121/229 | 35/229 |
| manuel yük (onaylıyken düz karta dönen) | – | 1/122 = %0,8 | 87/122 = %71,3 |
| panelin karta "kesin" anlam kaydetmesi (deyimsel / düz) | 10/60, 30/169 | aynı | 0, 1 |
| yeni onay / yanlış kesin / kalıp kartı onayı | – | 0 / 0 / 0 | 0 / 0 / 0 |
| kalıp okuması ve kalıp kartı kararı farkı | – | 0 (1 tanı metni) | 0 (1 tanı metni) |
| sıradan cümle (audit) kaybı | – | 0/841 | 21/841 = %2,5 [1,6–3,8] |
| gecikme (bu makine, Dart VM, kart başına, önbellek ayrı) | 2,35 ms | 2,79 ms | 2,72 ms |

Deyim/düz prevalansı: final %26, hold %70, dev/tune %92 (kelime kartı bazında). Oranlar kümeler arasında
karşılaştırılırken bu fark akılda tutulmalı.

### 5.3 Cevabın gerçekten yanlış/doğru olduğu (Claude okuması, final)

- A'nın engellediği **17 deyimsel-cümle onayının hepsi** okundu: yalnız **~3'ü yanlış** ("in the long term"de
  "term = terim" ×2, mecazi "caught fire"da "ateş"); ~14'ü doğru ("catch fire"da "fire = ateş" ×4, "in the long
  term"de "long = uzun" ×2, "one of those things"te "şey" ×4, "as a rule"da "kural", "in the saddle"da "eyer" ×2,
  "every last"te "son"). → w_i ≈ 0,18.
- Engellenen 70 düz-cümle onayından rastgele 30'u okundu: ~24'ü doğru, ~6'sı yanlış ("get lost"ta "almak/kaybetmek",
  "I've got a picture"da "almak"). → w_l ≈ 0,80.

### 5.4 Kabul kuralı (önceden dondurulmuş) → KAPALI

| koşul | A idiom+c | C undecided+c |
|---|---|---|
| G1 deyimsel onay azalıyor, p < 0,05 | ✔ (−17, p = 1,5·10⁻⁵) | ✘ (−1, p = 1) |
| G2 yeni onay yok, okumalar aynı | ✔ | ✔ |
| G3 net fayda, π = 0,71 (MAGPIE'nin doğal deyimsel payı), yalnız MAGPIE etiketiyle | ✔ 0,201 > 0,120 | – |
| G3 aynı, cevabın doğruluğu okunarak (w_i = 0,18, w_l = 0,80) | **✘ 0,036 < 0,096** | – |
| G4 sıradan cümle kaybı ≤ %3 | ✔ %2,5 | ✔ %0 |

Başabaş noktası (okunan ağırlıklarla) π ≈ 0,87: kartların ancak %87'ı gerçekten deyimsel cümlelerden geliyorsa net
fayda var. **Karar: her iki aday da varsayılan kapalı.**

### 5.5 hold5j (karar dışı, yeni cümle / görülmüş deyim)

A idiom+c: deyimsel onay 169/385 → 60 (−109), düz onay 75/165 → 42 (−33). C undecided+c: −4 / −1. Geliştirme
kümelerine benzer; finaldeki "doğru onaylar engelleniyor" bulgusunu ne doğruluyor ne çürütüyor (okunmadı).

## 6. Güvenlik, ödünleşim, neden kapalı

- Motor deyim/düz ayrımını hâlâ zayıf yapıyor: düz MAGPIE cümlelerinin %74–77'sinde kalıbı "olası deyim" okuyor. Bu
  yüzden motorun okumasına dayanan her koruma, düz kullanımdaki doğru kartları da büyük ölçüde engelliyor (yanlış veto).
- MAGPIE'nin "deyimsel" etiketi kelime kartının yanlış olduğunu göstermiyor: "catch fire", "in the long term" gibi
  yarı-saydam deyimlerde kelimenin kendi anlamı doğru. `+c` bunun bir kısmını kalıbın Türkçesinden yakalıyor, hepsini
  değil.
- Bir yanlış onay, bir doğru onayın kaybından daha kötü sayılabilir (yanlış bilgi "öğrenildi" kaydına giriyor; kayıp
  yalnız kartı manuel yapıyor). 1:1 ağırlıkla bile finalde fayda yok; 2:1 ile de yok (0,072 < 0,096). Ürün kararı
  olarak 5:1 ve üstü bir ağırlık seçilirse A açılabilir; bu ölçümle önermiyorum.
- Kapalıyken: kart davranışı, kayıtlar, panel 5I ile birebir aynı (testle sabit).

## 7. Arayüz (yalnız koruma açıkken görünür)

- Tekrar ekranı: kart dört şıklı soru yerine düz kart; cevap açılınca nötr not: "Bu cümlede kelime “on the run”
  kalıbının parçası olabilir; tek başına anlamı bu cümle için doğrulanamadı. Bu kart otomatik puanlanmıyor, kendin
  değerlendirebilirsin." (EN: "In this sentence the word may be part of the expression …; … This card is not graded
  automatically; you can rate it yourself."). Mevcut `review-unconfirmed` notunun yerini alıyor (aynı stil:
  `bodySmall`, `onSurfaceVariant`, italik; ekran okuyucu düz metin okur). Manuel "Hatırlamadım/Zorlandım/Bildim"
  aynen çalışıyor ve kaydı aynı yoldan yapıyor (testli).
- Kelime paneli: "Öğreneceğim" kartı yine cümlesiyle kaydediyor, yalnız "kesin" anlamı kaydetmiyor (tekrar karar
  verir). "Öğrendim" öğrencinin kendi seçimi olarak kalıyor.
- TR/EN, açık/koyu, 320 px widget testi; ekran görüntüleri (test çıktısı, gerçek cihaz değil): proje dosyalarında
  `kelime-karti-5j/`. Gözlenen, değiştirilmeyen: kartta "koşmak" altında "a score in baseball…" İngilizce tanımı
  görünüyor (yaygın anlamın Türkçesi ile WordNet tanımı farklı duyulardan; önceden var).

## 8. Testler ve doğrulama

- Yeni `test/word_card_guard_5j_test.dart` (19 test, cümleler Claude'un): varsayılanlar (5G/5H/5I bayrakları aynı,
  5J kapalı, kapalıyken "on the run" kartı 5I gibi onaylı); koruma açıkken deyim içi kart, düz "hot air rises",
  kalıpsız cümle, phrasal verb (bitişik/ayrık/çekimli), olumsuzluk ve bahsetme, `exprCarries` (ek, fiil kökü,
  yumuşama, AI taslağı asla), aynı kelime iki kez, cümle sınırı, dilbilgisi sözcüğü, kalıp kartı ve okumalar değişmiyor,
  önbellek ve sıra; `ReviewQuiz` (düz kart + neden, eski kayıtlı anlam korunuyor ve puanlanmıyor, cümlesiz kart
  değişmiyor); ekranlar (TR/EN not, manuel puanın kaydı, 320 px koyu, panelin anlam kaydetmemesi, "Öğrendim").
- `AppState.debugWordCardGuard`: yalnız testlerin korumayı açması için.
- Komutların sonuçları PR açıklamasında (tam `flutter test`, `qa_test`, `analyze`, Python testleri, CI).
- Bilinen ortam sınırı: PDFium bu makinede yok → 3 PDF testi `setUpAll`'da düşüyor (başlangıçta da: 582 geçti /
  12 atlandı / 3 başarısız). Gerçek Android/iOS cihazda ölçüm yapılmadı; kod saf Dart. Bellek: yeni önbellek yok
  (mevcut `resolve` önbelleği, 400 kayıt).

## 9. Yeniden çalıştırma (veri depoda yok)

```
# 1) MAGPIE_unfiltered.jsonl (sha256 541ee535…) indir; 5F→5I kümelerini kendi betikleriyle üret (rapor 5I §4.1)
python3 -I tools/nlp_research_5j/build_sets_5j.py assets/dict.db MAGPIE_unfiltered.jsonl S5F S5G S5H S5I OUT
sha256sum OUT/final5j_magpie.tsv OUT/hold5j_magpie.tsv   # = tools/nlp_research_5j/final5j_LOCKED.sha256
# 2) bütün modlar aynı satırlarda (off, undecided, idiom, notLiteral, +c)
NLP_5J_SETS=dev=OUT/dev5h_magpie.tsv,tune=OUT/tune5h_magpie.tsv,final=OUT/final5j_magpie.tsv \
NLP_5J_AUDIT=1 NLP_5J_OUT=W flutter test tools/nlp_research_5j/dump_5j_test.dart
python3 -I tools/nlp_research_5j/metrics_5j.py W/dev.jsonl W/tune.jsonl --audit W/audit.jsonl
python3 -I tools/nlp_research_5j/metrics_5j.py W/final.jsonl [--show idiom+c 30]   # --show: yalnız yerel
```

## 10. Veri, bağımlılık, çevrimdışı

- `assets/dict.db` SHA-256 `ab4a7a53b9fc5e1edbd682da5cb7193c0c109f93236655385bf6231d90221a9c`, `assets/tr_en.db`
  `49a661b9c8951259ab13fd6a95aa77b68e16f1c4716669dacfb6c12521cfa818`: başta ve sonda aynı.
- Kullanıcı verisi, kart kayıtları, şema: değişmedi. Yeni paket, model, ağ çağrısı, telemetri yok; çevrimdışı.
- `SenseEngine.version` değişmedi; koruma okumaları değiştirmediği için önbellek anahtarına girmiyor.
- Bulunan, değiştirilmeyen veri sorunları: "in prison" Türkçesi "hırpiste yatmak" (yazım hatası); "hot air" girdisi
  iki anlamı tek satırda birleştiriyor (5I'da da not edildi). #114 provenance/lisans kapısı çözülmüş sayılmadı.

## 11. Varsayılanlar ve geri dönüş

| bayrak | varsayılan | anlamı |
|---|---|---|
| `defaultLiteralCues` (5G), `defaultLiteralGuard` (5H) | açık | değişmedi |
| `defaultIdiomRecovery`, `defaultHeadFromPattern` (5I) | kapalı | değişmedi |
| `_ExprCardState.showMaybeNotHere` (5I UI) | açık | değişmedi |
| `SenseEngine.defaultWordCardGuard` (5J) | **`off`** | `idiom` / `undecided` / `notLiteral` deneysel |
| `SenseEngine.defaultCardCarries` (5J) | açık | yalnız koruma açıkken etkili |

Geri dönüş: koruma zaten kapalı; kodu tümüyle kaldırmak için `fit`'teki 5J bloğu, `cardBlocker`/`exprCarries`,
`QuizAnswer.inExpression`, `review_page` notu ve `_savedMeaning` kontrolü silinir (kayıt formatı değişmediği için veri
göçü gerekmez).

## 12. Kalan riskler ve öneriler

- **Asıl açık hâlâ açık:** deyimsel cümlelerde kelime kartları %44–48 oranında otomatik onaylanıyor; bunların bir
  kısmı doğru (yarı-saydam deyimler), bir kısmı yanlış. Payı MAGPIE ile ölçülemiyor.
- Öneri 1: kart düzeyinde **cevap etiketi** olan küçük, izinli/lisanslı, insan tarafından okunmuş bir küme (ör. kendi
  kitaplardan 300–500 kelime kartı; "bu cümlede kelimenin bu anlamı doğru mu?"), deyim/düz oranı doğal. Ardından
  `undecided+c` (en az zararlı) ve `idiom+c` yeniden ölçülmeli.
- Öneri 2: kelime paneli deyimsel cümlelerde de kelimeye **"kesin"** anlam gösterebiliyor (dev+tune %21,6, final
  10/60): kartın kaydettiği anlam da buradan geliyor. Panel ve kartın tek bir ortak analiz sonucunu kullanması
  (görevde belirtilen sonraki mimari iş) bunun doğal yeri.
- Öneri 3: kart kaydına tıklanan token konumunu eklemek, "aynı kelime iki kez" belirsizliğini kaldırır (şema değişikliği,
  ayrı onay gerekir).

## 13. Değişen dosyalar

- `lib/nlp/context_sense.dart`: `WordCardGuard`, `wordCardGuard` (kapalı), `cardCarries`, `cardBlocker`,
  `blocksWordCard`, `exprCarries`; `fit` 5J bloğu; `AnswerFit.inExpression`.
- `lib/data/review_quiz.dart`: `QuizAnswer.inExpression`. `lib/ui/review_page.dart`: not. `lib/ui/word_sheet.dart`:
  `_savedMeaning`. `lib/app_state.dart`: `debugWordCardGuard` (test).
- `test/word_card_guard_5j_test.dart` (yeni).
- `tools/nlp_research_5j/`: `build_sets_5j.py`, `final5j_LOCKED.sha256`, `ACCEPTANCE_5J.md`, `dump_5j_test.dart`,
  `metrics_5j.py` (veri yok).
- `docs/nlp_engine_research/IDIOM_WORD_CARD_SAFETY_5J.md`.
