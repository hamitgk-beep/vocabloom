# Değerlendirme raporu: spaCy ve Zemberek adaptörleri

Tarih: 2026-11-21. Bütün ölçümler geliştirme ortamında, gerçek `assets/dict.db` ve `assets/tr_en.db` salt okunur
açılarak yapıldı. İki dosyanın SHA-256 değeri ölçümlerden önce ve sonra aynı kaldı.

**Önemli not:** Etiketleri ve elle yapılan sınıflandırmaları Claude yaptı, bir insan değil. Altın küme
(`en_gold.jsonl`) geliştirme sırasında kural ayarlamak için de kullanıldı. Bu yüzden oradaki oranlar iyimser
olabilir. Kitap düzeyindeki elle sınıflandırma örnekleri ise ayarlamadan sonra rastgele çekildi.

## Yeniden üretmek için

```bash
bash tools/lexicon/setup_spacy.sh          # build/lexicon/venv (spaCy 3.8.18 + en_core_web_sm 3.8.0, MIT)
bash tools/lexicon/setup_zemberek.sh       # build/lexicon/zemberek (Zemberek 0.18.0, Apache-2.0; Java 21 gerekir)
build/lexicon/venv/bin/python tools/lexicon/eval/evaluate.py
bash tools/lexicon/setup_spacy.sh --with-wordfreq && bash tools/lexicon/setup_embeddings.sh
build/lexicon/venv/bin/python tools/lexicon/eval/evaluate.py --lang tr
build/lexicon/venv/bin/python tools/lexicon/eval/evaluate_senses.py --embeddings
build/lexicon/venv/bin/python tools/lexicon/eval/corpus.py --engine spacy --wordfreq library/books/pg-{55,120,74,1342,16}.md.gz
build/lexicon/venv/bin/python tools/lexicon/eval/corpus.py --engine spacy library/books/pg-{55,120,74,1342,16}.md.gz
python3 tools/lexicon/eval/corpus.py --engine builtin library/books/pg-{55,120,74,1342,16}.md.gz
python3 tools/lexicon/eval/corpus.py --lang tr --engine zemberek library/books/trb-*.md.gz
python3 tools/lexicon/run.py --db build/lexicon/eval/en-spacy/candidates.db gaps --out build/lexicon/eval/en-spacy/gaps.md
```

## 1. İngilizce, etiketli 30 cümle (`en_gold.jsonl`)

Cümleler, kütüphanedeki kamu malı Gutenberg kitaplarından (pg-55, 120, 1661, 16, 113, 215, 74, 1342, 11) aynen
alındı. 59 çekimli kelime, 36 özel ad, 29 phrasal verb etiketlendi.

| Ölçü | Yerleşik (`builtin-en@2`) | spaCy (`3.8.18/en_core_web_sm-3.8.0`) |
|---|---|---|
| Kök (lemma) doğruluğu | 0.966 | **0.983** |
| Özel ad bulma (recall) | 0.861 | **1.000** |
| Özel ad kesinliği (precision) | 0.838 | 0.837 |
| Phrasal verb kesinliği | 0.808 | **1.000** |
| Phrasal verb bulma | 0.724 | **0.862** |
| Kelime adayına sızan özel ad | 0.059 (2/34: dinah, sid) | **0.000** |

- Özel ad kesinliğindeki hatalar zararsız türden: "Miss", "Countess", "White Rabbit" gibi büyük harfle yazılmış
  unvan ve lakaplar ad sayıldı. Bunlar zaten sözlükte olan kelimeler olduğu için aday kaybına yol açmıyor.
- spaCy'nin kaçırdığı phrasal verb'ler: "get ... out of" (iki kez), "come away", "fall away".
- Yerleşik adaptör bu çalışmada iyileştirildi (kök doğruluğu 0.525'ten 0.966'ya). Düzensiz biçimler artık önce
  aranıyor ("sat" → "sit"), sözlükte kayıtlı olsalar bile düzenli çekimler köke indiriliyor ("thinking" → "think").

## 2. İngilizce, 5 kitap (19.850 cümle)

