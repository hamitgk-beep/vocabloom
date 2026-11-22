# Kalite ölçümleri (Görev 5A, Aşama 3 ve 4)

Tarih: 22 Kasım 2026. Kod: `main` @ `a181094`. Sözlükler salt okunur açıldı; SHA-256 değerleri ölçümden önce ve
sonra aynı (`dict.db ab4a7a53…`, `tr_en.db 49a661b9…`).

## 0. Dürüstlük notları (önce okuyun)

- **İnsan değerlendirmesi yapılmadı.** Bu çalışmada hiçbir insan etiket vermedi. Aşağıdaki "altın" etiketler
  başkalarının yayımlanmış **insan** etiketleridir (SemCor, UD, MAGPIE), etiketleri Claude koymadı.
- **Claude'un yaptığı sınıflandırmalar** (örneklem dosyalarının okunup "özel ad / yabancı / bozuk" diye
  ayrılması) ayrı işaretlendi ve insan doğrulaması **değildir**; yaklaşık oranlardır.
- **Bağımsızlık:** Uygulamanın kodu ve ağırlıkları bu kümelere bakılarak hiç ayarlanmadı. Kümeler, uygulama çıktısına
  bakılmadan önce sabit tohumla çekildi; önceki üç SemCor çekilişinin (`test/data/sense_eval_semcor*.tsv`) kelimeleri
  ve önceki MAGPIE çekilişlerinin (dev/fresh/fresh2) deyimleri dışarıda bırakıldı. Önceki çekilişler yeniden üretilip
  depodakilerle bayt bayt karşılaştırıldı (aynı). Metin hattı daha önce GUM ile ölçülmüştü; burada **hiç
  kullanılmamış** UD English-EWT kullanıldı.
- **Örneklem ≠ bütün sözlük.** "TAM" yazan ölçümler bütün tabloyu taradı; "ÖRNEKLEM" yazanlar örneklemdir ve
  bütün sözlüğün kesin istatistiği değildir.
- Ölçümler tek koşuda yapıldı; güven aralığı verilmedi. 300–340 satırlık kümelerde ±5 puanlık oynama olağandır.

## 1. Yöntem ve veri

| Küme | Kaynak (lisans) | Boyut | Ne ölçer |
|---|---|---|---|
| SemCor hold-out | SemCor 3.0, Brown derlemi; `brownv` dahil (Princeton lisansı) | 340 kelime-cümle (n 120, v 120, a 60, r 40), tohum 20261622; 132'sinde KeNet Türkçesi var | Bağlamda anlam seçimi; Türkçe karşılık |
| MAGPIE hold-out | MAGPIE (etiket CC BY 4.0; metin BNC, **yalnız yerel**) | 300 cümle (150 deyimsel / 150 düz), uzlaşma 1,0, önceki çekilişlerde olmayan deyimler | Deyim bulma, deyim/düz ayrımı |
| EWT metin | UD English-EWT test (CC BY-SA 4.0) | 2.077 cümle, 20.925 kelime | Cümle sınırı, belirteç, kök, sözcük türü |
| EWT phrasal verb | UD English-EWT dev+test | 4.078 cümle, 161 altın "fiil + parçacık" (`compound:prt`) | Phrasal verb recall / precision |
| EWT özel ad | UD English-EWT dev+test, PROPN | 1.801 özel ad (sözlükte de kelime olan) | Özel adın kelime anlamıyla gösterilmesi |
| UD Türkçe | UD Turkish BOUN, Kenet, Penn test (CC BY-SA 4.0) | 3.546 cümle, 25.393 içerik kelimesi | Türkçe kök ve sözcük türü (`TrEnDict`) |
| Kaynak karşılaştırması | Open English WordNet 2025 (CC BY 4.0), wordfreq 3.1.1, MAGPIE | TAM tarama | Eksik kelime, tür, phrasal verb, deyim, çelişki, yinelenme |

Yeniden üretme (Flutter 3.50.0, Python 3 + `nltk==3.9.1`, `wordfreq==3.1.1`):

