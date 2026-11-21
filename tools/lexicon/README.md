# Sözlük aday altyapısı (`tools/lexicon`)

Kitaplardan ve izinli kaynaklardan **kelime, anlam, phrasal verb, deyim ve örnek cümle adayları** çıkaran,
bunları mevcut iki sözlükle **salt okunur** karşılaştıran ve ayrı bir aday veritabanında saklayan geliştirici
aracı. Uygulamanın bir parçası değildir: Flutter kodu, `assets/` ve kullanıcı verisi değişmez, çevrimdışı
çalışma etkilenmez.

Lisans değerlendirmesi: [LICENSE_REPORT.md](LICENSE_REPORT.md).

## Güvenlik kuralları (kodla zorlanır)

| Kural | Nerede |
|---|---|
| `assets/dict.db` ve `assets/tr_en.db` yalnız `mode=ro` + `query_only` ile açılır, yazma denemesi hata verir | `safety.open_readonly` |
| Aday veritabanı ve dışa aktarım `assets/` içine ya da `dict.db`/`tr_en.db` adlı bir dosyaya yazılamaz | `safety.check_writable_target` |
| Yazılan lisans (`--licence MIT`) yalnızca bir beyandır, kaynağı paylaşılabilir yapmaz | `licenses.classify` |
| Paylaşım için isimli bir kişinin kanıtla (lisans adresi veya not) kaydettiği ayrı bir onay gerekir. Onay geri alınabilir. İkisi de silinemeyen `source_approval` kaydına yazılır | `store.approve_source` / `revoke_source` |
| Yalnız izin verici lisans sınıfı onaylanabilir. Kullanıcı kitabı, CC BY-SA, GPL, NC ve belirsiz lisanslar bu araçla onaylanamaz | Python + `approval_insert_check` |
| `source` satırları (licence, kind, lang, lisans sınıfı) değiştirilemez ve silinemez. İzin ve kapsam saklanmaz, onay kaydından türetilir, bu yüzden SQL ile "allowed" yazılacak bir sütun yoktur | `source_no_update` / `source_no_delete`, `source_status` görünümü |
| Elle (SQL ile) eklenen `source` satırında lisans sınıfı lisansla ve türle uyuşmak zorunda | `source_insert_check` |
| Adayın lisans kopyası kaynağınkine eşit olmak zorunda. Adayın kaynağı, lisansı, yönü, türü ve başlığı sonradan değiştirilemez | `candidate_insert_check` / `candidate_identity_fixed` |
| Her aday `unverified` başlar. Boru hattı `accepted`/`rejected` koyamaz. Kabul isimli bir gözden geçiren ister, şema da bunu zorlar | `store.add_candidate`, `CHECK` |
| `review_log` ve `source_approval` yalnız eklenebilir | tetikleyiciler |
| Koruyucu tetikleyicilerden biri silinmiş ya da değiştirilmişse dışa aktarım çalışmaz. Ayrıca bütün kurallar Python'da yeniden denetlenir | `store.verify_integrity`, `store.exportable` |
| Kaynak dili, yön, sözlük ve analiz motoru uyuşmazsa hiçbir aday yazılmadan reddedilir | `extract.check_route` (extract, add-sense), `add_candidate`, tetikleyici |

Not: Yerel bir SQLite dosyasını elinde tutan biri tetikleyicileri silebilir. Bu yüzden dışa aktarım önce
tetikleyicileri denetler, sonra kuralları Python'da yeniden uygular. SQL ile eklenen bir onay da (kuralları
geçiyorsa) kayıtta adıyla görünür.

## Güven sınırı: bu araç neyi garanti etmez

- **Bir onay, lisansın doğrulandığı anlamına gelmez.** `source_approval` yalnızca "şu kişi, şu kanıtla bu kaynağı
  kontrol ettiğini söyledi" bilgisini kaydeder. Araç lisansı kendisi doğrulamaz, internete de bakmaz. Doğruluk,
  onayı veren kişinin incelemesine bağlıdır.
