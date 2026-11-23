# Görev 5M: Genel cümle çözümleyici ve kalıp tanıyıcı (yama yerine motor)

Tarih: 2026-11-23. Dal: `claude/project-thread-6h1ydd`, **#122'nin (5L) HEAD'i `fe7ced3` üzerine** kuruldu.
Zincir: #116 → #117 → #118 → #119 → #120 → #121 → #122 → bu PR. Hiçbir şey birleştirilmedi veya yayınlanmadı.

## 1. Kısa sonuç

* 5F–5L boyunca her hata için ayrı bir kural yazıldı. Bu görevde bunun yerine **birbirine bağlı dört motor** kuruldu
  (§3). Hepsi Dart'ta, çevrimdışı çalışıyor; model, ağ çağrısı veya yeni bağımlılık eklenmedi. Uygulamada bayrak
  arkasında duruyor ve **varsayılan olarak KAPALI** (`sentenceAnalyzer5m = false`).
* **Kilitli, hiç kullanılmamış final kümesi** (DiMSUM tweetleri, 969 cümle; hash'i kod yazılmadan önce commit edildi,
  `433b8b7`). Tek koşu yapıldı ve ön kayıtlı **6 kabul ölçütünün 6'sı da tuttu**:
  **142 karar düzeldi, 22 karar bozuldu** (p = 1e-22). Aday F1 0,492 → 0,576. Yanlış "kesin" 22 → 13. Doğru
  "kesin" 45 → 45, yani hiç kayıp yok. Span F1 0,201 → 0,208.
* Kazancın neredeyse tamamı **Motor 3'ten** (bağlamsal "bu kalıp burada gerçekten kalıp mı?" puanlayıcısı, 35 KB)
  geliyor. **Sözdizimsel şablonlar tek başına ölçülebilir bir fayda getirmedi** (final +6/−8, p 0,79). Bunu
  saklamıyorum: şablonların değeri mimaride. Tek ayrıştırma var, iyelik boşluğu artık kalıbın kelimesi sayılmıyor
  ("waste ~~your~~ time") ve ayrık phrasal verb'ler bulunuyor. Doğruluk kazancı bu katmandan gelmiyor.
* **Bedeli:** puanlayıcı insan anotatörlerin "birim değil" dediği adayları gizliyor. Bunların bir kısmı öğrenen
  için yine de yararlı: "go back", "need to", "you know" ve 5L'in korunan örneği **"The TV was on all night"**
  ("be on" artık altı çizili değil). Ayrıca finalde 22 gerçek kayıp var, örneğin "once upon a time", "in terms of",
  "if I were you", "no way", "come on". Bu yüzden bayrağı açma kararı Hamit'in (§7).

## 2. Önceki görevlerden ne öğrenildi (GitHub'da doğrulandı)

* **#121 (5K):** spaCy, Stanza ve UDPipe ile gerçek bağımlılık ayrıştırması yapıldı. Kalıp kuralları ağaçların
  üzerine yazıldı. Sonuç bağımsız MAGPIE setinde **anlamlı biçimde daha kötü** çıktı (spaCy +12/−29, p 0,012).
  Bu görevin ana çıkarımı şu: hata ayrıştırıcının yokluğundan kaynaklanmıyor. Sözlükteki birçok kayıt cümlede
  yan yana gelen ama birim olmayan kelimelere uyuyor ("be on", "need to", "in this"). Hangisinin birim olduğunu
  sözdizimi tek başına söyleyemiyor, örneklerden öğrenilmesi gerekiyor.
* **#122 (5L):** dar ve ölçülmüş bir kural (A) kabul edildi. Genel kurallar (A2, B, C) geliştirme setinde karışık
  sonuç verdi ve kapalı kaldı.

## 3. Mimari: dört motor, tek karar

