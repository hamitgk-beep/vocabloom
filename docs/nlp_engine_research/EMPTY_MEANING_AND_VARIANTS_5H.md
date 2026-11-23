# Boş Türkçe anlamlar, düz okumanın dürüst gösterimi ve deyim varyantları (Görev 5H)

Tarih: 23 Kasım 2026. Temel: PR #117 (Görev 5G) head `003058e`; bu dal onun üstünde (stacked; #117 de #116'nın
üstünde). Flutter 3.50.0. Önceki değişiklikler kopyalanmadı.

## 1. Kısa sonuç

- **Boş paneller güvenli biçimde azaltılamadı.** Boş kalan panellerin çoğu, motorun gerçek deyimi yanlışlıkla
  "düz kullanım" sayıp o düz okumanın Türkçesini bulamadığı durumlar (geliştirme kümesinde 72 boş panelin 63'ü
  deyimsel cümle). Bu boşlukları kelimenin kendi anlamıyla doldurmak denendi: dolan panellerin çoğu deyim cümlesine
  kelime anlamı koyuyordu (geliştirmede 9 panelin 8'i). Doğrulanmış kaynaklı ve gerçekten doğru Türkçe gösterilen
  panel sayısı finalde **değişmedi** (yanlış bilgi eklememek için bilerek).
- **Değişen davranış (`SenseEngine.literalGuard`, varsayılan açık):**
  1. Sözlükteki bir kalıp cümlede bulunup **sözcük sözcük** okunduğunda bu okuma artık **hiç "kesin" değil**
     (phrasal verb'ler hariç, onlar eskisi gibi). 5F'nin deyim için koyduğu kuralın düz okumadaki karşılığı.
  2. Sözcük sözcük okumanın Türkçesi yoksa ve cümlenin biçiminde düz kullanım işareti (5G işaretleri) yoksa panel
     artık "kelimelerin düz anlamıyla kullanılmış" **demiyor**; "Türkçe karşılık doğrulanamadı: kalıp olarak mı,
     düz anlamıyla mı kullanıldığını sözlük ayırt edemiyor" diyor (`SenseGap.idiomOrWords`). Bu durumda
     İngilizce tanım Türkçe anlam yerine konmuyor.
  3. Kelime paneli (o kalıbın bir kelimesine dokunulunca) aynı dürüst cevabı veriyor (`SenseEngine.resolveTap`).
  4. Boş panelin nedeni artık kodda görünür ve test edilebilir: `ContextSense.gap` (`noTurkish`, `idiomOrWords`,
     `noMeaning`, `grammarWord`, `notInSentence`, `name`, `undecided`, `error`).
- **Kilitli bağımsız finalde (629 cümle, tek çalıştırma):** deyim cümlesinde düz okumanın **kesin** gösterilmesi
  **21/294 → 0/294** (21 düzeldi, 0 bozuldu; p ≈ 1·10⁻⁶). Deyim gösterimi, recall, precision, kart onayı
  **değişmedi** (hepsi birebir aynı). Bedel: doğru düz okumaların 15'i "kesin" yerine "olası" gösteriliyor ve
  Türkçesi olmayan 7 doğru "düz kullanım" iddiası "ayırt edemiyor"a döndü (§6).
- **Deyim varyantları** (iyelik, araya sözcük): her sınıf ayrı ölçüldü; hiçbiri "yeni yanlış deyim gösterimi = 0"
  koşulunu sağlamadı. `variants` **kapalı** kalıyor. Finalde de bir kez ölçüldü: recall +11, düz cümlede yanlış
  deyim +9 (§7).

## 2. Akış ve karar türleri

| karar | nerede | panelde |
|---|---|---|
| deyim | `_resolvePhrase` → `_decide`, `cat` dolu, `literalPhrase` boş | deyimin anlamı ("olası"; sıradan kelimeli deyim asla kesin değil, 5F) |
| düz kullanım | `literalPhrase` dolu | "büyük olasılıkla kelimelerin düz anlamıyla kullanılmış" + kelimenin anlamı ("olası"; 5H) |
| yalnız kalıptan söz edilmesi | 5G `mention` işareti (tırnak, "the idiom …") | hiç kesin değil (5G) |
| belirsiz (5H) | `gap == idiomOrWords` | "Türkçe karşılık doğrulanamadı … ayırt edemiyor"; anlam yok, kart puanlanmaz |

Bir deyimi geri plana almak düz anlam uydurmak için gerekçe sayılmadı: düz okumanın Türkçesi yoksa ve biçim
işareti yoksa, ne deyim ne düz anlam iddia ediliyor.

## 3. Boş panellerin nedenleri (başlangıç = 5G motoru)

Sayım: kalıp bulunan satırlarda panelin hiç Türkçe göstermediği durumlar (`dump_5h_test.dart`, ayrıştırma
`gap` ve aday listesinden; geliştirme ve ayar kümeleri, final yalnız betimleme için).

| neden | dev (2.134 bulunan) | tune (1.211) | final (406) |
|---|---|---|---|
| **toplam boş** | **72** (63 deyimsel / 9 düz) | **52** (41 / 11) | **22** (6 / 16) |
| düz okuma seçildi, kelimenin kendi panelinde **doğrulanmış** Türkçe var (yol/aday seçimi) | 18 (12 / 6) | 9 (8 / 1) | 5 (1 / 4) |
| düz okuma seçildi, kelimenin başka bir anlamında Türkçe var ama seçilmedi | 8 (7 / 1) | 9 (3 / 6) | 5 (2 / 3) |
| düz okuma seçildi, kelimede yalnız **doğrulanmamış AI taslağı** Türkçe var | 44 (42 / 2) | 29 (25 / 4) | 12 (3 / 9) |
| İngilizce tanım var, doğrulanmış Türkçe hiç yok | 2 (2 / 0) | 0 | 0 |
| deyim seçildi, deyimin yalnız İngilizce başlığı var | 0 | 5 (5 / 0) | 0 |
| hiç anlam yok | 0 | 0 | 0 |
| eşleştirme / cümle sınırı hatası | MAGPIE cümleleri tek cümle; otomatik ayrılamadı, testlerde ayrıca | | |

- Boş panellerin hepsi `noTurkish` (biri `undecided`): bir anlam seçilmiş, Türkçesi yok.
- Ayrıca bir **lemma hatası** bulundu: sözcük sözcük okuma, baş kelimenin taban biçimini kalıbın *ilk* kelimesinden
  alıyor; "in the hole"da "hole" yerine "in" (inç, Indiana) anlamları yarışıyor. Boş düz panellerin dev'de 15'i,
  tune'da 8'i bu yüzden. Düzeltmesi denendi (§5, aday 2): boş panel sayısı ve hata ölçüleri anlamlı değişmedi,
  yanlış "kesin" düz okuma +12/−4 arttı; **eklenmedi**, raporlandı.
- Örnek (Claude'un yazdığı cümleler, testte): "The prisoner was on the run for three weeks." 5G'de "düz anlamıyla
  kullanılmış" + boş; "Pour the water back in the hole …" aynı.

## 4. Veri, ayrım ve lisans

### 4.1 Kümeler (`tools/nlp_research_5h/build_sets_5h.py`)

| küme | cümle | deyim | kural | kullanım |
|---|---|---|---|---|
| `dev5h_magpie.tsv` | 2.202 deyimsel / 464 düz | 402 | 5F/5G final dışı deyimler (deyime göre hash, 2/3), uzlaşma ≥ 0,70, deyim+etiket başına ≤ 8 | teşhis, aday tasarımı |
| `tune5h_magpie.tsv` | 1.203 / 216 | 218 | aynı havuz, diğer 1/3 deyim | aday seçimi |
| `final5h_magpie.tsv` | **294 / 335** | **154** | 5F/5G final deyimleri; uzlaşma 0,70–0,99; **5F ve 5G'nin hiçbir kümesinde olmayan** cümleler; ≤ 4 | **tek ölçüm** |

- **Cümle bağımsızlığı:** final cümlelerinin hiçbiri 5F dev/final ve 5G dev/tune/final kümelerinde yok (kontrol: 0);
  uzlaşma 1,0 cümleleri (5A/5B/5E'nin çektiği havuz) finale alınmadı.
- **Deyim bağımsızlığı:** final deyimleri geliştirme/ayar kümelerinde yok (0 ortak). Bu deyimler 5F'de ve 5G'de
  yalnız ölçüldü, onlarla hiçbir şey ayarlanmadı. **Sınır:** sözlükte olup hiçbir önceki görevde kullanılmamış
  MAGPIE deyimi kalmadı; deyim **türleri** daha önce görülmüş.
- **Kilit:** final hash'i (`d479d256…`) hiçbir sistem çalışmadan önce commit edildi (`d35b27c`,
  `final5h_LOCKED.sha256`); aday kod finalden önce donduruldu (`00fb015`). Baseline, aday ve varyant ölçümü aynı
  satırlarda **birer kez** çalıştı; sonra kural değişmedi.
- Hash'ler: MAGPIE_unfiltered.jsonl `541ee535…`, dict.db `ab4a7a53…`, 5F final `6874e650…` ve 5G final
  `ce55c3bb…` (ikisi de yeniden üretilip kilitle doğrulandı), dev5h `5e81b1be…`, tune5h `197f7faf…`,
  final5h `d479d256…`.
- **Etiketler:** MAGPIE kitle etiketleri (insan, çoğunluk oyu, uzlaşma 0,70–0,99: gürültülü). Testlerdeki
  cümleleri **Claude yazdı (AI)**; insan etiketli altın veri değildir.

### 4.2 Lisans ve kaynak

- MAGPIE: etiketler CC BY 4.0; cümleler çoğunlukla BNC ve **yeniden dağıtılamaz**. Depoya hiçbir MAGPIE/BNC
  cümlesi konmadı; kümeler betikle yerelde üretilir, raporda yalnız deyim adı ve MAGPIE id var.
- Daha önce hiç görülmemiş insan etiketli veri için EPIE (Saxena & Paul) ve PIE-English (Adewumi vd.) depolarına
  bakıldı: depolarda lisans dosyası yok, cümle kaynakları BNC/web. Lisansı doğrulanamadığı için **kullanılmadı**.
- Üretime giren yalnız kendi kodumuz (GPL-3.0). Yeni veri, model, bağımlılık, ağ çağrısı yok. Hiçbir İngilizce tanım
  Türkçeye çevrilmedi; damdafayton, FreeDict veya AI taslaklarından anlam türetilmedi; #114'e dokunulmadı.

## 5. Denenen adaylar (yalnız dev/tune)

| # | aday | dev sonucu | tune sonucu | karar |
|---|---|---|---|---|
| 1 | düz okuma boşsa baş kelimenin tek başına panelindeki **doğrulanmış** anlamı ("olası") | boş −9; ama 8'i deyim cümlesi: deyim cümlesine kelime anlamı +8 (p = 0,008) | boş −5, benzer | **ret** (yanlış anlam ekliyor) |
| 2 | lemma düzeltmesi (baş kelimenin taban biçimi kalıptaki kendi kelimesinden) | boş ±0 (+12/−12), recall −3, yanlış kesin düz +12/−4 | – | **ret**, rapor |
| 3 | 1+2 birlikte | boş −9, deyim cümlesine kelime anlamı +16/−4 (p = 0,01) | – | **ret** |
| 4 | **düz okuma asla kesin + Türkçesiz ve işaretsizse "ayırt edemiyor"** | yanlış kesin düz 115 → 0; yanlış "düz" iddiası 240 → 179; diğer ölçüler aynı | 57 → 0; 133 → 98 | **seçildi** |
| 4a | 4 + kelime panelinde, belirsiz kalıbın kelimesine kelimenin doğrulanmış anlamı | kelime paneli boş −17 (hepsi doğrulanmış kaynak) | −7 | **ret**: elle okunan 17'nin yaklaşık yarısı bağlama uymuyor ("bearing in mind" → "vermek (meyve)", "make short work" → "üretmek"; Claude'un okuması, insan değil) |
| 4b | 4 + biçim işareti olan Türkçesiz düz okumada kelimenin doğrulanmış anlamı | dev +1 doğru (düz cümle) | 0 | açık (zararsız; finalde 0 etki) |

## 6. Kilitli final sonuçları (tek çalıştırma)

Komutlar (depo kökünden; `S5F`, `S5G` 5F/5G betikleriyle yerelde üretilir):

```
python3 -I tools/nlp_research_5h/build_sets_5h.py assets/dict.db MAGPIE_unfiltered.jsonl S5F S5G S5H
NLP_5H_MODE=base|guard NLP_5H_SETS=final=S5H/final5h_magpie.tsv NLP_5H_OUT=OUT/<mode> \
  flutter test tools/nlp_research_5h/dump_5h_test.dart
python3 -I tools/nlp_research_5h/metrics_5h.py OUT/base/final.jsonl OUT/guard/final.jsonl
```

629 cümle (294 deyimsel, 335 düz, 154 deyim); kalıp 406 satırda bulundu. Köşeli parantez: Wilson %95 GA;
eşleştirilmiş fark: düzelen/bozulan, McNemar kesin testi.

| ölçü | 5G (baseline) | 5H | eşleştirilmiş |
|---|---|---|---|
| (i) düz cümlede deyim gösterildi | 108/335 = %32,2 [27,5–37,4] | 108/335 = %32,2 | 0 / 0 |
| (ii) precision / recall / F1 | %64,7 / %67,3 / 66,0 | aynı | 0 / 0 |
| (iii) kalıp eşleşme recall'u | 238/294 = %81,0 | aynı | 0 / 0 |
| (iv) yanlış kesin deyim (düz cümle) | 0/335 [0–1,1] | 0/335 | 0 / 0 |
| (iv) **yanlış kesin düz okuma (deyim cümlesi)** | **21/294 = %7,1 [4,7–10,7]** | **0/294 [0–1,3]** | **21 düzeldi / 0 bozuldu, p ≈ 1·10⁻⁶** |
| (v) yanlış otomatik kart onayı | 0/204 [0–1,8] | 0/204 | 0 / 0 |
| (vi) Türkçesi boş panel (bulunan satır) | 22/406 = %5,4 [3,6–8,1] | 22/406 | 0 / 0 |
| (vi) bunlardan "ayırt edemiyor" olarak dürüst açıklanan | 0 | 12 | |
| (vii) doğru + kaynaklı: deyim cümlesinde deyimin doğrulanmış anlamı | 113/294 = %38,4 | 113/294 | 0 / 0 |
| (vii) doğru + kaynaklı: düz cümlede doğrulanmış kaynaklı düz okuma | 36/335 = %10,7 | 36/335 | 0 / 0 |
| deyim cümlesine "düz anlamıyla kullanılmış" denmesi | 40/294 = %13,6 | 35/294 = %11,9 | 5 düzeldi / 0, p = 0,06 |
| kelime paneli: deyim cümlesinde kesin kelime anlamı | 58/238 = %24,4 | 37/238 = %15,5 | 21 / 0, p ≈ 1·10⁻⁶ |
| kelime paneli: boş / doğrulanmış / AI taslağı | 80 / 257 / 69 (406) | aynı | 0 / 0 |
| (viii) gecikme (bu bulut makinesi, masaüstü Dart VM, kalıp başına, tek ölçüm) | 4,01 ms | 3,91 ms | gürültü içinde |

**Kayıplar (dürüstçe):**
- Doğru düz okumaların **15'i** (düz cümlelerin %4,5'i) artık "kesin" değil "olası". Bunların sözcüğe dokunulunca
  kartla kaydedilen otomatik anlamı da artık yok (öğrenen seçer). 5F'deki deyim kartı ödünleşiminin aynısı.
- "Ayırt edemiyor"a dönen 12 satırın **7'si gerçekten düz** cümle: orada önceki "düz anlamıyla kullanılmış" doğruydu
  (ama Türkçesi yine yoktu). Finalde bu durumdaki düz/deyim oranı geliştirmedekinden çok farklı (dev 5 düz / 61 deyim,
  final 7 / 5). Yani "yanlış düz iddiası" azalması finalde küçük ve anlamlılık sınırında (p = 0,06).
- Bu değişiklik boş panel sayısını azaltmıyor; yalnız boş panelin ne dediğini düzeltiyor.

(vii)'nin "doğru" kısmı MAGPIE etiketinin yönüne (deyim/düz) dayanır; kelimenin doğru *anlamının* seçilip
seçilmediğini MAGPIE söylemez. 5H hiçbir yeni anlam göstermediği için bu sayı değişmedi; elle okuma yalnız aday 4a'da
yapıldı (Claude, insan değil).

## 7. Deyim varyantları (`PhraseMatcher.match(variants: true)`, kapalı)

Yalnız varyantla bulunan satırlar, sınıf sınıf (5H motoru; dev/tune). "gösterildi" = deyim anlamı panelde.

| sınıf | dev: deyimsel bulundu / gösterildi | dev: **düz** bulundu / **gösterildi** | tune: deyimsel | tune: **düz** |
|---|---|---|---|---|
| iyelik zamiri ("his" ← someone's) | 84 / 71 | 25 / **22** | 23 / 22 | 15 / **11** |
| özel ad iyeliği ("Oliver's") | 14 / 12 | 2 / **2** | 5 / 4 | 0 |
| isim iyeliği ("the company's") | 5 / 5 | 0 | 0 | 0 |
| araya sıfat/diğer | 17 / 14 | 12 / **8** | 8 / 6 | 15 / **7** |
| araya -ing / -ed / -ly | 10 / 8 | 4 / **1** | 2 / 2 | 6 / **2** |

- Hiçbir varyant eşleşmesi "kesin" olmadı ve hiçbiri kart onaylamadı (kart yolu `SenseQuery.find` sıradan eşleştiriciyi
  kullanır; testli).
- Yeni yanlış deyim gösterimi 0 olan tek sınıf isim iyeliği: dev'de 5 satır, tune'da hiç yok, finalde hiç yok.
  Etkisi ölçülemiyor → açılmadı.
- İyelik zamirinde deyim–düz puan farkı ≥ 0,26 eşiği dev'de 7 deyim / 0 düz, tune'da 4 / 0 veriyor; ama final
  kümesinde iyelik varyantlı yalnız **1** satır var (MAGPIE'de bu deyimlerin uzlaşma < 1,0 cümlesi az). Ölçülemediği
  için eklenmedi; daha büyük bir iyelik test kümesiyle sonraki adım olabilir.
- Finalde bir kez (bilgi için, karar dev/tune'da verilmişti): recall 198 → 209 (+11, p = 0,001), düz cümlede deyim
  108 → 117 (**+9**, p = 0,004), kesin/kart 0 → 0. Koşul sağlanmıyor: **kapalı**.

## 8. Testler ve koruma

- Yeni: `test/literal_guard_5h_test.dart` (17 test; cümleler Claude'un, AI): varsayılan bayrak; düz okuma asla kesin
  (bayrak kapalıyken kesin = ön koşul); dört "ayırt edemiyor" örneği (anlam yok, İngilizce tanım yok, kart yok);
  kelime paneli aynı cevap; belirsizlik olmayan yerde kelime paneli değişmiyor; phrasal verb'ler (bölünmüş dahil)
  değişmiyor; kendi biçimindeki deyim değişmiyor; önbellek anahtarı; sorgu sırası; `gap`; iki apostrof türü;
  varyant eşleşmesi cümle sınırını geçmiyor; varyant eşleşmesi kart onaylamıyor; sıradan eşleşmeler aynı.
- `test/context_sense_ui_test.dart` +1: kalıp ve kelime panelinde "Türkçe karşılık doğrulanamadı" notu, anlam kutusu,
  İngilizce tanım satırı, "düz anlamıyla kullanılmış" ve "Anlam yanlış" düğmesi yok. Ekran görüntüleri:
  `tr_on_the_run_cannot_tell`, `en_on_the_run_cannot_tell`, `tr_hot_air_literal_guess` (koyu tema).
- Tam `flutter test`, `flutter analyze`, Python testleri: sonuçlar PR açıklamasında.
- `assets/dict.db`, `assets/tr_en.db` SHA-256 başta ve sonda aynı (`ab4a7a53…`, `49a661b9…`). Kullanıcı kitapları,
  kartları, öğrenme kayıtları, yedekleri, sense ID'leri ve şemalar değişmedi. `SenseEngine.version` 5 → 6 yalnız
  geri bildirim kayıtlarındaki motor sürümü alanını ve önbellek anahtarını etkiler.
- Arayüz: yalnız `ContextSenseCard` metinleri (TR/EN, `L(...)`); stil ve yerleşim aynı.

## 9. Geri dönüş

`SenseEngine.defaultLiteralGuard = false` (tek satır) → motor ve paneller 5G ile aynı (testli: bayrak kapalı
karşılaştırmaları). Birleştirme kararı kullanıcınındır.

## 10. Riskler ve kalan işler

- Boş Türkçe panellerin asıl çözümü veri: düz okumada kelimelerin çoğunda yalnız AI taslağı Türkçe var (dev'de 44/72).
  Bu taslakların insan incelemesinden geçmesi boş panelleri kod değiştirmeden azaltır.
- Lemma hatası ("in the hole" → "in") gerçek ama düzeltmesi ölçülebilir fayda getirmedi; ayrı bir görev olabilir.
- Deyim/düz ayrımı hâlâ zayıf (finalde düz cümlelerin %32'sinde deyim gösteriliyor; 5G'nin konusu).
- Final etiketleri gürültülü; final deyim türleri daha önce görülmüş; cümle sınırı ve özel isim vakaları yalnız
  Claude'un test cümleleriyle sınandı.
- Gerçek mobil cihazda ölçüm yapılmadı; kod saf Dart, platforma özgü bir şey yok.

## 11. Dosyalar

- `lib/nlp/context_sense.dart`: `literalGuard`, `SenseGap` / `ContextSense.gap`, `resolveTap`, sürüm 6.
- `lib/ui/context_sense_card.dart`: kelime dokunuşu `resolveTap`'e, "doğrulanamadı" ve "büyük olasılıkla" metinleri.
- `test/literal_guard_5h_test.dart` (yeni), `test/context_sense_ui_test.dart`.
- `tools/nlp_research_5h/`: `build_sets_5h.py`, `dump_5h_test.dart`, `metrics_5h.py`, `final5h_LOCKED.sha256` (veri yok).