```sh
python3 tools/eval/build_sense_eval.py assets/dict.db <nltk_data> <MAGPIE_unfiltered.jsonl> <prev>   # önceki çekilişler
python3 -I docs/lexicon_research/scripts/build_holdout.py assets/dict.db <nltk_data> <MAGPIE> <ud_dir> <prev> <out>
HOLDOUT_DIR=<out> HOLDOUT_OUT=<rows> flutter test docs/lexicon_research/scripts/holdout_eval_test.dart
python3 tools/eval/build_text_eval.py <EWT test'i en_gum-ud-test.conllu adıyla içeren klasör> <dir>
TEXT_EVAL_DIR=<dir> TEXT_EVAL_SET=test flutter test test/text_eval_test.dart                       # EWT metin ölçümü
python3 -I docs/lexicon_research/scripts/compare_sources.py assets/dict.db assets/tr_en.db english-wordnet-2025.xml.gz <MAGPIE> <out>
```
Kaynak indirme: SemCor ve WordNet `nltk_data` (GitHub), UD treebank'leri `UniversalDependencies/*` (GitHub),
MAGPIE `hslh/magpie-corpus` (GitHub), OEWN `globalwordnet/english-wordnet` release `2025-edition`.

## 2. Aşama 4 metrikleri (bağımsız kümeler)

### 2.1 Lemma / kök doğruluğu
| Dil | Küme | Sonuç |
|---|---|---|
| EN | EWT (9.485 isim/fiil/sıfat/zarf) | Kelime tek başına: **%95,6**; cümlede gösterilen anlamın kökü: **%95,0** |
| TR | UD BOUN+Kenet+Penn (25.393) | İlk önerilen kök doğru: **%78,0**; doğru kök listede herhangi bir yerde: %82,5; **hiç kök bulunamadı: %10,6** |

EN kök hatalarının türü (422 hata, otomatik ayrım):

| Tür | Sayı | Örnek | Kullanıcıya zarar |
|---|---:|---|---|
| Ortaç/ulaç fiile indirildi, UD sıfat/isim diyor | 115 | worried→worry, ruling→rule | Çoğu kez düşük (ikisi de gösterilebilir); **willing→will zararlı** |
| Çekimli biçim indirgenmedi | 87 | screenshots, relations, others | Orta (kelime bulunamıyor) |
| Başka yanlış kök | 55 | best→good (UD: well), media→medium | Değişir |
| Yalnız çoğul isim indirildi | 54 | thanks→thank, barracks→barrack | Orta |
| Ortaç olduğu gibi kaldı (UD fiil diyor) | 50 | buried, received, announced | Düşük–orta |
| Altın kök sözlükte yok (yazım hatası, kısaltma) | 42 | usint, idelogical | – |
| **-er/-or ismi köke indirildi** | 19 | **customer→custom, owner→own, buffer→buff, opener→open** | **Yüksek: tamamen yanlış anlam** |

TR: hata dağılımı 1.750 yanlış kök, 1.147 doğru kök ikinci sırada, 2.688 kök yok.