- **"Public domain" eser, ülke, baskı ve çeviri düzeyinde ayrı ayrı değerlendirilmelidir.** Bir eser ABD'de kamu
  malı olup Türkiye'de ya da AB'de olmayabilir (ölüm + 70 yıl kuralı). Yeni bir baskının editör notları, modern bir
  çeviri veya düzenlenmiş metin ayrıca korunuyor olabilir. Onay verirken eserin hangi baskısının kullanıldığı
  kanıt metnine yazılmalıdır.
- **Örnek cümlelerin yeniden dağıtımı ayrıca kontrol edilmelidir.** Bir kaynağın okunabilir olması, cümlelerinin
  sözlükte örnek olarak dağıtılabileceği anlamına gelmez. Atıf gerektiren lisanslarda (CC BY) atıf, dağıtılan
  veriyle birlikte taşınmalıdır.
- **Mevcut sözlüğün lisansı değişmez.** `assets/dict.db` CC BY-SA 4.0 kaynaklardan uyarlandığı için CC BY-SA 4.0
  ile paylaşılır (ana README). Bu araçla üretilen veriye, kaynağı ne olursa olsun, otomatik olarak "telifsiz"
  muamelesi yapılmaz. Bir aday sözlüğe girecekse, dağıtım öncesinde hem kaynağın lisansı hem de sözlüğün CC BY-SA
  lisansıyla uyumu ayrıca kontrol edilmelidir.
- **Bu bir güvenlik sınırı değildir.** Tetikleyiciler ve dışa aktarım denetimleri, geliştirici iş akışındaki
  hataları ve kazaları azaltmak içindir. Dosyaya yazabilen biri her şeyi değiştirebilir. Araç ağ bağlantısı kurmaz,
  dışa aktarım yalnız verilen yerel dosyaya yazar.

## İzin modeli

| `licence_class` (kaynakta, sabit) | Onay | `permission` (türetilir) | `scope` |
|---|---|---|---|
| `permissive` | yok ya da geri alındı | `pending_verification` | private |
| `permissive` | `approve` | `allowed` | shared |
| `needs_approval` (SA, GPL, NC) | onaylanamaz | `needs_approval` | private |
| `unknown` | onaylanamaz | `unknown` | private |
| `private_only` (kullanıcı kitabı) | onaylanamaz | `private_only` | private |

Dışa aktarılanlar: `accepted` durumunda, `permission = allowed` olan ve Python denetimini geçen adaylar.

## Veri yapısı (`build/lexicon/candidates.db`, git'e girmez)

**source** (değiştirilemez): `name`, `kind` (`public_domain_text`, `open_license_text`, `user_book`, `manual`),
`licence` (beyan edilen, normalleştirilmiş), `licence_class`, `licence_url`, `licence_note`, `lang` (`en`/`tr`).

**source_approval** (yalnız eklenir): `source_id`, `decision` (`approve`/`revoke`), `approver`, `evidence`, `at`.

**source_status** (görünüm): kaynak bilgisi, son karar ve türetilmiş `permission`.

