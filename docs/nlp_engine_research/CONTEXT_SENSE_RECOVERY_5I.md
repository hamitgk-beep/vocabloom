# Bağlamsal anlam kurtarma ve "doğrulanmış anlam" arayüzü (Görev 5I)

Tarih: 23 Kasım 2026. Temel: PR #118 (Görev 5H) head `43ca22a`; bu dal onun üstünde (stacked: #116 → #117 → #118 → 5I).
Flutter 3.50.0 (bulut makinesi, Linux). Önceki PR'lar birleştirilmedi, rebase edilmedi.

## 1. Kısa sonuç

- **"on the run" vakasının kök nedeni bulundu ve genel bir kural yazıldı, ama kilitli finalde desteklenmediği için
  varsayılanı KAPALI** (`SenseEngine.defaultIdiomRecovery = false`). Üretimde davranış 5H ile aynı kalıyor;
  "The prisoner was on the run for three weeks." hâlâ "ayırt edemiyor" diyor.
- **"hot air" vakası (UI) düzeltildi, açık:** "Bu cümledeki kalıplar" listesinde motorun düz okuduğu bir kalıp artık
  sakin bir notla gösteriliyor: "Bu cümlede kalıp olarak kullanılmamış olabilir; kelimeler düz anlamında görünüyor.
  Kalıp olarak anlamı:" (EN: "It may not be used as an expression in this sentence; …"). Deyim anlamı silinmiyor,
  yalnız daha küçük puntoyla notun altında. Geri dönüş: `_ExprCardState.showMaybeNotHere = false`.
- **"in the hole" vakası:** kök neden doğrulandı (baş sözcüğün taban biçimi kalıbın *ilk* sözcüğünden, "in"den
  alınıyor: inç, indiyum, Indiana). Düzeltme (`headFromPattern`) dev/tune'da ölçülebilir fayda vermedi, hatta
  "in the hole" düz cümlesinde AI taslağı deyim anlamını öne çıkardı; **kapalı, araştırma olarak bırakıldı.**
- Yanlış "kesin" (deyim ve düz), yanlış otomatik kart onayı: finalde 0 → 0 (değişmedi). Yeni bağımlılık, ağ, model,
  veri değişikliği yok; iki DB'nin SHA-256'sı başta ve sonda aynı.
- Yan bulgu (önceden var, bu görevde değiştirilmedi): **kelime kartı**, kelime bir deyimin içindeyken de kelimenin tek
  başına anlamıyla puanlanıyor ("on the run" cümlesinde "run = koşmak" kartı onaylanıyor). Ölçüm §6.3.

## 2. Kök neden (gerçek kod ve DB üzerinden)

Tanılama aracı: `tools/nlp_research_5i/trace_test.dart` (yalnız `assets/dict.db` okur, kullanıcı verisi yok; her aday için
kategori, kaynak, taslak mı, Türkçe, lemma/POS, skor bileşenleri ve karar gerekçesi yazar).

### A) "The prisoner was on the run for three weeks."

| aday | tür | Türkçe | skor | bileşenler |
|---|---|---|---|---|
| `wn:81903` run = "bir makinenin çalıştığı süre" | düz (WordNet) | **yok** | **0,415** | sem 0,35 (yalnız "~period, ~hour": "weeks"in tanımından gelen tesadüfi örtüşme), fr 0,09 |
| `ex:on the run#0` "Fleeing." | kalıp (expr tablosu) | firarda, kaçmakta, koşturmaca içinde | 0,410 | sem 0, örnek 0 ("prisoner" ile "suspect/robbery" örtüşmüyor) |
| `wn:1402` koşma, koşu | düz | var | 0,376 | |

- Fark 0,005. 5G'nin "deyim mi düz mü, yakınsa deyimi tahmin olarak göster" kuralı (`_idiomOrWords = 0,06`) zaten var,
  ama yalnız **önde giden düz okumanın Türkçesi varken** çalışıyor (`r.confidence != none` koşulu). Burada lider
  Türkçesiz olduğu için kural atlanıyor, 5H koruması da "ayırt edemiyor" diyor (`SenseGap.idiomOrWords`).