Kitaplar: The Wonderful Wizard of Oz (pg-55), Treasure Island (pg-120), Tom Sawyer (pg-74), Pride and Prejudice
(pg-1342), Peter Pan (pg-16).

| | Yerleşik | spaCy |
|---|---|---|
| Kelime adayı (benzersiz satır) | 738 | 619 |
| Bunların güveni ≥ 0.3 olanlar | 296 | 249 |
| Phrasal verb adayı | 268 | 268 |
| Eşdizim (verb + nesne) adayı | – | 869 |
| Olası yeni anlam (sözcük türü boşluğu) | – | 8 |
| Atlanan özel ad kullanımı | 16.055 | 15.530 |
| Süre | 50 sn | 89 sn |

Güveni 0.1 ve altında olanlar ayrıca işaretlendi: bilinen kelimelerden kurulmuş tireli birleşikler (spaCy: 330),
düşmüş harfli lehçe yazımları ("kep'", "'nough": 24), yalnız cümle başında görülüp ad olabilecekler (12), ünlemler (4).

**Özel ad sızıntısı (kitap düzeyinde):** spaCy'nin kelime adaylarında, kitapta hiç küçük harfle geçmeyen 11 kelime
var. Hepsi ünlem ya da tireli birleşik ("chow-ow-ow", "well-a-well"), hiçbiri gerçek bir özel ad değil, hepsinin
güveni 0.1 veya altında. Yerleşik adaptörde 35 tane var, 5'i gerçek ad olabilir (Bromley, Turley ...), hepsinin
güveni 0.1 veya altında. Güveni ≥ 0.3 olan adaylarda özel ad yok.

### Elle sınıflandırma (spaCy, rastgele örnek)

**50 kelime adayı (güven ≥ 0.3):**

| Sınıf | Sayı | Örnekler |
|---|---|---|
| Sözlükte gerçekten eksik, geçerli kelime | 20 (%40) | agitatedly, cheeriness, clandestinely, imperturbably, tremblingly, unaffectedly, woodbox, sunshiny |
| Lehçe / göz lehçesi yazımı (sözlükte yok, ama çoğu sözlüğe girmemeli) | 20 (%40) | agin, cretur, dunno, sich, widder, yaller, yourn, obleege |
| Eski çekimli biçim (lemma değil) | 5 (%10) | doth, dropt, endeth, giveth, barking |
| Yanlış kök / bölme hatası | 5 (%10) | anywher, covie, recoate, redescende, tete |
| Özel ad | **0** | – |

Kitapların ikisi (Tom Sawyer, Treasure Island) lehçe konuşmalarla dolu olduğu için lehçe oranı yüksek. "Sözlükte
yok" tespiti %90 doğru (yalnız %10 araç hatası). Hataların ikisi ("recoated", "redescended") bu örnekten sonra
düzeltildi: ön ek + bilinen kelime kuralı eklendi ve test edildi.

**30 phrasal verb adayı:** 26'sı gerçek fiil + edat yapısı (%87): bound away, clamber up, fetch out, prevail on,
steal out, trot along ... Yanlışlar: "be up" (sıfat kullanımı, artık engelleniyor), "board off", "suggest up",
"bent down" (kök "bend" olmalıydı). Doğru olanların çoğu yön bildiren, anlamı tahmin edilebilir yapılar. Sözlüğe
alınacakları bir insanın seçmesi gerekiyor.

**30 eşdizim adayı:** 13'ü kullanışlı (%43): ask a question, entertain hopes, have no idea, shake hands, ship water,
take possession, vent one's feelings ... Geri kalanı rastlantısal fiil + nesne çiftleri (kiss lip, put letter).
Eşdizimler en düşük güvenle (0.2–0.5) kaydediliyor. Daha iyi sonuç için daha büyük bir derlem ve istatistiksel
ölçü (ör. PMI) gerekir.

