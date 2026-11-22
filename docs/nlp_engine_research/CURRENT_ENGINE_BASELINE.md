# Mevcut motorun referans ölçümü (Görev 5E, Aşama 1)

Tarih: 22 Kasım 2026. Kod: `main` @ `6817c28` (Görev 5B birleştirmesi). `SenseEngine.version = 3`.
Sözlükler salt okunur açıldı, hiçbir veri değiştirilmedi.

## 0. Dürüstlük notları

- Buradaki "altın" etiketler yayımlanmış **insan** etiketleridir (SemCor, Senseval/SemEval, UD, MAGPIE). Claude etiket
  koymadı. Claude'un elle yaptığı tek değerlendirme, `BENCHMARK_RESULTS.md` §4'teki "eş anlamlı ama KeNet'te yazmayan
  Türkçe" incelemesidir ve orada ayrıca işaretlidir.
- Bu dosyadaki sayılar **geliştirme kümelerindendir** (aşağıda). Görev 5B'nin final kümesi (`final_*`) bir kez
  kullanılmıştı; 5E'de "görülmüş" sayıldı ve geliştirme kümesi oldu. 5E'nin kendi final kümesi ayrıdır
  (`BENCHMARK_RESULTS.md`).
- 5B'nin final sonuçları bu ortamda **birebir yeniden üretildi** (ör. SemCor "kesin" Türkçe yanlışı 6/67 = %9,0;
  yanlış İngilizce anlamın kesin gösterilmesi %17,1; MAGPIE B düz → deyim %65,3). Yani kümeler ve ölçüm kodu
  5B ile aynıdır.
- 300–340 satırlık kümelerde ±5 puanlık oynama olağandır; tablolarda Wilson %95 güven aralığı verildi.

## 1. Motor nasıl çalışıyor (kısa)