Büyük dil modellerinin yaptığı şeyin küçük ve çevrimdışı karşılığı şu: her kelimeyi cümlenin tamamıyla birlikte
oku, bir kalıbın gerçekten kalıp olup olmadığına çok sayıda insan etiketli örnekten öğrenilmiş ipuçlarıyla karar ver.

| motor | dosya | ne yapar | boyut / hız (masaüstü) |
|---|---|---|---|
| 1. Cümle ayrıştırıcı | `lib/nlp/construction.dart` `ConstructionParser` | kelime türü (sözlüğün `posOf`'u + kapalı sınıflar + bağlam), isim öbekleri ve başları, cümle içi kırılmalar | kod; **0,09–0,17 ms/cümle** |
| 2. Kalıp adayı üretici | `TemplateCompiler`, `TemplateMatcher` | 18.209 kaydın 4.595'i şablona çevrilir: fiil + isim öbeği (baş kelime, artikel politikası, zorunlu sıfatlar), iyelik boşluğu, `sb/sth` boşluğu, edyilgen ("the decision was made"), uzun nesneli ayrık phrasal verb ("turn the kitchen light off"). Deyimler donuk: yazılan artikel aynı olmalı, araya sıfat giremez ("ring ~~the little~~ bell"). Diğer kayıtlar mevcut `PhraseMatcher` ile eşleşir. | kod; **0,05–0,10 ms/cümle** |
| 3. Bağlamsal birim kararı | `unitFeatures`, `UnitScorer`, `lib/nlp/unit_weights_5m.dart` | aday için 20 kadar özellik (kategori, uzunluk, boşluk, önceki ve sonraki kelime türü, arkasından isim öbeği geliyor mu, cümle sonu, büyük harf, başka adayla çakışma, **SenseEngine'in güveni**, Türkçe durumu, kaydın kimliği), lojistik model, eşik 0,40 | **1.160 ağırlık, 35 KB Dart sabiti** |
| 4. Anlam ve güven | mevcut `SenseEngine` (değişmedi) | kesin / olası / anlam seçilemedi, panel, kart notlama | — |

Bağlantı (`lib/ui/paragraph_view.dart`, yalnız bayrak açıkken):
`analyze()` → `SentenceAnalyzer.matches` (motor 1+2) → okuyucunun `_isLiteral`'ı → `SentenceAnalyzer.notAUnit`
(motor 3, SenseEngine'in kendi güveniyle) → adayın altı çizilmez. Kelimelere tek tek dokunmak aynen çalışır.
Panel ve kart (`resolve`, `fit`) değişmedi. Kart notlaması da bu yüzden değişmedi (ölçümde "kart onayı" aynı).

Motor 3'ün ağırlıkları yalnız **STREUSLE 4.x train+dev** adaylarından öğrenildi (2.047 aday, 1.184 birim). Sözlük
verisi okunmadı ve değiştirilmedi.

## 4. Değerlendirme setleri

| set | kaynak | rol |
|---|---|---|
| dev_streusle | STREUSLE 4.x train+dev (3.279) | motor 3'ün **eğitimi**; 5K/5L'de görüldü |
| hold_dimsum, hold_parseme | DiMSUM 2016 test (1.000), PARSEME 1.1 EN (6.844) | 5L'de bir kez açıldı; burada **geliştirme** (C, eşik, sözcük özellikleri seçildi) |
| **final_tweets** | DiMSUM 2016 **train**'in tweet bölümü (Lowlands + Ritter, 969), STREUSLE/DiMSUM test/PARSEME/mini ile çakışanlar çıkarıldı | **kilitli final**, kod yazılmadan önce hash'lendi (`final_5m_LOCKED.sha256`), tek koşu |

Bağımsızlık: final için yeni cümleler ve yeni tür (tweet) var. Anotasyon geleneği aynı (DiMSUM ≈ STREUSLE). Etiket
birimi 5L ile aynı: "adayın bütün kelimeleri tek bir insan MWE'sinin içinde" = birim. Bu Türkçe anlamın doğruluğunu
ölçmüyor. Korpus cümleleri commit edilmedi, yalnız hash'ler, sayılar ve toplu metrikler commit edildi.

## 5. Sonuçlar

Tanımlar 5L ile aynı (`tools/nlp_research_5l/metrics_5l.py`). +/− = mevcut motora (`cur`) göre düzelen/bozulan
karar; p = kesin McNemar.

### 5.1 Final (tek koşu, donmuş aday `a68adcc`)

| sistem | P | R | F1 | FPR | yanlış kesin | doğru kesin | kart onayı | + | − | p | span P / R / F1 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| cur (bugünkü uygulama) | 0,362 | 0,767 | 0,492 | 0,836 | 22 | 45 | 21 | — | — | — | 0,333 / 0,144 / 0,201 |
| tpl (motor 1+2) | 0,362 | 0,776 | 0,493 | 0,847 | 22 | 45 | 21 | 6 | 8 | 0,79 | 0,333 / 0,146 / 0,203 |
| **unit (motor 1+2+3, birincil)** | **0,487** | 0,703 | **0,576** | **0,458** | **13** | **45** | 21 | **142** | **22** | **1e-22** | **0,453** / 0,135 / **0,208** |
| unitS ("kesin" asla gizlenmez) | 0,474 | 0,703 | 0,566 | 0,483 | 22 | 45 | 21 | 133 | 22 | 1e-20 | 0,440 / 0,135 / 0,207 |

Kabul ölçütleri (`tools/parser_research_5m/ACCEPTANCE_5M.md`, koşudan önce commit edildi):
1. düzelen > bozulan, p < 0,05: **142 > 22, p = 1e-22 ✓**
2. F1 artmalı: **0,492 → 0,576 ✓**
3. yanlış kesin artmamalı: **22 → 13 ✓**
4. doğru kesin kaybı en fazla 4: **0 ✓**
5. span F1 en fazla 0,01 düşebilir: **+0,007 ✓**
6. DB hash'leri aynı: **✓** (§8)

Kategori kırılımı (unit): tek başına duran adaylar +124/−17, phrasal verb +22/−4, deyimler +26/−9, edat öbekleri
+30/−3, chunk +17/−3, modal +12/−0, bağlaç +11/−0, binomial +0/−2.

### 5.2 Geliştirme setleri (bilgi için; seçim bunlarla yapıldı)

| set | sistem | F1 | FPR | yanlış kesin | doğru kesin | + | − |
|---|---|---|---|---|---|---|---|
| DiMSUM test | cur → unit | 0,498 → 0,566 | 0,805 → 0,420 | 12 → 7 | 27 → 23 | 134 | 27 |
| PARSEME 1.1 (yalnız phrasal verb) | cur → unit | 0,411 → 0,459 | 0,680 → 0,547 | 301 → 249 | 113 → 110 | 149 | 15 |
| DiMSUM test | cur → tpl | 0,498 → 0,502 | | 12 → 12 | | 6 | 5 |
| PARSEME | cur → tpl | 0,411 → 0,410 | | 301 → 307 | | 2 | 8 |

Seçimler: C ∈ {0,3; 1,0}, sözcük özellikleri açık/kapalı, eşik ∈ {0,3; 0,4; 0,5}. Sözcük özellikleri (kaydın kimliği)
her iki sette de daha iyiydi. Eşik 0,5 recall'u fazla düşürdü.

### 5.3 Neler düzeldi, neler bozuldu (final; cümle metni commit edilmedi)

* **Düzelenler (çoğu):** "need to" (9), "you know", "I see", "I mean", "you see", "as long as", "for the first time",
  "the other day", "go back", "in this", "on it", "full of", "take after", "may have been". Anotatörler bunları
  bu cümlelerde birim saymıyor.
* **Bozulanlar (22):** "once upon a time", "in terms of", "if I were you", "no way", "come on", "come back" (2),
  "get started", "far be it", "one and only", "yours truly", "world record", "Break Your Heart", "you know" (1),
  "kick it", "switch out", "John Henry", "Q and A". Ayrıca iyelik boşluğu yüzünden aynı adayın iki satırı ("open one's
  mouth", "close one's eyes").
* Denenen ama **kabul edilmeyen** bir düzeltme, finalden sonra ve yalnız geliştirme setlerinde: "3+ kelimelik bitişik
  kalıp asla gizlenmez". "Once upon a time" gibi kayıpları geri getirir, ama DiMSUM test F1'i 0,566 → 0,541'e düşürüyor.
  Bu bir öğrenen-değeri / anotasyon-ölçütü tercihi. Yeni bir kilitli setle ölçülmeden açılmamalı.

## 6. Seçenekler: boyut, hız, lisans

| seçenek | ne | boyut | hız | lisans (ticari / GPL-3.0) | ölçüm | karar |
|---|---|---|---|---|---|---|
| **5M motorları 1–3 (bu PR)** | Dart kural + öğrenilmiş lojistik model | kod + 35 KB | ~0,3 ms/cümle masaüstü | GPL-3.0 kod. Ağırlıklar CC BY-SA 4.0 anotasyon türevi (GPLv3 ile tek yönlü uyumlu, atıf gerekli) | final +142/−22 | **önerilen ilk adım** (bayrak kapalı) |
| spaCy / Stanza / UDPipe (5K) | bağımlılık ayrıştırıcı | 12 MB – 327 MB, Python | — | UDPipe EWT modelleri **NC** (elendi); spaCy MIT ama Python | MAGPIE'de kötüleştirdi | uygulama için hayır |
| LSR Tagger (Liu vd. 2021) | BERT-large + MWE/anlam sınıfı etiketleme | ~1,3 GB | GPU sınıfı | kod MIT; modeller Google Drive'da (buradan erişilemedi) | bert-base ile aynı yöntem: final span F1 0,431, küçük modelden iyi değil | telefona sığmaz, gerek de yok |
| BeeParser (MWE 2026, gerçek bir sistem) | XLM-R-base + B/I/O başlığı (PARSEME 2.0, 8 dil) | ~1,1 GB | — | kod MIT; model yayımlanmadı; **İngilizce yok** | aynı yöntem bert-base ve küçük modellerle ölçüldü; XLM-R çalıştırılmadı | telefona sığmaz |
| küçük kodlayıcı + B/I/O (bert-tiny, Ettin-17m) | kalıp sınırı etiketleyici | int8 ONNX 11–17 MB | masaüstü 1 çekirdek 1–2,5 ms; telefonda ölçülmedi | Ettin MIT, bert-tiny Apache-2.0; eğitim verisi CC BY-SA | final span F1 0,425–0,442; motor 3'e eklenince bozulan 22 → 17 | **ikinci adım adayı** |
| UDPipe 1 kodu + kendi EWT modelimiz | C++ ayrıştırıcı, dart:ffi | ~15–20 MB (doğrulanmadı) | hızlı | MPL-2.0 + CC BY-SA 4.0 | 5K'da ayrıştırıcı kazanç vermedi | şimdilik gerek yok |
| wink-nlp / compromise.js | JS kural/sözlük etiketleyici | 0,25–1 MB | hızlı | MIT | — | yalnız fikir kaynağı |
| Flutter çalıştırıcı | `flutter_onnxruntime` (MIT, aktif) / `tflite_flutter` (Apache-2.0) | — | — | uyumlu | — | ikinci adım için |

Elenen eğitim verileri: UD GUM, LinES, ParTUT (NC lisans parçaları). Kullanılabilir olanlar: UD EWT, Atis, STREUSLE,
PARSEME EN (CC BY / CC BY-SA). Eğitilmiş ağırlıkların CC BY-SA türevi sayılıp sayılmadığı hukuken net değil.
Güvenli yol, ağırlıkları CC BY-SA 4.0 ile atıf vererek dağıtmak.

### 6.1 Sinir ağı kalıp etiketleyicileri (LSR / BeeParser yöntemi, burada yeniden eğitildi)

LSR Tagger ve BeeParser'ın hazır İngilizce modeli yok ya da erişilemiyor. İkisinin de yöntemi aynı: bir kodlayıcı ve
her kelime için B/I/O etiketi. Bu yöntem burada **yeniden eğitildi**: `tools/parser_research_5m/neural_tagger_5m.py`,
yalnız STREUSLE train+dev, 3 tur, sabit ayarlar. Bunlar orijinal modellerin kendisi değil, aynı yöntemin kopyaları.
Ölçü: kesin span eşleşmesi (güçlü MWE'ler). Karşılaştırma için Storilex sözlük eşleştiricisinin aynı ölçüsü final'de
0,201, DiMSUM test'te 0,236.

| model | parametre | DiMSUM test span F1 | **final span F1 (P / R)** | ONNX int8 | int8 = PyTorch etiket uyumu | 1 çekirdek CPU, int8 |
|---|---|---|---|---|---|---|
| bert-tiny (L-4, H-256; Apache-2.0) | 4,4 M | 0,426 | **0,425** (0,467 / 0,390) | **11,3 MB** | %98,5 | ~1,2 ms/cümle |
| Ettin-encoder-17m (MIT) | 16,9 M | 0,448 | **0,442** (0,479 / 0,410) | 17,1 MB | %89,6 (int8 bozuyor; fp16 ~34 MB gerekir) | ~2,5 ms/cümle |
| bert-base-cased (LSR tarzı) | 107,7 M | 0,460 | **0,431** (0,541 / 0,359) | ölçülmedi (~110 MB) | — | ~33 ms/cümle (4 çekirdek) |
| XLM-R-base (BeeParser tarzı) | 278 M | — | — | — | — | **çalıştırılmadı**: CPU'da ~1,5 saat eğitim, telefona sığmaz, bert-base büyük modelin kazanç getirmediğini zaten gösterdi |

Bulgular:
* Küçük model (4,4 M parametre, 11 MB) kalıp **sınırlarını** bulmakta sözlük eşleştiricisinin iki katından iyi
  (0,425'e karşı 0,201). Büyük modeller bunu anlamlı biçimde aşmıyor (bert-base 0,431). Telefon için doğru boyut küçük
  model.
* Ama sinir ağı **anlam vermiyor**. Yalnız "burada bir kalıp var" diyor. Tek başına filtre olarak kullanıldığında
  recall çok düşüyor (DiMSUM test: R 0,79 → 0,46). Bu yüzden motor 3'e bir **özellik** olarak eklendi (`unn3`,
  önceden kaydedildi, 2 katlı çapraz eğitim):

| final | F1 | yanlış kesin | doğru kesin | + | − | p |
|---|---|---|---|---|---|---|
| unit (yalnız Dart) | 0,576 | 13 | 45 | 142 | 22 | 1e-22 |
| unn3 (Dart özellikleri + bert-tiny) | 0,576 | 12 | 45 | 134 | **17** | 1e-23 |

  Sinir ağı aynı F1'de bozulan kararı 22'den 17'ye indiriyor. Küçük ama tutarlı bir ek: DiMSUM test'te 27 → 17,
  PARSEME'de 15 → 9. Uygulamaya eklemek bir ONNX çalıştırıcısı (`flutter_onnxruntime`, MIT) ve 11 MB'lık bir varlık
  demek. Bu PR'da eklenmedi; ikinci adım olarak öneriliyor.
* Hız (masaüstü, tek çekirdek): bert-tiny int8 ~1,2 ms/cümle. Telefonda bunun birkaç katı beklenir (MobileBERT
  makalesi Pixel 4'te 15–25 M parametre için 40–62 ms bildiriyor). Gerçek cihazda ölçülmedi.

## 7. Öneri ve sonraki adım

1. **Bayrak şimdilik kapalı kalmalı.** Ölçüm ölçütleri geçti, ama bedeli öğrenen deneyimini etkiliyor ("go back",
   "you know", "TV was on" altı çizili olmaktan çıkıyor). Hamit'in kararı: (a) bayrağı açmak, (b) yalnız "kesin"leri
   koruyan `unitS`'i açmak (yanlış kesin azalmıyor ama altı çizili yanlış "olası"lar azalıyor), (c) önce bir telefonda
   denemek.
2. Motor 3'ün gizleme kararı ileride üç düzeyli olabilir: altını çizme, soluk çiz ("kalıp olmayabilir"), gizle.
3. İkinci adım: bert-tiny (11 MB, int8 ONNX) motor 3'e özellik olarak eklenir. Finalde bozulan kararları 22'den
   17'ye indirdi. Bunun için `flutter_onnxruntime` bağımlılığı, telefonda hız ölçümü ve yeni bir kilitli set gerekir.
4. Asıl sınırlayıcı artık sözlük. Final'de insan MWE'lerinin büyük çoğunluğu için sözlükte hiç aday yok (span recall
   0,14). Sinir ağı bunların bir kısmını buluyor (recall 0,39), ama anlam vermek için sözlük kaydı gerekiyor. #121'in
   228 yüksek riskli kaydı da hâlâ insan incelemesi bekliyor.

## 8. Doğrulama

* `assets/dict.db` SHA-256 `ab4a7a53…221a9c`, `assets/tr_en.db` `49a661b9…cfa818`: önce ve sonra aynı.
* `flutter analyze`: 0 hata, 0 uyarı, 127 info (5L ile aynı sayı).
* `flutter test`: 631 geçti, 12 atlandı, 3 başarısız (bilinen PDFium `setUpAll`: import_completeness, picture_book,
  text_repair). 5L: 623/12/3. +8, yeni `test/sentence_analyzer_5m_test.dart`.
* Mobil cihazda ölçüm yapılmadı.
* Final koşusu: `final_5m_LOCKED.sha256` hash'leri koşudan hemen önce yeniden doğrulandı (2/2 aynı).

## 9. Dosyalar

* `lib/nlp/construction.dart` (yeni): motor 1–3, `SentenceAnalyzer`, `sentenceAnalyzer5m` bayrağı (kapalı).
* `lib/nlp/unit_weights_5m.dart` (yeni, üretilmiş): motor 3'ün ağırlıkları.
* `lib/ui/paragraph_view.dart`, `lib/app_state.dart`: yalnız bayrak açıkken çalışan bağlantı. Kapalıyken okuyucu
  5L ile birebir aynı (testle doğrulandı).
* `test/sentence_analyzer_5m_test.dart` (yeni, 8 test).
* `tools/parser_research_5m/`: final set üretici + kilit, kabul ölçütleri, iz (`trace_5m_test.dart`), puanlayıcı
  eğitimi (`train_unit_5m.py`), sinir ağı eğitimi/ölçümü/ONNX (`neural_tagger_5m.py`, `nn_eval_5m.py`,
  `stack_nn_5m.py`, `export_onnx_5m.py`), model JSON'ları.
* `docs/nlp_engine_research/nlp_5m_results/`: yalnız toplu metrikler.

Commit **edilmeyenler**: korpus cümleleri (STREUSLE, DiMSUM, PARSEME), sinir ağı ağırlıkları ve ONNX dosyaları,
Python ortamları. `assets/`, `pubspec.*` değişmedi. #114 lisans/yayın kapısı atlanmadı; uygulama paketine yeni veri
veya model girmiyor (Dart ağırlık dosyası hariç: CC BY-SA 4.0 STREUSLE anotasyonu türevi, atıf dosyanın başında).