**Olası yeni anlamlar (8 aday, hepsi incelendi):** Kullanışlı olan yok denecek kadar az. "mischief" (fiil) belki
geçerli, diğerleri etiketleme hatası ya da lehçe ("spile", "git"). İlk sürümde 214 aday vardı ve 20'lik örnekte
yaklaşık 4'ü anlamlıydı. Sonra yalnız isim ↔ fiil boşlukları, en az 3 kullanım ve kullanımların en az %20'si
şartıyla sınırlandı. **Sonuç:** küçük spaCy modeliyle sözcük türü boşluğu, yeni anlam bulmak için zayıf bir sinyal.
Yeni anlamlar şimdilik `add-sense` ile elle eklenmeli. Bu adaylar 0.2 güvenle kaydediliyor.

## 3. Türkçe, etiketli 20 cümle (`tr_gold.jsonl`)

Cümleler, kütüphanedeki Nasreddin Hoca ve Ömer Seyfettin metinlerinden aynen alındı. 86 çekimli kelime ve 19 özel ad
etiketlendi. "Hoca", "Bey", "Paşa" gibi unvanlar puanlanmadı.

| Ölçü | Yerleşik (`builtin-tr@1`) | Zemberek 0.18.0 |
|---|---|---|
| Kök (lemma) doğruluğu | 0.756 | **0.953** |
| Özel ad kesinliği | **1.000** | 0.950 |
| Özel ad bulma | 0.947 | **1.000** |
| Kelime adayına sızan özel ad | 0.000 | 0.000 |

- Konuşma çizgisinden ya da iki noktadan sonra gelen büyük harf ("– Şunun ...", "Kız: ...") artık ad kanıtı
  sayılmıyor. Bu düzeltmeden önce iki adaptör de bu kelimeleri ad sanıyordu.

## 4. Türkçe, 6 kitap (18.410 cümle)

Kitaplar: Nasreddin Hoca Fıkraları 1–3 ve Ömer Seyfettin Hikâyeler 1–3 (katalogda "Public domain", kaynak
tr.wikisource.org).

| | Yerleşik (`tr_en.db/form`) | Zemberek 0.18.0 |
|---|---|---|
| Kelime adayı (satır) | 10.328 | **2.287** |
| Lemması bulunmuş aday | 0 | 986 |
| Güveni ≥ 0.3 | 0 | 898 |
| Süre | 34 sn | 24 sn |

- Yerleşik adaptörün 25'lik örneğinin 22'si bilinen kelimelerin çekimli biçimiydi (kendisinden, köşelerinden,
  anlatmaktadır ...). Yani yerleşik Türkçe adayların büyük çoğunluğu gürültü. Zemberek bunları köke indirip sözlükte
  bulduğu için aday sayısı %78 azaldı.
- **Zemberek, 40 aday (güven ≥ 0.3), elle sınıflandırma:** 26 geçerli eksik kelime (%65: akşamüzeri, bükük,
  duraklamak, küflenmek, lakırdı, nahif, süzgün, şişmanlamak, tekdir, vakar ...), 2 yazım/ağız farkı (kimbilir,
  ülen), 2 çekimli biçim (zannolunmak), 10 yanlış kök (aynıyla, birkaçı, oracıkta, kıvramak, gargar ve "harıl harıl"
  gibi ikilemelerin yarısı). İkileme yarıları bu örnekten sonra düşük güvene alındı.
- Şapkalı yazımlar ("hakikî", "fevkalâde") artık `tr_en.db`'deki şapkasız biçimle eşleştiriliyor. Bu düzeltmeden
  önce yüzlerce bilinen kelime "yeni" görünüyordu.
- Bilinen sınır: cümle başındaki özel adlar ("Ali dün ...") Zemberek'te sıfat ("ali") olarak çözülebiliyor.
  Belge düzeyindeki ad kanıtı, adın başka yerlerdeki büyük harfli kullanımlarından bunu çoğu zaman yakalıyor.

## 5. Bağlama uygun Türkçe anlam (`sense_gold.jsonl`, `evaluate_senses.py`)

5 Gutenberg kitabından 99 cümle, `own_word`'de birden çok anlamı olan 51 kelime. Her cümlede kelimenin uyan anlamı
(bazen iki anlam) etiketlendi. Etiketleri Claude yaptı. Ayar (ağırlıklar, gömme metinleri) aynı kümede seçildi, bu
yüzden oranlar iyimser olabilir. İki yarıya bölünce gömmeli sonuç 0.68 ve 0.59 çıktı.