**candidate**: tek bir aday
- `kind`: `word`, `sense`, `phrasal_verb`, `idiom`, `collocation`, `example`
- `direction`: `en-tr` (dict.db için) veya `tr-en` (tr_en.db için). Kaynak diliyle uyuşmak zorunda.
- `headword`, `lemma`, `pos`, `translation`, `definition`, `example`, `example_translation`
- kaynak bilgisi: `source_id`, `locator` (dosya#cümle), `licence` (kaynağın lisansının değişmez kopyası)
- `engine` (ör. `builtin-en@1`), `confidence` (0–1)
- `compare_result`: `new_headword`, `known_headword`, `known_form`, `known_sense`, `possible_new_sense`,
  `new_phrase`, `known_phrase`. `compare_detail` JSON olarak bulunan lemmayı ve cümle uyarılarını (`sentence_flags`) tutar.
- `status`: `unverified` → `needs_review` → `accepted` / `rejected`. Yanında `reviewer` ve `review_note`.
- `occurrences`: aynı adayın aynı kaynakta kaç kez görüldüğü

**candidate_status** (görünüm): aday, kaynağın güncel `permission` değeri ve türetilmiş `scope`.

**review_log** (yalnız eklenir): her durum değişikliği (eski, yeni, kim, not, zaman).

## Adaptörler

İngilizce ve Türkçe adaptörler birbirinden bağımsızdır. Her dilin kendi temel sınıfı vardır, biri diğerini içe aktarmaz.

| Dil | Adaptör | Bağımlılık | Not |
|---|---|---|---|
| İngilizce | `builtin` | yok | Düzensiz biçimler `dict.db/exc` tablosundan önce aranır ("sat" → "sit"), ekler kurallarla çözülüp sözlükte denetlenir (karşılaştırma ve üstünlük ekleri, ön ek + bilinen kelime dahil). Phrasal verb yalnız fiil + edat cümle sonundaysa ya da zaten biliniyorsa bulunur |
| İngilizce | `spacy` | spaCy 3.8.18 + en_core_web_sm 3.8.0 (MIT) | Ayrık phrasal verb'leri de bulur ("took it off"). Özel adları etiket ve varlık tanımayla ayırır. Lemmayı sözlükle doğrular, yanlışsa yerleşik kurallara düşer. Tireli birleşikleri tek kelime tutar. Fiil + nesne eşdizim kanıtı toplar |
| Türkçe | `builtin` | yok | Çekimli biçim `tr_en.db/form` ile lemmaya indirilir. Kesme işaretli sözcükler ve cümlenin ilk sözcüğünden sonra büyük harfle başlayan sözcükler özel ad sayılır |
| Türkçe | `zemberek` (deneysel) | Zemberek-NLP 0.18.0 (Apache-2.0), Java 21 | Biçimbirim çözümlemesi ve belirsizlik giderme ile kök bulur. Yerel bir `java` alt sürecinde çalışır, ağ kullanmaz. Zemberek'in kendi kelime listesi aday olarak kopyalanmaz |

Kurulum tek komut, elle bir şey kurmak gerekmez. İkisi de yalnız `build/lexicon/` altına yazar, uygulamaya
bağımlılık eklemez:

```bash
bash tools/lexicon/setup_spacy.sh      # build/lexicon/venv: sabit sürümler (requirements-spacy.txt + constraints-spacy.txt)
bash tools/lexicon/setup_zemberek.sh   # build/lexicon/zemberek: SHA-256 ile sabitlenmiş jar'lar (zemberek/jars.lock)
```

### İsteğe bağlı yardımcı sinyaller

| Bileşen | Lisans | Ne yapar | Kurulum |
|---|---|---|---|
| `senses.py` (bağlama uygun anlam) | Storilex (GPL-3.0) | `own_word`'deki anlamlar arasından cümleye uyanı önerir. Anlamın örnekleri ve Türkçesi üzerinden bağlı WordNet tanımlarıyla kelime örtüşmesine, kelime türüne ve anlam sırasına bakar | Gerekmez |
| `embeddings.py` | Model Apache-2.0; onnxruntime MIT, tokenizers Apache-2.0 | Sentence Transformers modeli `paraphrase-multilingual-MiniLM-L12-v2` ile İngilizce cümleyi anlamın Türkçe karşılığı ve WordNet tanımıyla karşılaştırır. PyTorch gerekmez (ONNX, 118 MB) | `bash tools/lexicon/setup_embeddings.sh` (SHA-256: `embeddings.lock`) |
| `frequency.py` | wordfreq kodu Apache-2.0, verisi CC BY-SA 4.0 | Kelime adayına Zipf sıklığı ekler. Lemma bilinmiyor ama yazılı biçim yaygınsa (`unaccounted` → `unaccount`) `lemma_suspect` işaretler ve güveni 0.1'e indirir | `bash tools/lexicon/setup_spacy.sh --with-wordfreq` |

Üçü de yalnız aday veritabanına **inceleme bilgisi** yazar (`compare_detail` içinde `sense_hint`, `zipf`,
`lemma_suspect`). Çeviri alanını doldurmaz, adayı kabul etmez, sözlüğe bir şey aktarmaz. Model ve sıklık listeleri
git'e ve uygulamaya girmez.

## Aday türleri ve filtreler (extract)

| Tür | Ne zaman yazılır | Güven |
|---|---|---|
| `word` | Lemma sözlükte yoksa | 0.4 (lemma bulundu), 0.2 (bulunamadı); bilinen parçalardan tireli birleşik, düşmüş harfli lehçe yazımı ("kep'"), ünlem ve yalnız cümle başında görülen kelime 0.1 |
| `phrasal_verb` | Sözlükte olmayan fiil + edat | 0.3–0.6 |
| `collocation` | spaCy fiil + nesne çifti, metinde en az 2 kez ve sözlükte yok ("make decision" → "make a decision" de denenir) | 0.2–0.5 |
| `sense` | Bilinen bir kelime, sözlüğün listelemediği türde (isim ↔ fiil) en az 3 kez ve kullanımlarının en az %20'sinde | 0.2 |
| `example` | Bilinen kelime ya da bilinen deyim / phrasal verb için kaynak başına bir cümle. Deyimler çekimli hâlleriyle de bulunur ("broke the ice" → "break the ice", "pulled my leg" → "pull someone's leg"). Birden çok anlamı olan İngilizce kelimelerde `sense_hint` hangi Türkçe anlamın uyduğunu **önerir** (güven 0.3–0.5) | 0.3 |

Özel adlar belge düzeyinde de aranır: bir kelime metnin bir yerinde cümle içinde büyük harfle yazılıp hiç küçük
harfle geçmiyorsa, cümle başındaki kullanımları da ad sayılır ("Dinah was ..."). Kısaltmalar ("etc.") aday olmaz.
Şüpheli cümlelerden gelen adayların güveni 0.1 düşer. Çeviri hiçbir zaman otomatik üretilmez.

## Kullanım (depo kökünden)

```bash
python3 tools/lexicon/run.py add-source --name gutenberg-11 --kind public_domain_text --licence "Public domain" --lang en
python3 tools/lexicon/run.py approve-source --source gutenberg-11 --approver Hamit --evidence "https://www.gutenberg.org/ebooks/11"
python3 tools/lexicon/run.py add-source --name benim-kitabim --kind user_book --lang en      # her zaman özel
python3 tools/lexicon/run.py extract --source gutenberg-11 --text alice.txt                 # --engine spacy
python3 tools/lexicon/run.py add-source --name elle --kind manual --licence Storilex --lang en
python3 tools/lexicon/run.py add-sense --source elle --headword run --translation "işletmek" --pos verb
python3 tools/lexicon/run.py summary
python3 tools/lexicon/run.py gaps --out build/lexicon/gaps.md                            # eksik kelime/anlam raporu
python3 tools/lexicon/run.py review --id 12 --status accepted --reviewer Hamit
python3 tools/lexicon/run.py export --out build/lexicon/reviewed.jsonl
```

spaCy ile: `build/lexicon/venv/bin/python tools/lexicon/run.py extract ... --engine spacy`. Türkçe kaynakta
`--engine zemberek`. Yanlış dil için motor seçilirse komut aday yazmadan durur. `--wordfreq` Zipf sıklığını,
`--embeddings` anlam önerisinde cümle gömmelerini açar.

`gaps`, aday veritabanındaki eksikleri (yeni kelime, olası yeni anlam, yeni phrasal verb / deyim / eşdizim) kaynaklar
arasında birleştirip `.md` ve `.tsv` olarak yazar. En çok kaynakta görülenler başa gelir. Reddedilenler hariçtir.
Kullanıcı kitabından gelen örnek cümleler rapora hiç yazılmaz, yalnız sayıları görünür.

`add-sense` mevcut bir kelimeye **yeni anlam adayı** ekler. Anlam sözlükte varsa karşılaştırma `known_sense`,
yoksa `possible_new_sense` yazar. Çeviriler otomatik üretilmez. Yön her zaman kaynağın dilinden çıkarılır.

## Testler ve değerlendirme

```bash
python3 -m unittest discover -s tools/lexicon/tests -t tools                       # standart kütüphane
build/lexicon/venv/bin/python -m unittest discover -s tools/lexicon/tests -t tools # spaCy testleriyle
build/lexicon/venv/bin/python tools/lexicon/eval/evaluate.py                      # başarı oranları
build/lexicon/venv/bin/python tools/lexicon/eval/evaluate.py --lang tr            # Türkçe (Zemberek)
build/lexicon/venv/bin/python tools/lexicon/eval/evaluate_senses.py --embeddings  # bağlama uygun anlam
```

Testler küçük, sentetik `dict.db`/`tr_en.db` kopyalarıyla çalışır. `RealAssetsTests` gerçek dosyalar varsa onları
salt okunur açar ve SHA-256 değerinin ve değişiklik zamanının aynı kaldığını denetler. spaCy ya da Zemberek kurulu
değilse onların testleri atlanır. `SharingGuardTests` sahte kaynak, SQL ile alan değiştirme, silinen tetikleyici gibi
saldırgan girdileri dener. `EvaluationThresholdTests`, etiketli 30 cümlede ölçülen kalitenin (kök doğruluğu, özel ad
sızıntısı, phrasal verb kesinliği) ve 20 Türkçe cümlede Zemberek sonuçlarının belirlenen eşiklerin altına
düşmediğini denetler. `SenseEvaluationThresholdTests` aynısını 99 cümlelik anlam kümesi için yapar. CI'daki
`lexicon-tools` iş akışı testleri hem yalnız standart kütüphaneyle hem de bütün motorlar kurulu olarak çalıştırır.

Ölçüm yöntemi ve sonuçlar: [eval/REPORT.md](eval/REPORT.md). Kitap düzeyinde çalıştırma: `eval/corpus.py`.

## Bilinen sınırlar

- Cümle ayırıcı basittir. Kısaltmaları ("Mr.", "Dr.", "vb."), baş harfleri ("J. K."), ondalık sayıları ve Türkçe
  büyük harfleri tanır. Bilinen iki sınırı var:
  - "– Ver elini! Ver elini! diye seslenmişler." gibi konuşmalar ikiye bölünür.
  - Cümle sonundaki bir kısaltma ("etc.") iki cümleyi birleştirir.

  Böyle parçalar `sentence_flags` ile işaretlenir (`short`, `speech_inside`, `abbreviation`, `starts_lowercase`,
  `unbalanced_quotes`, `no_final_punctuation`). Bu parçalardan çıkan adaylar düşük güvenle kaydedilir.
- Yerleşik İngilizce adaptör cümle başındaki özel adları (ör. "Dinah") yeni kelime sanabilir. Belge düzeyindeki ad
  kanıtı ve spaCy bunların çoğunu ayırır, kalanlar 0.1 güvenle `possible_name` işaretiyle yazılır.
- spaCy, sözlükte olmayan kelimelerin kökünü bazen yanlış kurar ("covies" → "covie"). Lehçe yazımları (Tom Sawyer,
  Treasure Island) sözlükte olmadığı için aday olur. Bunları ayıklamak gözden geçirenin işidir.
- Eşdizim ve olası yeni anlam adayları gürültülüdür (bkz. rapor). Yeni anlamlar için asıl yol `add-sense`.
- Yerleşik Türkçe adaptör `tr_en.db`'de olmayan çekimli biçimleri lemmaya indiremez. Bunlar `lemma` boş ve düşük
  güvenle (`0.2`) kaydedilir. Zemberek bu adayların çoğunu köke indirir.
- Zemberek cümle başındaki özel adları bazen sıradan kelime olarak çözer ("Ali" → "ali", sıfat).
- Anlam önerisi 99 etiketli cümlede %64 doğru (ilk anlamı seçmek %38). Yani her üç öneriden biri yanlış: yalnız
  gözden geçirene yardımcı bir ipucudur.
- Yeni deyim çıkarımı yok. Sözlükte kayıtlı deyimler metinde bulunup örnek cümle adayı olur. Yeni deyim ve eşdizim
  adayları elle `add-sense --kind idiom` ile eklenir.
