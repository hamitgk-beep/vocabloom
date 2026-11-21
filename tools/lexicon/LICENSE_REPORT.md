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
| PyPI JSON API (`pypi.org/pypi/<paket>/json`) | spacy 3.8.18 (3.8.20 PyPI'da geri çekildi), stanza 1.15.1, sentence-transformers 6.3.0, wordfreq 3.1.1, fsrs 6.3.3, turkicnlp 0.5.0, zemberek-python 0.2.3 |
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
| 7 | ahmetaa/zemberek-nlp | Apache-2.0 ✅ | Sözlük ve model jar içinde, ayrı lisans yok (Apache-2.0 sayılıyor). Kökeni için aşağıya bakın ⚠️ | Guava, Caffeine Apache-2.0; protobuf, ANTLR BSD-3 ✅ | İsteğe bağlı adaptör olarak eklendi, yalnız çözümleme için |
| 8 | turkic-nlp/turkicnlp | Apache-2.0 ✅ | Apertium FST: GPL-3.0 ⚠️, Türkçe Stanza: IMST (NC) ⚠️, GlotLID/Glot500 doğrulanmadı | UD treebank'leri ⚠️ | Dahil edilmedi, onay gerekli |

## Ayrıntılar

### 1. spaCy
- **Kod:** MIT (`LICENSE`: "The MIT License (MIT) Copyright (C) 2016-2024 ExplosionAI GmbH ..."). Kullanılan sürüm
  3.8.18 (MIT). 3.8.20 PyPI'da "incomplete due to size limit" gerekçesiyle geri çekildiği için kullanılmadı.
- **Model:** `en_core_web_sm` 3.8.0, meta dosyasında `"license": "MIT"`. Eğitim kaynakları: OntoNotes 5 ("commercial
  (licensed by Explosion)"), ClearNLP dönüşüm kuralları (yalnız atıf, kod yok), WordNet 3.0 (WordNet License; proje
  zaten kullanıyor). Model, GitHub sürüm sayfasından SHA-256 ile sabitlenmiş tekerlek olarak kurulur.
- **Bağımlılıklar** (kurulu paketlerin üst verisinden, 2026-11-21): MIT, BSD-2/3, Apache-2.0, ISC, PSF; `certifi`
  MPL-2.0, `tqdm` MPL-2.0 AND MIT (dosya düzeyinde zayıf copyleft, değiştirmeden kullanmak serbest). GPL yok.
  Tam liste `constraints-spacy.txt` içinde.
- **Entegrasyon:** `adapters/english.py` → `SpacyEnglishAnalyzer`. İsteğe bağlı, yalnız geliştirici makinesinde
  `--engine spacy` ile çalışır. Uygulamaya girmez. Adaptör, model lisansı MIT değilse açılmayı reddeder.
- **Boyut:** Sanal ortam yaklaşık 304 MB, yalnız geliştirici makinesinde (`build/lexicon/venv`, git'e girmez).

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
- **Kod:** Apache-2.0 ("Copyright 2018 Ahmet A. Akın, Mehmet D. Akın"). README: "Code is licensed under Apache
  License, Version 2.0". SSS: kaynak ve ikili dosyalar Apache-2.0 şartlarıyla, kapalı kaynaklı ticari projelerde
  bile kullanılabilir. `contributors.txt`: kodun bir kısmı TÜBİTAK BİLGEM'de geliştirilmiş.
- **Sürüm:** 0.18.0 (CHANGELOG: 10 Kasım 2026, Java 21 gerekir). Yazarın GitHub üzerindeki Maven deposundan
  (`ahmetaa/maven-repo`) alınır. Yayımlanalı 11 gün oldu: yeni bir sürüm olduğu için bütün jar'lar SHA-256 ile
  sabitlendi (`zemberek/jars.lock`). İstenirse 0.17.1'e dönülebilir, ama onun belirsizlik giderme doğruluğu
  belirgin biçimde düşük (CHANGELOG: %77.5'e karşı %92.8).
- **Jar içindeki kaynaklar:** `tr/lexicon.bin` (kök sözlüğü), `tr/tdk-obsolete.dict`, `tr/informal.dict`,
  `tr/first-10K`, `tr/ambiguity/model_10k_argon_v24.bin` (belirsizlik giderme modeli), cümle sınırı modeli,
  kısaltma listeleri. Hiçbiri için ayrı lisans dosyası yok, depo lisansı (Apache-2.0) geçerli sayılıyor.
- **Köken uyarısı ⚠️:** Depodaki metin sözlüklerinin adları (`master-dictionary.dict`, `non-tdk.dict`,
  `tdk-obsolete.dict`) kök listesinin büyük ölçüde TDK sözlüğünün madde başlarıyla örtüştüğünü düşündürüyor.
  `proper-from-corpus.dict` ve `abbreviations.dict` dosyalarında "collected from a corpus" notu var. Belirsizlik
  giderme modeli bir haber derlemi üzerinde eğitilmiş (CHANGELOG'da `cnn-turk` adı geçiyor). Yazarlar bunları
  Apache-2.0 ile dağıtıyor. Ama bu listeler **sözlük içeriği olarak** kopyalanırsa köken sorusu doğar. Bu yüzden:
  - Zemberek yalnızca metindeki kelimeleri **çözümlemek** (kök ve sözcük türü bulmak) için kullanılır.
  - Zemberek'in kök listesi, ad listeleri veya başka bir dosyası aday veritabanına ya da sözlüğe aktarılmaz.
  - Adaylar her zaman izinli bir metinde geçen kelimelerden gelir. Kaynağı da o metindir.
  - Yazara kaynakların kökeni ve lisansı sorulabilir (plan belgesindeki açık karar).
- **Bağımlılıklar** (Maven POM'larından ve jar içindeki LICENSE dosyalarından doğrulandı): Guava 33.7.1-jre ve
  failureaccess 1.0.3 (Apache-2.0), Caffeine 3.2.4 (Apache-2.0), protobuf-java 4.36.2 (BSD-3-Clause),
  antlr4-runtime 4.7.2 (BSD-3-Clause). GPL yok.
- **Entegrasyon:** `adapters/turkish_zemberek.py` → `ZemberekTurkishAnalyzer`, `--engine zemberek`. Tek bir yerel
  `java` alt süreci (`zemberek/ZemberekBridge.java`) stdin/stdout üzerinden çalışır, ağ bağlantısı açmaz.
  `setup_zemberek.sh` jar'ları `build/lexicon/zemberek/lib` altına indirir, sağlamasını doğrular, köprüyü derler,
  duman testi yapar. Hiçbir jar git'e girmez. Boyut 9.3 MB.
- **Python portu:** `zemberek-python` 0.2.3 (Apache-2.0) **Python 3.13'te açılmıyor** (denendi: `antlr4` 4.8,
  `typing.io` modülünü arıyor; ayrıca kaldırılan `pkg_resources`'a bağlı). Kullanılmadı.

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

## Gerçekte kullanılanlar (PR #99 ve ikinci aşama)

| Bileşen | Lisans | Zorunlu mu |
|---|---|---|
| Python standart kütüphanesi (sqlite3, re, json ...) | PSF | Evet |
| Yerleşik İngilizce ve Türkçe adaptörler | GPL-3.0 (Storilex kaynak kodu) | Evet |
| spaCy 3.8.18 + en_core_web_sm 3.8.0 | MIT + MIT | Hayır, `--engine spacy` (`setup_spacy.sh`) |
| Zemberek-NLP 0.18.0 + Guava, Caffeine, protobuf, ANTLR | Apache-2.0 + Apache-2.0 / BSD-3-Clause | Hayır, `--engine zemberek` (`setup_zemberek.sh`, Java 21) |
| `assets/dict.db`, `assets/tr_en.db` | mevcut lisansları | Yalnız salt okunur karşılaştırma |

Flutter uygulamasına hiçbir bağımlılık eklenmedi (`pubspec.yaml` değişmedi). Değerlendirmede yalnız uygulamanın
kütüphanesindeki kamu malı metinler kullanıldı: Project Gutenberg kitapları (`library/books/pg-*.md.gz`) ve
Türkçe kütüphanedeki Nasreddin Hoca ve Ömer Seyfettin metinleri (katalogda "Public domain", kaynak tr.wikisource.org).
Ayrıntılar: [eval/REPORT.md](eval/REPORT.md).
