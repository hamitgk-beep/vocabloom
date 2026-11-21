# Lisans ve entegrasyon raporu: sözlük aday altyapısı

Tarih: 2026-11-21. Bu rapor sekiz reponun **kod**, **model**, **veri** ve **bağımlılık** lisanslarını ayrı ayrı
ele alır. Kural: MIT, Apache-2.0 veya eşdeğer izin verici lisanslar doğrudan kullanılabilir. GPL, AGPL, CC BY-SA,
NC (ticari olmayan) ya da lisansı belirsiz bileşenler projeye **otomatik olarak girmez**, ayrı onay gerekir.

Storilex'in kendi kaynak kodu GPL-3.0, `assets/dict.db` CC BY-SA 4.0 lisanslıdır. Bu yüzden bazı copyleft
bileşenler teknik olarak uyumlu olabilir. Yine de kurala göre onaysız eklenmezler. Uygulama Play Store'da
reklamlı/ücretli olabileceği için NC şartı taşıyan her şey ayrıca risklidir.

## Nasıl doğrulandı

| Yöntem | Ne kontrol edildi |
|---|---|
| `raw.githubusercontent.com/<repo>/HEAD/LICENSE*` | Sekiz reponun lisans dosyası (ilk satırlar okundu) |
| Aynı yoldan `README*` | Model ve veri lisansı bölümleri |
| PyPI JSON API (`pypi.org/pypi/<paket>/json`) | spacy 3.8.20, stanza 1.15.1, sentence-transformers 6.3.0, wordfreq 3.1.1, fsrs 6.3.3, turkicnlp 0.5.0, zemberek-python 0.2.3 |
| `pip-licenses` (ayrı bir sanal ortamda) | spaCy + en_core_web_sm'nin bütün bağımlılık ağacı |
| `explosion/spacy-models/meta/en_core_web_sm-3.8.0.json` | Model lisansı ve eğitim kaynakları |
| `UniversalDependencies/UD_*/LICENSE.txt` | Stanza ve turkicnlp modellerinin eğitildiği ağaç bankaları |

Doğrulanamayanlar: Bu ortamdan `huggingface.co` ve GitHub API'sine erişilemedi. Hugging Face'teki model
kartları (sentence-transformers modelleri, Stanza ve turkicnlp ağırlıkları, GlotLID, Glot500) **okunamadı**. Bu
modeller için "doğrulanmadı" yazıldı.

## Özet