| Yöntem | Doğruluk |
|---|---|
| Her zaman ilk anlam (taban çizgisi) | 0.384 |
| Doğru kelime türündeki ilk anlam (spaCy) | 0.495 |
| Kelime örtüşmesi, yerleşik adaptör | 0.465 |
| Kelime örtüşmesi + spaCy kelime türü | 0.596 |
| **+ Sentence Transformers gömmeleri** (`--embeddings`) | **0.636** |

- Gömmeler, İngilizce cümleyi anlamın **Türkçe karşılığıyla** ("kıyı, yamaç (nehir için)") ve bağlı WordNet
  tanımıyla karşılaştırıyor. Örnek cümlelerle karşılaştırmak daha kötüydü (0.48): örnek cümleler başka konularla dolu.
- Bağlamla karar verilen öneriler (güven 0.5): kelime örtüşmesinde %23 kapsama, %78 kesinlik. Gömmelerle %60 kapsama,
  %64 kesinlik. Kalanlar sıraya dayanır (güven 0.3).
- 5 kitapta 19.448 örnek adayının 14.499'u öneri aldı (2.552'si bağlamla, gömmesiz çalıştırma).
- **Sonuç:** Öneri, gözden geçirene hangi anlamın uyduğunu göstermek için yararlı. Her üç öneriden biri yanlış, bu
  yüzden hiçbir zaman çeviri alanına yazılmıyor.

## 6. wordfreq sinyali

- 5 İngilizce kitapta (spaCy) `lemma_suspect` 5 kelime adayını işaretledi. 5'i de gerçek lemma hatası: unaccounted →
  unaccount, unfeeling → unfeel, unlooked → unlook, unprovided → unprovide, vittles → vittle. Bunların güveni 0.1'e
  iniyor ve `suggested_headword` yazılı biçimi tutuyor.
- Zipf tek başına geçerli kelimeyi lehçeden ayırmıyor (dunno 3.76, agitatedly 1.25, woodbox 0). Güveni ≥ 0.3 olan
  218 İngilizce adayın 122'si wordfreq'te hiç yok. Bu yüzden Zipf yalnız sıralama ve inceleme bilgisi.
- Türkçede (Zemberek) güveni ≥ 0.3 olan 999 adayın 856'sının yazılı biçimi wordfreq'te yok. Liste küçük ve çekimli
  biçimlerden oluştuğu için lemma kontrolü Türkçede kapalı.

## Özet

| Hedef | Sonuç |
|---|---|
| İngilizce kök bulma | spaCy 0.983, yerleşik 0.966 (etiketli 59 kelime) |
| Phrasal verb adayları | spaCy kesinlik 1.00 / bulma 0.86 (etiketli küme); kitaplarda %87 gerçek yapı |
| Deyim adayları | Sözlükte kayıtlı deyim ve phrasal verb'ler çekimli hâlleriyle de bulunup örnek cümle adayı oluyor ("broke the ice" → "break the ice"). Yeni deyim çıkarımı yok, elle `add-sense --kind idiom` |
| Özel adları aday yapmama | spaCy: etiketli kümede sızıntı 0; kitaplarda güven ≥ 0.3 olan adaylarda 0 |
| Eksik kelime ve anlam tespiti | Eksik kelime: spaCy örneğinde %40 geçerli, %40 lehçe, %90 "gerçekten sözlükte yok". Eksik anlam: zayıf |
| Türkçe kök bulma | Zemberek 0.953, yerleşik 0.756 (etiketli 86 kelime); özel ad sızıntısı 0 |
| Bağlama uygun Türkçe anlam | 0.636 (gömmelerle), 0.596 (spaCy), ilk anlam 0.384 (99 etiketli cümle) |
| Lemma hatası yakalama (wordfreq) | 5 işaret, 5'i doğru |
| Ayrı veritabanı | `build/lexicon/...` altında, `assets/` dışına yazılır. Ana sözlükler hiç değişmedi |