| Parça | Nerede | Ne yapıyor |
|---|---|---|
| **SenseEngine** | `lib/nlp/context_sense.dart` | Dokunulan kelime ya da kalıp için aday anlamları toplar, her birine puan verir, en iyisini ve bir güven seviyesi (`sure` / `likely` / `none`) döndürür. Sonuçları cümle + konum anahtarıyla önbellekler. Hata olursa `none` döner, panel normal sözlüğü gösterir. |
| Aday anlamlar | `_wordCandidates`, `_exprCandidates` | WordNet sinsetleri (`wn:`), kendi sözlük anlamları (`od:`, inceleme bekleyen AI taslakları `ow:`/`xd:`), yerleşik kalıp anlamları (`ex:`), ana anlam listesi (`ft:`). |
| Puan | `_score` | 0,40 anlam örtüşmesi (tanım/örnek/eş anlamlıların cümleyle ortak kelimeleri, IDF ağırlıklı; Türkçe örtüşme de) + 0,18 sözcük türü uyumu + 0,18 cümle kalıbı (nesne var mı, özne insan mı) + 0,12 örnek cümle benzerliği + 0,12 sıklık. |
| **Sözcük türü** | `guessPos` (`lib/nlp/text.dart`) + `_guessPos` | El yazımı kurallar ("to"dan sonra fiil, belirteçten sonra isim, sıfat isimden önce …). Her kuralın adı var; EWT'de sık yanılan kurallar "zayıf" sayılır ve güveni düşürür. |
| **İngilizce kök** | `lemmaOf`, `_lemmaCandidates` | Düzensiz fiil tablosu (`exc`) + ek kesme kuralları (-s, -ed, -ing, -er/-est …). Birden çok kök adayı yarışır. |
| **Türkçe kök** | `TrEnDict.lemmas` (`lib/data/tr_en_dict.dart`) | Türkçe ek çözümleme (ünlü uyumu, yumuşama, olumsuz fiil). Tahmin kökler ayrıca işaretlenir. (Bu görevin İngilizce bağlam konusu dışında; 5B'de ölçüldü.) |
| **Bağlamsal anlam seçimi** | `_decide` | En yüksek puanlı aday. "Sure" için: cümlenin kendisi (sıklık değil) farkı yaratmalı veya ana anlam olmalı; yakın rakip başka Türkçe söylüyorsa, POS belirsizse, AI taslağı kontrol edilmiş bir anlamla doğrulanmıyorsa, Türkçenin biçimi sözcük türüne uymuyorsa `likely`. |
| **Deyim tanıma** | `DictDb.matcher` + `_resolvePhrase` | Sözlükteki kalıp (`expr`) cümlede sözcük sözcük (çekimli biçimlerle) aranır. Bulunursa kalıbın anlamları ile **sözcük sözcük okuma** yarışır. Sıradan kelimelerden oluşan deyim **asla `sure` olmaz** (5B). Düz okumaya yakın kalan deyim anlamı `likely` gösterilir. |
| **Phrasal verb** | `_separable`, `isLiteral` | Bölünmüş phrasal verb ("turn the light off") ayrıca yakalanır; "lived in Kansas" gibi düz kullanım `isLiteral` ile ayrılır. |
| **Güven seviyeleri** | `SenseConfidence` | `sure`: panelde kesin; `likely`: "olası"; `none`: bağlamsal anlam yok. |
| **Otomatik kart puanlama** | `SenseEngine.fit` + `lib/data/review_quiz.dart` | Kart yalnız `confirmed` ise puanlanır: bağlamdaki anlam gösteriliyor, AI taslağına dayanmıyor ve cevapla aynı Türkçe (veya aynı türden KeNet eş anlamlısı). Kalıplarda yalnız `sure` sayılır, yani deyim kartları hiç otomatik puanlanmaz. |

## 2. Referans sayılar (geliştirme kümeleri)

Kümeler: SemCor 5A hold-out (340 satır), SemCor 5B final (340), SemEval-2007 (146, Senseval/SemEval çerçevesinin
geliştirme kısmı), MAGPIE geliştirme kümelerinin hepsi (867 cümle), UD English-EWT train örneklemi (her 4. paragraf,
13.928 çok-türlü kelime).

### 2.1 Bağlamsal anlam ve Türkçe

| küme | kapsama | doğru İng. anlam (tümü) | kesin (pay) | kesin doğru | **yanlış anlam kesin** (tümünden) | Türkçe doğru (gösterilenlerde, sıkı) | **kesin Türkçe yanlış** | ilk-anlam doğru | ilk-anlam Türkçe | kart puanlanan, doğru |
|---|---|---|---|---|---|---|---|---|---|---|
| SemCor 5A | %92,9 | %31,2 | 113 (%33) | %58,4 | %13,8 | %78,6 | 6/78 = %7,7 | %70,6 | %78,2 | 68, %83,8 |
| SemCor 5B | %93,8 | %27,6 | 110 (%32) | %45,5 | %17,6 | %79,5 | 6/67 = %9,0 | %74,1 | %78,7 | 68, %86,8 |
| SemEval-07 | %96,6 | %30,1 | 46 (%32) | %54,3 | %14,4 | %65,0 | 4/35 = %11,4 | %56,8 | %72,0 | 39, %84,6 |

Okuma:
- **İngilizce sinset düzeyinde** motor ilk WordNet anlamının çok gerisinde (≈%30'a karşı ≈%57–74). Bunun bir kısmı
  ölçüm kaynaklıdır: motorun seçtiği anlam çoğu zaman kendi sözlük anlamıdır (`od:`/`ow:`), WordNet kimliği yoktur ve
  sinset eşleşmesinde "yanlış" sayılır. Bu yüzden asıl karşılaştırma **Türkçe** üzerindendir: orada motor ilk-anlamla
  aynı düzeydedir (%78–80'e karşı %78–79), SemEval-07'de geridedir (%65'e karşı %72).
- SemCor'da ilk-anlam temel çizgisi iyimserdir: WordNet'in anlam sırası SemCor sayımlarından gelir.

### 2.2 Sözcük türü ve kök (UD English-EWT train örneklemi)

| ölçüm | değer |
|---|---|
| Gösterilen anlamın sözcük türü doğru (iki+ türü olan kelimeler) | 10.112/11.747 = **%86,1** |
| "Kesin" gösterilenlerde sözcük türü yanlış | 267/3.902 = **%6,8** |
| İngilizce kök (kelime tek başına) | 19.861/20.769 = %95,6 |
| Gösterilen anlamın kökü | 19.645/20.539 = %95,6 |

En sık "kesin ama yanlış tür" hataları (EWT, gerçek cümleler): isim yerine fiil 62 (ör. "a fantasy **trading**
game"), sıfat yerine zarf 52 (ör. "**far** below"), fiil yerine isim 51 (ör. "tended to **focus** on", "many Iraqis
**regard** the date"), isim yerine sıfat 22 ("the two **main** competing lists").

### 2.3 Deyim ve düz kullanım (MAGPIE geliştirme kümeleri, 480 deyimsel / 387 düz cümle)

| ölçüm | değer |
|---|---|
| Deyim precision | %62,0 |
| Deyim recall (deyimsel cümlede deyim anlamı gösterildi) | %88,3 |
| F1 | 72,9 |
| **Düz kullanımın deyim sanılması** | 260/387 = **%67,2** [%62–72] |
| Düz kullanım deyim sanıldı ve **kesin** | 0 |

Yani motor deyimi bulmada iyi, ama **düz cümlelerin üçte ikisinde de deyim anlamını gösteriyor** (hepsi "olası").
5B'nin "kesin" yasağı sayesinde bu hata hiçbir karta yazılmıyor; ama okuyucu yanlış "olası" anlam görüyor.

### 2.4 Deyimin biçimi (MAGPIE eğitim havuzu, 3.393 cümle, varyant türüne göre)

| deyimin cümledeki biçimi | deyimsel: bulundu | deyimsel: deyim gösterildi | düz: deyim gösterildi |
|---|---|---|---|
| birebir aynı (identical) | %100 | %88 | %70 |
| çekimli (inflection) | %97 | %83 | %63 |
| çekim + başka değişiklik (combined-inflection) | %48 | %39 | %13 |
| araya kelime girmiş (insertion-other) | **%0** | %0 | %0 |
| araya belirteç girmiş (insertion-determiner) | **%0** | %0 | %0 |
| belirteç düşmüş (deletion-determiner) | %17 | %17 | %5 |
| iyelik (possessive) | %0 | %0 | – |

**Araya kelime giren deyimleri eşleştirici hiç bulamıyor.** Çekim desteklenir; ama çekim başka bir değişiklikle
birleşince bulma oranı yarıya iner.

## 3. Yanlış anlam seçtiği durumlar: örnekler

### 3.1 Gerçek cümlelerden (SemCor geliştirme, motor "kesin" dedi, KeNet başka Türkçe veriyor)

| kelime | cümle (SemCor) | motor (kesin) | KeNet | not |
|---|---|---|---|---|
| color (v) | "But most learn to **color** and paint …" | tahrif etmek | renklendirmek | gerçek hata (mecazi "çarpıtmak" anlamı) |
| elaborate (v) | "… not within the scope of this report **elaborate** …" | mufassal, tafsilatlı | ayrıntılandırmak | fiil yerine sıfat Türkçesi |
| specify (v) | "Rhode Island law **specifies** that …" | tespit etmek | şart koşmak | gerçek hata |
| reduction (n) | "the **reduction** of fear …" | indirgeyici | azaltma | isim yerine sıfat Türkçesi |
| time (v) | "Brannon **timed** it so that …" | saat tutmak | zamanlamak | gerçek hata |
| strap (n) | "banded with **strap** iron" | omuz askısı | kayış | gerçek hata |
| passion (n) | "Music could not be Eugene's **passion**." | ihtiras, tutku | aşk, sevgi | büyük olasılıkla **doğru** çeviri; KeNet'te yazmıyor |
| outcome (n) | "The **outcome** of the experiment …" | etki | sonuç | yakın ama kabul edilemez |

### 3.2 Görevin örnekleri ve sorunlu durumlar (deneme cümleleri)

Aşağıdaki cümleler gösterim için yazıldı; **test verisi değildir**, hiçbir oran bunlarla ölçülmedi
(`tools/nlp_research/probe_engine_test.dart`).

| durum | cümle | motor | doğru mu |
|---|---|---|---|
| deyim | The host told a joke to **break the ice** at the start of the meeting. | olası: ilk adımı atmak, konuşmayı başlatmak | ✓ |
| düz | He used a hammer to **break the ice** on the frozen pond. | olası: buzları eritmek (deyim) | ✗ düz kullanım deyim sanıldı |
| deyim, çekimli | Who **spilled the beans** about the surprise party? | olası: ağzındaki baklayı çıkarmak | ✓ |
| düz, çekimli | She tripped and **spilled the beans** all over the kitchen floor. | kesin: dökmek (sözcük sözcük) | ✓ |
| deyim | Is the finance team **on board** with the new plan? | olası: ekibe veya projeye katılmak | ✓ |
| düz | There were two hundred passengers **on board** the ship. | olası: bir taşıtta olmak | ✓ |
| deyim | Just relax and **go with the flow**. | olası: akışına bırakmak | ✓ |
| düz | The dead leaves **go with the flow** of the river. | olası: akışına bırakmak | ✗ düz kullanım deyim sanıldı |
| araya kelime | A funny story can **break the** awkward **ice** between strangers. | olası: "sona ermek" (break = terminate) | ✗ deyim bulunamadı, yanlış anlam |
| edilgen / yalnız bir kısmı | **The ice was** finally **broken** when the coach made a joke. | anlam yok | ✗ deyim bulunamadı |
| isim / fiil | He looked at his **watch** and left. / We **watch** the news every evening. | saat / izlemek | ✓ ✓ |
| iki isim anlamı | They had a picnic on the **bank** of the river. / The **bank** raised its interest rates. | nehir kıyısı / banka | ✓ ✓ |
| sıfat / zarf | She works **hard** every day. | olası: çalışkan, yorucu (sıfat) | ✗ zarf olmalı (sıkı, çok) |
| sıfat / zarf | He drives too **fast**. | olası: hızlı, kısa ("hurried and brief", sıfat) | ✗ zarf olmalı |
| özel ad | **Apple** released a new phone in September. | **kesin: elma** | ✗ cümle başındaki özel ad, kesin yanlış |
| özel ad | Mr. **Brown** arrived late to the meeting. | olası: kahverengi | ✗ |
| az bağlam | It was **light**. | olası: hafif | belirsiz cümle; "olası" doğru davranış |

## 4. Ek bulgular

1. **Sıralamaya bağlı sonuç (küçük bir hata).** Aynı cümle, motor daha önce başka kelimelere baktıysa farklı
   sonuç verebiliyor: 340 satırın 3'ünde ("tick", "march", "confine") güven veya anlam değişti. Nedeni büyük
   olasılıkla `_Profile._cache`'in yalnız aday kimliğiyle (`wn:…`) anahtarlanması; aynı sinset başka bir kelimeyle
   gelince ilk hesaplanan profil kalıyor. Ayrıca `SenseEngine.cacheKey` sorgunun `lemma` alanını içermiyor. Etki
   küçük ama sonuçları tekrarlanamaz kılıyor; ayrı, küçük bir düzeltme önerilir (bu görevde motora dokunulmadı).
   Bu yüzden ölçüm betiği her dosya için yeni bir motor kurar.
2. **Kart puanlama zaten temkinli:** kartların %83–87'si doğru puanlanıyor; deyim kartları hiç otomatik
   puanlanmıyor.

## 5. Yeniden üretme

```
python3 -I tools/eval/build_sense_eval.py assets/dict.db NLTK MAGPIE_unfiltered.jsonl SETS
python3 -I tools/eval/build_holdout.py    assets/dict.db NLTK MAGPIE_unfiltered.jsonl UD SETS SETS
python3 -I tools/eval/build_final.py      assets/dict.db NLTK MAGPIE_unfiltered.jsonl UD SETS SETS
NLP_SENSE="dev_semcor5a=SETS/holdout_semcor.tsv,..." NLP_MAGPIE=... NLP_EWT=... NLP_OUT=DUMP \
  flutter test tools/nlp_research/dump_engine_test.dart
python3 tools/nlp_research/eval_systems.py DUMP SCORES show dev_semcor5a dev_semcor5b dev_se07
```