| # | Repo | Kod | Model | Veri | Karar |
|---|---|---|---|---|---|
| 1 | explosion/spaCy | MIT ✅ | en_core_web_sm 3.8.0: MIT ✅ | Model meta: OntoNotes 5 (Explosion'ın ticari lisansı), WordNet 3.0 License | **Prototipte isteğe bağlı** |
| 2 | orionsheep/wordlink | MIT ✅ | WordLink-Edge: Qwen2.5 lisansı ⚠️ | `data/`: ECDICT (MIT) ve şartları ayrıca belirtilmemiş kaynaklar ⚠️ | Dahil edilmedi |
| 3 | open-spaced-repetition/fsrs4anki | MIT ✅ | (FSRS parametreleri) | Eğitim verisi AnkiWeb kullanıcılarından, alınmıyor | Uygun, sonraki aşama |
| 4 | huggingface/sentence-transformers | Apache-2.0 ✅ | Her model ayrı, doğrulanmadı ⚠️ | Model eğitim verileri modele göre değişir ⚠️ | Dahil edilmedi |
| 5 | stanfordnlp/stanza | Apache-2.0 ✅ | UD ağaç bankalarıyla eğitilmiş ⚠️ | EWT: CC BY-SA 4.0, GUM: CC BY-NC-SA 4.0, Türkçe IMST: CC BY-NC-SA ⚠️ | Dahil edilmedi, onay gerekli |
| 6 | rspeer/wordfreq | Apache-2.0 ✅ | – | CC BY-SA 4.0 (+ Google Books Ngrams, SUBTLEX şartları) ⚠️ | Dahil edilmedi, onay gerekli |
| 7 | ahmetaa/zemberek-nlp | Apache-2.0 ✅ | Sözlük kaynakları depoda, README yalnız "kod Apache" diyor | – | Uygun, sonraki PR (Java) |
| 8 | turkic-nlp/turkicnlp | Apache-2.0 ✅ | Apertium FST: GPL-3.0 ⚠️, Türkçe Stanza: IMST (NC) ⚠️, GlotLID/Glot500 doğrulanmadı | UD treebank'leri ⚠️ | Dahil edilmedi, onay gerekli |

## Ayrıntılar

### 1. spaCy
- **Kod:** MIT (`LICENSE`: "The MIT License (MIT) Copyright (C) 2016-2024 ExplosionAI GmbH ..."). PyPI: 3.8.20, MIT.
- **Model:** `en_core_web_sm` 3.8.0, meta dosyasında `"license": "MIT"`. Eğitim kaynakları: OntoNotes 5 ("commercial
  (licensed by Explosion)"), ClearNLP dönüşüm kuralları (yalnız atıf, kod yok), WordNet 3.0 (WordNet License; proje
  zaten kullanıyor).
- **Bağımlılıklar** (`pip-licenses`): MIT, BSD, Apache-2.0, ISC, PSF; `certifi` ve `tqdm` MPL-2.0 (dosya düzeyinde
  zayıf copyleft, değiştirmeden kullanmak serbest). GPL yok.
- **Entegrasyon:** `adapters/english.py` → `SpacyEnglishAnalyzer`. İsteğe bağlı, yalnız geliştirici makinesinde
  `--engine spacy` ile çalışır. Uygulamaya girmez. Adaptör, model lisansı MIT değilse açılmayı reddeder.
- **Boyut:** Ölçülen sanal ortam (spaCy, model, bağımlılıklar, zemberek-python denemesi dahil) 423 MB. Yalnız geliştirici makinesinde.

### 2. wordlink (orionsheep)
- **Kod:** MIT ("Copyright (c) 2026 OrionSheep and WordLink contributors").
- **Veri:** README: "`data/` bundles lexical resources from other projects, including ECDICT (MIT); check each
  source's terms before reusing the data on its own." Yani verinin bir kısmının lisansı belirtilmemiş.
- **Model:** WordLink-Edge, Qwen2.5-1.5B-Instruct üzerine ince ayar, "Model weights follow the Qwen2.5 license".
- **Uygunluk:** Next.js/PostgreSQL uygulaması, İngilizce–Çince odaklı. Kelime bağı grafiği (eş anlam, türev,
  benzer yazım) fikir olarak yararlı. **Hiçbir veri veya model alınmadı.** Yalnız fikir düzeyinde kullanılabilir.

### 3. fsrs4anki
- **Kod:** MIT ("Copyright (c) 2022 open-spaced-repetition"). Python kütüphanesi `fsrs` (py-fsrs) 6.3.3 da MIT.
- **Uygunluk:** Kişiselleştirilmiş tekrar zamanlaması için uygun. Bu PR'ın kapsamı dışında. Uygulamadaki tekrar
  sistemi (`lib/data/review.dart`) ve kullanıcı verisi değiştirilmedi.

### 4. sentence-transformers
- **Kod:** Apache-2.0. PyPI 6.3.0: `license_expression: Apache-2.0`.
- **Model:** 15.000'den fazla model var, her birinin lisansı ayrı. `all-MiniLM-L6-v2` ve
  `paraphrase-multilingual-MiniLM-L12-v2` gibi modeller genelde Apache-2.0 olarak bilinir. Ancak model kartları bu
  ortamdan **okunamadı**. Eğitim veri setlerinin (ör. MS MARCO) şartları ayrıca incelenmeli.
- **Bağımlılık:** PyTorch + transformers (birkaç GB).
- **Karar:** Anlam eşleştirme (yeni anlam mı, var olan mı) için ileride değerli. Model seçildiğinde ayrı lisans
  doğrulaması ve onay gerekiyor.

### 5. Stanza
- **Kod:** Apache-2.0 ("Copyright 2019 The Board of Trustees of The Leland Stanford Junior University").
- **Model ve veri:** README: "We currently provide models for all of the Universal Dependencies treebanks".
  Kontrol edilen UD lisansları:
  - UD_English-EWT: **CC BY-SA 4.0**
  - UD_English-GUM: **CC BY-NC-SA 4.0** (ticari olmayan)
  - UD_Turkish-IMST: **CC BY-NC-SA** (README: 4.0, LICENSE.txt: 3.0)
  - UD_Turkish-BOUN: CC BY-SA 4.0
- **Karar:** Modellerin lisansı eğitim verisinden bağımsız değerlendirilemiyor. NC/SA riski var, **onay gerekli**.

### 6. wordfreq
- **Kod:** Apache-2.0 ("Copyright 2022 Robyn Speer").
- **Veri:** README: "includes data files that may be redistributed under a Creative Commons
  Attribution-ShareAlike 4.0 license". Ayrıca Google Books Ngrams ve SUBTLEX şartları geçerli. README'ye göre
  veri artık güncellenmiyor.
- **Karar:** Kelime sıklığı için yararlı. Ancak sıklık değerleri CC BY-SA veriden türetildiği için **ayrı onay**
  gerekiyor. (Projede `wfreq` tablosu zaten var.)

### 7. Zemberek-NLP
- **Kod:** Apache-2.0 ("Copyright 2018 Ahmet A. Akın, Mehmet D. Akın"). Son sürüm 0.18.0 (Maven, GitHub üzerindeki
  depo).
- **Kaynaklar:** Biçimbirim sözlüğü depo içinde. README yalnızca "Code is licensed under Apache License, Version 2.0"
  diyor, sözlük dosyaları için ayrı bir lisans belirtmiyor. Aynı depoda dağıtıldıkları için Apache-2.0 sayılıyor,
  yazara teyit ettirmek iyi olur.
- **Python portu:** `zemberek-python` 0.2.3 (Apache-2.0, bağımlılıkları antlr4 BSD, numpy BSD) **Python 3.13'te
  açılmıyor** (denendi: `antlr4` 4.8, `typing.io` modülünü arıyor; ayrıca kaldırılan `pkg_resources`'a bağlı).
- **Karar:** Lisans uygun. Java (JVM) gerektirdiği için ikinci PR'da `TurkishAnalyzer` arayüzüne bir adaptör
  olarak eklenebilir. Şimdilik Türkçe için yerleşik, sözlük tabanlı adaptör kullanılıyor.

### 8. turkicnlp
- **Kod:** Apache-2.0. PyPI 0.5.0: `Apache-2.0`.
- **Model ve veri:** README: "library is Apache-2.0; Apertium GPL-3.0 data downloaded separately". Türkçe
  biçimbirim çözümlemesi Apertium FST (**GPL-3.0**). Türkçe Stanza modelinin varsayılanı IMST (**CC BY-NC-SA**).
  GlotLID ve Glot500 modelleri Hugging Face'te, **doğrulanmadı**. LLM arka uçları çevrimiçi servisler.
- **Karar:** **Onay gerekli.** Dahil edilmedi.

## Aday verisinin lisansı: güven sınırı

- Araçtaki kaynak onayı (`approve-source`), bir kişinin adını ve yazdığı kanıt metnini kaydeder. Lisans otomatik
  doğrulanmaz.
- "Public domain" eser, ülke, baskı ve çeviri düzeyinde ayrıca değerlendirilmelidir. Project Gutenberg metinleri
  ABD hukukuna göre kamu malıdır. Diğer ülkeler ve modern baskılar ya da çeviriler için ayrı kontrol gerekir.
- Kaynaktan alınan örnek cümlelerin sözlükte yeniden dağıtılması ayrıca kontrol edilmelidir. Atıf gerektiren
  lisanslarda atıf, veriyle birlikte taşınmalıdır.
- `assets/dict.db` CC BY-SA 4.0 lisanslıdır. Yeni üretilen veriye otomatik olarak "telifsiz" muamelesi yapılmaz.
  Sözlüğe girecek her veri için dağıtım öncesinde ayrı bir lisans uygunluk kontrolü gerekir.
- Bu kontroller güvenlik sınırı değildir, geliştirici iş akışındaki riski azaltmak içindir.

## Bu PR'da gerçekte kullanılanlar

| Bileşen | Lisans | Zorunlu mu |
|---|---|---|
| Python standart kütüphanesi (sqlite3, re, json ...) | PSF | Evet |
| Yerleşik İngilizce ve Türkçe adaptörler (bu PR'da yazıldı) | GPL-3.0 (Storilex kaynak kodu) | Evet |
| spaCy 3.8 + en_core_web_sm 3.8.0 | MIT + MIT | Hayır, `--engine spacy` ile |
| `assets/dict.db`, `assets/tr_en.db` | mevcut lisansları | Yalnız salt okunur karşılaştırma |

Prototipte örnek metin olarak yalnızca kamu malı metinler kullanıldı: Project Gutenberg #11 (Alice's Adventures in
Wonderland, 1. bölüm, `library/books/pg-11.md.gz`) ve uygulamanın Türkçe kütüphanesindeki "Al Elimi" (katalogda
"Public domain").