### 2.2 Sözcük türü doğruluğu
- EN (EWT, birden çok türü olan 6.533 kelime): anlam gösterildi %83,7; gösterilenlerin türü doğru **%82,5**.
  **"Kesin" gösterilen 3.028 anlamın %14,8'inin türü yanlış** (ör. "interested", "worried" → fiil; "purchase
  agreements" → fiil; "want to go" → isim). Türe göre doğru/gösterilen: isim 1.764/2.203, fiil 1.648/1.818, sıfat
  921/1.181, **zarf 181/268** (zarfların yalnız %31,7'sine anlam gösteriliyor).
- TR: doğru kökün ilk anlamının türü UD ile aynı **%89,1**. Not: tr_en'de 23.952 anlamın türü boş (FreeDict kaynaklı).

### 2.3 Anlam seçimi doğruluğu (SemCor hold-out, 340)
| Ölçü | Değer |
|---|---|
| Anlam gösterme oranı (kapsama) | **%92,6** (315/340) |
| Gösterilen anlam = insanın seçtiği WordNet anlamı | %33,3 (105/315). Not: gösterilen 104 anlam WordNet dışı (AI taslağı) kaynaktan geldiği için bu ölçüde otomatik yanlış sayılır; aşağıdaki satır adil karşılaştırmadır |
| Yalnız WordNet anlamı gösterilen satırlar, **seçici** vs **"ilk WordNet anlamı" tabanı** | "kesin" 142 satır: **%54,9 vs %73,9**; "olası" 69 satır: %39,1 vs %56,5 |
| İnsan anlamı aday listesinde (üst sınır) | %67,4 |
| Taban: ilk WordNet anlamı (tüm satırlar) | %70,6 |
| Gösterilen anlamın Türkçesi KeNet referansıyla aynı (katı, 132 satır) | **%77,9**; "kesin" olanlarda %88,8; tabanın Türkçesi %78,8 |
| Tekrar kartı kuralı (`fit`) ortak anlamı onayladı | 69 satır, KeNet'e göre doğru %82,6 |

Sonuç: İngilizce anlam **kimliğinde** bağlam seçici, en basit "ilk anlam" tabanının **altında** kalıyor. Kullanıcının
gördüğü **Türkçe** düzeyinde ise taban ile aynı seviyede (%77,9 vs %78,8). Yani bağlam seçicinin bugünkü ağırlıkları,
anlamı değiştirdiği yerlerde ortalamada kazanç sağlamıyor. Önceki raporlarla tutarlı: depodaki ana kümede (260) seçici
175 doğru, 68 yanlış (aynı koşuda tekrar ölçüldü; o küme bağımsız değildir).

### 2.4 Yanlış anlamı kesin doğru gösterme oranı
- SemCor: İngilizce anlam olarak **tüm satırların %30,3'ü** (103/340) "kesin" ama insanın seçtiğinden farklı. Türkçe
  düzeyinde "kesin" gösterilen 98 satırın 11'i (%11,2) KeNet'e göre farklı Türkçe.
- Sözcük türü: "kesin" gösterilenlerin %14,8'i yanlış tür (EWT).
- Deyim: deyim olarak "kesin" gösterilen 20 MAGPIE cümlesinin 7'si aslında düz kullanım.
- Özel ad: EWT'de sözlükte de kelime olan 1.801 özel adın %74,1'ine kelime anlamı gösterildi, **%49,9'u "kesin"**.
  Çoğu zararsız çeviri (Iraq→Irak, January→ocak); ama ör. "Nook" (ürün adı)→"köşe" 16 kez. Zarar oranı elle
  etiketlenmedi.
- Örnek: "Rector's next **stop** was…" (isim) → "durmak, durdurmak" (fiil Türkçesi), **kesin**. Kaynak: AI taslağı,
  ft ile "doğrulanmış" sayıldı (iki kaynağın aynı Türkçeyi vermesi, türleri farklıyken).

### 2.5 Deyim ve phrasal verb tespiti
| Ölçü | Değer |
|---|---|
| MAGPIE: deyim sözlükte bulundu (deyimsel cümlelerde) | %98,7 |
| MAGPIE: "deyim olarak kullanılmış" kararı | **precision %57,3, recall %76,0, F1 65,3** |
| MAGPIE: düz cümlenin deyim sanılması | **%56,7** (85/150) |
| EWT phrasal verb recall | **%80,1** (129/161) |
| EWT phrasal verb precision (alt sınır) | %37,8 (düz kullanım kontrolünden sonra; öncesi %32,9) |

Uyarılar: MAGPIE kümesi bilerek 50/50 dengelendi; gerçek metinde deyimlerin çoğu deyimsel kullanıldığı için gerçek
precision daha yüksek olur. EWT yalnız parçacıkları (`compound:prt`) altın sayar; "look at" türü edatlı fiiller hiç
altın olmadığı için precision gerçekte daha yüksektir (alt sınır).

### 2.6 Türkçe karşılık doğruluğu
- SemCor (132 satır, KeNet referansı, katı eşleşme): %77,9 aynı Türkçe. Eş anlamlı ama farklı yazılmış doğru cevaplar
  yanlış sayılır; gerçek doğruluk daha yüksektir (insan değerlendirmesi yapılmadı).
- `ft` Türkçesi ile KeNet (ilk üç synset) en az bir ortak kelime: **%76,1** (11.059/14.539) — TAM.
- `ft` içinde Türkçe sözlükte (tr_en `form`+`lemma`) bulunmayan belirteç: **%6,7** (11.314/169.383) — TAM.
  80 örnek türün yaklaşık 20'si bozuk/yazım hatalı/çok eski öztürkçe (Claude okuması): "çivermek" (upend),
  "mahsül", "sakçısı" (patrolman), "siniz" (are), "birdeme", "karşıtezgen". Geri kalanı geçerli çekimli/nadir kelime.

### 2.7 Kaynaklar arası tutarlılık (TAM)
- `ft` ilk anlamı ile AI taslağının ilk anlamı: 41.176 kelimede karşılaştırıldı; **%53,4** en az bir ortak kelime,
  19.189 kelimede hiç ortak kelime yok. 44 tanesi okundu (Claude): ≈34 eş anlamlı/farklı söyleyiş, ≈4 farklı ama
  geçerli anlam (stake: kazık / pay), ≈6 bir taraf yanlış veya bozuk (fecula: ft "nişasta" doğru, AI "dışkı" yanlış;
  maraging: ft "maryaşlama"; adagio: ft "adacio"; suslik: ft "geleni").
- `ft` ile KeNet: %76,1 (yukarıda).
- Not: Kelime örtüşmesi anlam uyuşmazlığını ölçmez; yalnız inceleme sırası için sinyaldir.

### 2.8 Kararsız kalma / sonuç göstermeme oranı
- SemCor: anlam yok %7,4 (25/340); bunların 19'unda aday vardı ama puan zayıftı.
- EWT tür: birden çok türlü kelimelerin %16,3'ünde anlam gösterilmedi; zarflarda %68,3.
- UD Türkçe: kök bulunamadı %10,6.
- Değerlendirme: seçici %92,6 kapsama ile çok az çekimser kalıyor; "kesin" etiketi ise yanlışların önemli kısmını
  taşıyor. Daha az ama daha doğru "kesin" önerisi bu yüzden anlamlı (bkz. RECOMMENDED_ARCHITECTURE).

### 2.9 Dilbilgisi analizindeki hata türleri
Bu çalışmada `grammar_marks` için yeni insan etiketli küme bulunamadı (açık lisanslı, Türkçe açıklamalı bir
gramer-yapısı derlemi yok). Ölçülenler: cümle sınırı EWT'de precision %95,0 / recall %70,3 (web metninde noktalama
eksik başlıklar ve e-postalar recall'u düşürüyor); belirteç konumu %98,0; ifadelerin cümle sonunu aşması 854'te 2.
Önerilen: UD EWT/GUM'daki `Tense`, `Voice=Pass`, `Mood` özellikleri ile edilgen ve zaman işaretlerinin otomatik
karşılaştırılması (yol haritası Aşama 2).

### 2.10 Performans ve kaynak tüketimi (Linux x64, test ortamı)
| Ölçü | Değer |
|---|---|
| `DictDb.load()` | 732 ms |
| Süreç belleği (RSS) yüklemeden sonra | 191 MB |
| `SenseEngine.resolve` | medyan 2,1 ms, p95 5,7 ms |
| `TrEnDict.lemmas` + `entry` | ≈ 65 µs / kelime |
| Dosya boyutları | dict.db 70,6 MB, tr_en.db 44,1 MB |
Telefon ölçümü yapılmadı.

## 3. Aşama 3: kaynaklarla karşılaştırma (İngilizce ve Türkçe ayrı)

### 3.1 İngilizce
| Bulgu | Değer | Tür |
|---|---|---|
| OEWN 2025 lemma | 127.311 | TAM |
| OEWN 2025'te olup dict.db WordNet'inde olmayan lemma | 4.337 (4.211'i dict.db'nin hiçbir tablosunda yok) | TAM |
| dict.db WordNet lemmalarından OEWN 2025 çekirdeğinde olmayan | 24.332 (çoğu özel ad; OEWN 2025 özel adları Namenet'e taşıdı — tek tek doğrulanmadı) | TAM |
| wordfreq EN ilk 30.000 (alfabetik 29.152) içinde hiçbir biçimde bulunmayan | **3.706** (bantlar: 0–5k 106, 5–10k 312, 10–15k 557, 15–20k 763, 20–25k 1.007, 25–30k 961) | TAM (basit ek kuralıyla; uygulamanın kuralları daha geniş) |
| Bunların OEWN 2025'te olanı | 38 | TAM |
| 80'lik örneklem (Claude okuması) | ≈55 özel ad, ≈10 yabancı kelime (les, und, vous), ≈7 kısaltma, ≈8 gerçek kelime/argo (ecommerce, freshmen, midfielders, plz, friggin) | ÖRNEKLEM |
| Eksik sözcük türü (OEWN'de var, uygulamada yok; ilk 12.000'den 8.159 kelime) | 14 (podcast v, screenshot v, vegan n, rival a …) | TAM |
| OEWN "fiil + parçacık" girdileri | 1.756; expr'de olmayan 53; sık fiilli olup eksik 14 (contract in, freeze off, harsh on …) | TAM |
| MAGPIE deyim türü (uzlaşma 1,0) sözlükte | 1.159 / 1.727 (**%67,1**) | TAM |
| WordNet synset'inde örnek | 32.884 / 117.659 (%27,9); **örneklerin Türkçesi: 0** | TAM |
| İfadede Türkçe yok | 7.275 / 18.209 (%40,0); hiç örnek yok 2.643 | TAM |
| Yinelenen: aynı ifade 2+ kategoride | 55 | TAM |
| Yinelenen: ft'de aynı Türkçe iki kez | 226 kelime | TAM |
| Yinelenen: own_word'de aynı tür+Türkçe iki kez | 54 kelime | TAM |
| Özel ad sıklık yanlılığı | `wfreq` ilk 200: "tom" (1.), "mary" | TAM |
| Kök/çekim eşleme hataları | §2.1 | ÖRNEKLEM (EWT) |
| Çelişen anlamlar | §2.7 | TAM + ÖRNEKLEM |
| Olası çeviri hataları | §2.6 | TAM + ÖRNEKLEM |

### 3.2 Türkçe
| Bulgu | Değer | Tür |
|---|---|---|
| tr_en lemma | 55.364; örnekli 13.635 (%24,6) | TAM |
| wordfreq TR ilk 30.000 (alfabetik 29.302) içinde tabloda lemma ya da biçim olarak bulunmayan | 6.685 (%22,8). **Yalnız tablo**: uygulamanın ek kesme kuralları uygulanmadı; gerçek kayıp UD'de %10,6 | TAM |
| 80'lik örneklem (Claude okuması) | çoğu tabloda olmayan çekimli fiil biçimi (bakıldığında, beklediğini, edilmedi), özel adlar (gülay, tolstoy), İngilizce kelimeler (party, shirt), şapkasız/aksansız yazım (cok, basladi) | ÖRNEKLEM |
| Birden çok lemmaya giden biçim | 5.903 | TAM |
| Türü boş anlam | 23.952 (FreeDict "fd" anlamları) | TAM |
| Tür "name" (özel ad madde başı) | 4.243 (ahmet, ankara, istanbul …) — bilerek tutuluyor, ama özel ad/kelime ayrımı yok | TAM |
| Aynı İngilizce karşılık iki kez | 116 lemma | TAM |
| Kök/tür | §2.1, §2.2 | UD |

## 4. Sınırlamalar
- Kaikki, Tatoeba, OPUS ve PARSEME verileri bu ortama indirilemedi; bu kaynaklarla doğrudan veri karşılaştırması
  yapılmadı (yalnız lisans ve belge incelemesi).
- KeNet Türkçesi tek referans; eş anlamlı doğru cevaplar yanlış sayılıyor (katı ölçüm).
- İnsan etiketli Türkçe anlam seçimi kümesi yok; Türkçe→İngilizce anlam seçimi (`meaningInContext`) ölçülmedi.
- Telefon üzerinde performans ölçülmedi.
- PR #104/#106 araçları (spaCy, Zemberek, gömmeler) bu kümelerde çalıştırılmadı; onların sayıları kendi raporlarından
  (Claude etiketli, ayarla aynı küme) gelir.