- Kategori: (i) doğru deyim varken yanlış literal seçimi + (v) bağlamdan zayıf ayrım. Veri eksikliği değil.
- **Kaynak durumu:** "on the run" Türkçesinin provenance'ı **bilinmiyor** (`inventory.py`, ham girdiler olmadan:
  kaikki / KeNet / FreeDict / AI ön çevirisi ayırt edilemiyor; `entr` alanı `ai_pretranslate`). Motor bunu "AI taslağı
  değil" anlamında *checked* sayıyor (`own_expr` taslağı değil), lisans/kaynak anlamında doğrulanmış değil.

### B) "Hot air rises and cold air sinks."

- Motor doğru karar veriyor: düz okuma "sıcak" (olası; 5H'den beri asla kesin değil). Sorun arayüzde: kelime panelinin
  altındaki "BU CÜMLEDEKİ KALIPLAR" listesi (`ExprCard`, `word_sheet.dart` ve `sentence_sheet.dart`) motora hiç
  sormuyor; kalıp yüzeyde bulunduysa sözlük anlamını ("boş laf, palavra; sıcak hava") büyük ve kalın gösteriyor.
  Kategori (vi) UI yanlış izlenimi.
- Not: "hot air" sözlük girdisi iki anlamı tek satırda birleştiriyor (`expr_fixes.TR`: "boş laf, palavra; sıcak hava").
  Veri değiştirilmedi.

### C) "Pour the water back in the hole and press the soil down."

- `_resolvePhrase` düz okumanın baş sözcüğü olarak "hole"u seçiyor, ama taban biçim adayına önce kalıbın **ilk**
  sözcüğünü ("in") ekliyor; "in"in WordNet anlamları (indiyum 0,492 "~soft" tesadüfi örtüşmesiyle, inç) yarışıyor.
  Kategori (iv) yanlış baş sözcük/lemma.
- Kalıbın Türkçesi yalnız AI taslağında var (`own_expr`, `ai_draft_unreviewed`), yani "doğrulanmış Türkçe yok".
- Aynı hata "over the hill", "in the running", "in the offing" gibi edatla başlayan kalıplarda da görülüyor (§7 kuyruğu).

## 3. Denenen çözümler (karar yalnız 5H dev/tune'da)

| # | aday | dev (2.202 deyimsel / 464 düz) | tune (1.203 / 216) | karar |
|---|---|---|---|---|
| R1 | **idiomRecovery**: Türkçesiz düz lider ile *checked* (AI taslağı olmayan) deyim anlamı arasındaki fark ≤ 0,06 (mevcut sabit) ve 5G biçim işareti / bahsetme / isim öbeği devamı yoksa deyim anlamını "olası" göster; kelime paneli de aynı tahmini göstersin | deyim recall +16/−0 (p = 3·10⁻⁵); düz cümlede deyim +1/−0; boş panel −17; kesin/kart 0 → 0 | recall +6/−0; düz cümlede deyim 0; boş −6 | **dev/tune'da seçildi, finalde başarısız → kapalı** |
| R2 | **headFromPattern**: baş sözcüğün taban biçimi kalıptaki kendi sözcüğünden | recall +10/−13; doğru+kaynaklı deyim +1/−6; boş ±0 (+12/−12) | recall +6/−10; doğru+kaynaklı −5 | **ret** (fayda yok; "in the hole" düz cümlesinde AI taslağı "borçlu"yu öne çıkarıyor) |
| R1+R2 | ikisi birlikte | recall +25/−12, boş +10/−28 | recall +11/−5 | **ret** (R1'den kötü) |
| R1' | R1'in ilk hâli: kelime paneli kelimenin kendi anlamına düşüyordu | kelime panelinde AI taslağı +11 ("run" → "koşmak") | +4 | **düzeltildi**: kelime paneli kalıbın tahminini gösteriyor (AI taslağı +0) |

Hiçbir aday bir cümleye ya da kalıba özel liste/çeviri içermiyor; R1 yalnız mevcut adayların skorlarına ve kaynak
türüne bakıyor. Yeni eşik yok (5G'nin `_idiomOrWords` sabiti kullanıldı).

## 4. Bağımsız final (tek çalıştırma)

### 4.1 Küme ve kilit

| küme | cümle | deyim | kaynak | kullanım |
|---|---|---|---|---|
| `dev5h_magpie.tsv`, `tune5h_magpie.tsv` | 2.666 / 1.419 | 402 / 218 | 5H'nin kümeleri, değiştirilmeden (hash kontrollü) | aday tasarımı ve seçimi |
| **`final5i_magpie.tsv`** | **615 (165 deyimsel / 450 düz)** | **97** | MAGPIE, uzlaşma 0,70–0,99, **5F/5G/5H'nin hiçbir kümesinde olmayan** cümleler, deyim+etiket başına ≤ 8 | **tek ölçüm** |

- Üretim: `tools/nlp_research_5i/build_sets_5i.py` (seed 20261124). 5F/5G/5H kümeleri kendi betikleriyle yeniden
  üretildi ve kilit hash'leriyle doğrulandı (5F `6874e650…`, 5G `ce55c3bb…`, 5H dev `5e81b1be…`, tune `197f7faf…`,
  final `d479d256…`). MAGPIE_unfiltered.jsonl `541ee535…`.
- **Kilit:** final hash'i `a50d77ca95384f9e83098b95f7923180f2865d15e9b03d2d3dbb51e3f8b446a0`, hiçbir sistem çalışmadan
  commit edildi (`b1dad3c`, `final5i_LOCKED.sha256`). Aday kod finalden önce donduruldu (`c587450`). Baseline (5H motoru)
  ve aday aynı satırlarda **birer kez** çalıştı; sonra hiçbir kural/eşik değişmedi. Yalnız varsayılan bayrak kararı
  finale göre verildi (go/no-go; görev tanımındaki "literal precision'da gerileme olmamalı" ölçütü).
- **Cümle bağımsızlığı:** 0 ortak cümle (5F/5G/5H'nin 8 kümesiyle). **Deyim bağımsızlığı:** final deyimleri dev/tune'da
  yok (0). **Sınır:** final deyim *türleri* 5F/5G/5H finallerinde ölçüldü (hiçbirinde ayar yapılmadı); MAGPIE'de hiçbir
  önceki görevde kullanılmamış sözlük deyimi kalmadı. Bu yüzden final "yeni deyim türü" kanıtı değil, "yeni cümle" kanıtı.
- **Etiketler:** MAGPIE kitle etiketleri (insan, çoğunluk oyu, gürültülü). `test/context_recovery_5i_test.dart` ve UI
  testlerindeki cümleleri **Claude yazdı (AI)**; insan etiketli veri değil ve hiçbir ölçüme katılmadı.
- **Lisans:** MAGPIE etiketleri CC BY 4.0; cümleler BNC, yeniden dağıtılamaz: depoya hiçbir cümle konmadı.

### 4.2 Sonuçlar (5H motoru → R1 açık), eşleştirilmiş

Komutlar: `NLP_5I_MODE=base|rec NLP_5I_SETS=final=…/final5i_magpie.tsv NLP_5I_OUT=… flutter test
tools/nlp_research_5i/dump_5i_test.dart`, sonra `python3 -I tools/nlp_research_5i/metrics_5i.py base.jsonl rec.jsonl`.
Köşeli parantez Wilson %95 GA; "+/−" düzelen/bozulan satır; p McNemar kesin testi.

| ölçü | 5H (baseline) | R1 açık | eşleştirilmiş |
|---|---|---|---|
| kalıp bulunan satır | 363 / 615 | aynı | |
| deyim recall | 93/165 = %56,4 [48,7–63,7] | 94/165 = %57,0 | +1 / −0, p = 1 |
| deyim precision / F1 | %37,1 / 44,7 | %36,6 / 44,5 | |
| **düz cümlede deyim gösterimi** | 158/450 = %35,1 [30,8–39,6] | **163/450 = %36,2** | **+5 / −0, p = 0,06** |
| yanlış kesin deyim (düz cümle) | 0/450 | 0/450 | 0 / 0 |
| yanlış kesin düz okuma (deyim cümlesi) | 0/165 | 0/165 | 0 / 0 |
| yanlış otomatik kalıp kartı onayı | 0/273 | 0/273 | 0 / 0 |
| doğru kesin kapsamı (bulunan satırlarda "kesin") | 0/363 | 0/363 | 0 / 0 |
| boş Türkçe panel (bulunan satır) | 29/363 = %8,0 [5,6–11,2] | 23/363 = %6,3 | −6, p = 0,03 |
| "ayırt edemiyor" | 16/363 = %4,4 | 10/363 = %2,8 | −6, p = 0,03 |
| gereksiz "ayırt edemiyor" (deyim cümlesi, checked Türkçe var) | 1/64 | 0/64 | −1 |
| doğru + kaynaklı deyim anlamı (deyim cümlesi; AI taslağı/türetilmiş değil) | 54/165 = %32,7 | 55/165 = %33,3 | +1 |
| doğru + kaynaklı düz okuma (düz cümle) | 54/450 = %12,0 | 54/450 | 0 |
| anlamlı anlam kaybı (deyim cümlesine kelime anlamı) | 29/165 | 29/165 | 0 / 0 |
| kelime paneli: AI taslağı Türkçe gösterimi | 26/363 | 26/363 | 0 / 0 |
| gecikme (bu bulut makinesi, Dart VM, kalıp başına, tek ölçüm) | 3,38 ms | 3,38 ms | gürültü içinde |

**Yorum:** Finalde R1'in değiştirdiği 6 satırın **5'i düz cümleydi** ("go to town", "in the clear", "on and off",
"on the ball", "see the light"); yalnız 1'i ("fly the flag") gerçek deyim. Dev/tune'da oran 22 doğru / 1 yanlış idi.
Fark örneklem dağılımından: dev/tune'un %83'ü deyimsel cümle, final'in %27'si. "Ayırt edemiyor" satırlarının çoğu
dev'de deyimsel (61/66), finalde düz (13/16). Yani R1'in faydası gerçek kitaplardaki deyim/düz oranına bağlı ve bu
oran bilinmiyor. Görev ölçütü "literal precision'da belirgin gerileme olmamalı" idi: +5/−0 anlamlılık sınırında
(p = 0,06) ama yön açıkça olumsuz ve kazanç 1 satır. **Karar: varsayılan kapalı.** Bütün güvenlik ölçüleri (kesin,
kart) her iki ayarda da 0.

### 4.3 Arayüz notunun doğruluğu (açık)

Not, motor kalıbı düz okuduğunda (`literalPhrase != null`) çıkıyor; motorun kararı 5H ile aynı, not yalnız onu görünür
yapıyor. "Doğru not" = MAGPIE'ye göre gerçekten düz cümle.

| küme | notun çıktığı satır | doğru (düz) | yanlış (deyimsel) | isabet |
|---|---|---|---|---|
| dev | 247 / 2.134 | 68 | 179 | %27,5 |
| tune | 132 / 1.211 | 34 | 98 | %25,8 |
| **final** | 96 / 363 | 64 | 32 | **%66,7** |

İsabet yine deyim/düz oranına bağlı. Notun metni bu yüzden "olabilir" diyor ve deyim anlamını gizlemiyor; üstteki kart
(5H) zaten aynı satırlarda "büyük olasılıkla kelimelerin düz anlamıyla kullanılmış" diyordu, yani yeni bir iddia
eklenmiyor, iki kart arasındaki çelişki kalkıyor. Bu notun açık kalması bir ürün kararıdır; kapatmak tek satır.

## 5. UI / okuma deneyimi

- Değişen: yalnız `ExprCard` (kelime paneli ve cümle analizi altındaki "Bu cümledeki kalıplar") ve `PanelHeading`.
- Not: `Icons.info_outline` + `bodySmall`, `onSurfaceVariant` rengi (açık/koyu temada temanın kendi kontrast rengi);
  deyim anlamı 17/w700 yerine 15,5/w600. Ekran okuyucu notu düz metin olarak okur (ikon dekoratif).
- TR/EN metinler `L(...)` ile; iki dilde test edildi.
- Dar ekran: 320 px'te ve İngilizce arayüzde 390 px'te, "EXPRESSIONS IN THIS SENTENCE" başlığı **önceden de** taşıyordu
  (1 px / 22 px). `PanelHeading` artık uzun başlığı alt satıra kaydırıyor (çizgi en az 24 px kalıyor).
- Ekran görüntüleri (test çıktısı, gerçek cihaz değil): proje dosyalarında `baglamsal-anlam-5i/`
  — `tr_hot_air_kalip_notu_5i.png` (açık), `tr_hot_air_kalip_notu_dark_5i.png`, `en_hot_air_note_dark_5i.png`,
  `tr_hot_air_deyim_5i.png` (deyimsel cümlede not yok), `tr_in_the_hole_cannot_tell_5i.png`.
- Gözlenen ama değiştirilmeyen: ExprPanel'in "Kelimelerin düz anlamı" kutusu "on the run" için "run (+ on the) — a
  score in baseball … / deneme" gösteriyor (İngilizce tanım ile Türkçe farklı anlamlardan). Önceden var; ayrı iş.

## 6. Türkçe kapsama ve kaynak raporu (salt-okunur)

Araç: `tools/nlp_research_5i/coverage_5i.py` + `tools/lexicon_provenance/inventory.py` (ham girdiler olmadan).
Kuyruk: `docs/nlp_engine_research/review_queue_5i.tsv` (103 kalıptan en sık 100'ü; yalnız kalıp adı ve sayılar,
cümle yok). Hiçbir anlam onaylanmadı, DB'ye hiçbir şey yazılmadı.

### 6.1 Boş panellerin nedenleri (5H motoru; dev + tune + final, bulunan 3.708 satır, boş 152)

| neden | deyimsel | düz | toplam |
|---|---|---|---|
| **yalnız AI taslağı Türkçe var** (`own_expr`, incelenmemiş) | 64 | 27 | 91 |
| **doğru anlam var ama sıralama seçemiyor** (checked Türkçe var, Türkçesiz düz okuma önde) | 41 | 15 | 56 |
| hiç Türkçe yok | 5 | 0 | 5 |

"Sıralama seçemiyor" grubundaki 56 satırın kalıp Türkçesinin kaynağı: **bilinmiyor 47**, Storilex kategori listesi 6,
Storilex katkısı 1, exd (yerleşik anlam açıklaması) 2. Yani R1 açılsa bile gösterilecek Türkçelerin çoğunun
provenance'ı belirsiz; motor bunları "AI taslağı değil" diye ayırıyor, lisans/kaynak açısından doğrulanmış değil.

### 6.2 Kaynak durumu (envanter, dict.db)

- Kelime ana anlamları (`ft`): 83.381 terim yalnız **damdafayton** (lisansı belirsiz, #114), 21.403 yalnız Kindle
  Wiktionary, 12.345 ikisinde. "run", "hot", "hole"un ilk anlamı ikisinden.
- WordNet/KeNet Türkçesi (`syn`): 14.171 synset, kaynak ham girdi olmadan **bilinmiyor**.
- Kalıp Türkçesi (`expr.tr`): 7.312 **bilinmiyor**, 2.486 Storilex katkısı, 902 kategori listesi, 234 expr_fixes.
- AI taslakları: `own_word` 80.997, `own_expr` 13.110 (incelenmemiş).
- **#114'ün yayın/provenance kapısı çözülmeden yayın önerilmez.** Bu PR veriye dokunmuyor.

### 6.3 Önceden var olan risk: kelime kartı deyim içinde de puanlanıyor

`SenseEngine.fit(kelime, cümle, ...)` kelimeyi tek başına çözüyor, cümledeki kalıba bakmıyor. Ölçüm (kelimenin ilk ana
anlamı cevap olarak): deyimsel cümlelerde onay dev 772/1.875 (%41), tune 481/1.084 (%44), final 45/128 (%35). Örnek:
"The prisoner was on the run …" cümlesinde "run = koşmak" kartı onaylanıyor. Bu görevde değiştirilmedi (R1 de
değiştirmiyor; 0/0). Kart değerlendirmesine "kelime bir deyimin içindeyse puanlama" kuralı ayrı bir görev olmalı.

## 7. Testler

- Yeni `test/context_recovery_5i_test.dart` (15 test, cümleler Claude'un): varsayılanlar (R1 kapalı = 5H motoru
  birebir); R1 açıkken "on the run" deyim cümlesi (checked anlam, olası, kart yok, kelime paneli aynı tahmin); kuralın
  genelliği (her değişen cevapta lider Türkçesiz düz okuma, yeni cevap checked ve ≤ 0,06 içinde); AI taslağı kurtarılmıyor
  ("in the hole"); hot air düz ve deyimsel; olumsuzluk, tırnaklı bahsetme, kısa cümle; biçim işareti; cümle sınırı;
  phrasal verb'ler; çok anlamlı kelimeler (bank, know); önbellek anahtarı ve sorgu sırası; headFromPattern araştırma bayrağı.
- `test/context_sense_ui_test.dart`: 5H "ayırt edemiyor" testi "in the hole" cümlesine taşındı (on the run R1 kapalıyken
  de hâlâ aynı, motor testinde sabit); +2 test: hot air notu TR ve EN, deyimsel cümlede not yok, deyim anlamı hâlâ
  erişilebilir; 320 px koyu temada taşma yok.
- `test/literal_guard_5h_test.dart`: motor R1 açıkça kapalı kurulur (5H kurallarını sabitlemek için).
- Tam `flutter test`, `flutter analyze`, Python testleri, CI: sonuçlar PR açıklamasında. Bilinen ortam sınırı: PDFium
  kütüphanesi bu makinede yoksa 3 PDF testi düşer (önceki görevlerdeki gibi). **MAGPIE ölçümleri CI'da koşmaz** (veri
  depoda yok); yukarıdaki sayılar bu bulut makinesinde yerel çalıştırmadır.
- Gerçek cihazda test yapılmadı; kod saf Dart, platforma özgü değişiklik yok.

## 8. Veri, bağımlılık, çevrimdışı

- `assets/dict.db` SHA-256 `ab4a7a53b9fc5e1edbd682da5cb7193c0c109f93236655385bf6231d90221a9c`, `assets/tr_en.db`
  `49a661b9c8951259ab13fd6a95aa77b68e16f1c4716669dacfb6c12521cfa818`: başta ve sonda aynı.
- Yeni paket, model, ağ çağrısı, veri dosyası yok; paket boyutu değişmez. Çevrimdışı çalışma etkilenmez.
- `SenseEngine.version` değişmedi (varsayılan davranış 5H ile aynı); R1 veya headFromPattern açılırsa önbellek anahtarı
  ayrışır (`recover`, `head`).

## 9. Varsayılan ayarlar ve geri dönüş

| bayrak | varsayılan | anlamı |
|---|---|---|
| `SenseEngine.defaultLiteralCues` (5G) | açık | değişmedi |
| `SenseEngine.defaultLiteralGuard` (5H) | açık | değişmedi |
| `SenseEngine.defaultIdiomRecovery` (5I, R1) | **kapalı** | açmak tek satır; önce gerçek kitaplardan deyim/düz oranı bilinen bir küme gerekli |
| `SenseEngine.defaultHeadFromPattern` (5I, R2) | **kapalı** | araştırma |
| `_ExprCardState.showMaybeNotHere` (5I, UI) | **açık** | kapatmak tek satır |

## 10. Kalan riskler ve sonraki adımlar

- "on the run" gibi panellerin asıl çözümü: (a) gerçek kitap cümlelerinden etiketli, deyim/düz oranı doğal bir küme ile
  R1'i yeniden ölçmek; (b) kalıp Türkçelerinin provenance'ını ham girdilerle (`inventory.py --raw`) netleştirmek;
  (c) `review_queue_5i.tsv`'deki AI taslaklarının insan incelemesi (91/152 boş panel bu yüzden).
- Deyim/düz ayrımı hâlâ zayıf: finalde düz cümlelerin %35'inde deyim anlamı ("olası") gösteriliyor.
- Kelime kartı deyim içinde puanlanıyor (§6.3).
- Final etiketleri gürültülü, deyim türleri önceden görülmüş, final küçük (165 deyimsel cümle).

## 11. Değişen dosyalar

- `lib/nlp/context_sense.dart`: `idiomRecovery`, `headFromPattern` (ikisi de kapalı), `resolveTap` kurtarılan kalıbı
  izler, önbellek anahtarı.
- `lib/ui/word_sheet.dart`: `ExprCard` notu. `lib/ui/meaning_parts.dart`: `PanelHeading` kaydırma.
- `test/context_recovery_5i_test.dart` (yeni), `test/context_sense_ui_test.dart`, `test/literal_guard_5h_test.dart`.
- `tools/nlp_research_5i/`: `build_sets_5i.py`, `final5i_LOCKED.sha256`, `dump_5i_test.dart`, `metrics_5i.py`,
  `trace_test.dart`, `coverage_5i.py` (veri yok).
- `docs/nlp_engine_research/CONTEXT_SENSE_RECOVERY_5I.md`, `docs/nlp_engine_research/review_queue_5i.tsv`.
