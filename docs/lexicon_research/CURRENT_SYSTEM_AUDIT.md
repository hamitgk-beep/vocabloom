# Mevcut Storilex sözlük sistemi: denetim (Görev 5A, Aşama 1)

Tarih: 22 Kasım 2026. İncelenen kod: `main` @ `a181094` (PR #105, #107, #108, #109, #110 birleşmiş hâli).
Açık taslak PR'lar #99, #104 ve #106 kendi dallarından okundu (`claude/project-thread-hvk1xi`, `claude/lexicon-spacy`,
`claude/lexicon-integrations`). Bu belgedeki sayılar, aksi yazılmadıkça, iki sözlük dosyası **salt okunur** açılarak
tam tarama ile sayıldı:

| Dosya | Boyut | SHA-256 (bu denetimde, değişmedi) |
|---|---:|---|
| `assets/dict.db` (İngilizce→Türkçe) | 70,6 MB | `ab4a7a53b9fc5e1edbd682da5cb7193c0c109f93236655385bf6231d90221a9c` |
| `assets/tr_en.db` (Türkçe→İngilizce) | 44,1 MB | `49a661b9c8951259ab13fd6a95aa77b68e16f1c4716669dacfb6c12521cfa818` |

## 1. İngilizce–Türkçe sözlük (`assets/dict.db`, `DictDb._version = '36'`)

| Tablo | Satır | Ne tutar | Kaynak |
|---|---:|---|---|
| `ft` | 42.154 | Kelime → Türkçe anlam listesi (JSON dizi, ilk eleman "ana anlam") | Wiktionary çevirileri (kaikki üzerinden, Kindle derlemesinin Wiktionary kısmı) + damdafayton/eng-tur-dictionary |
| `syn` | 117.659 | WordNet 3.0 synset: tür, tanım, örnekler, eş anlamlılar, `tr` (KeNet Türkçesi), `extr` | Princeton WordNet 3.0 + KeNet (CILI ile bağlı) |
| `sense` | 206.941 | lemma → synset sırası (147.306 ayrı lemma, 64.188'i çok kelimeli) | WordNet 3.0 |
| `exc` | 5.952 | Düzensiz biçimler (form, lemma, tür) | WordNet `*.exc` |
| `fam`, `famg` | 31.120 / 11.874 | Kelime aileleri (word family) | `tools/word_family.py` |
| `expr` | 18.209 | İfade: deyim, phrasal verb, eşdizim … 18 kategori | Wiktionary (EN + TR), `tools/categories.py` listeleri, AI açıklamaları |
| `exd` | 2.510 | Hazır "öğretmen anlatımı" (JSON) | AI (dictionary-data iş akışı) |
| `exs` | 70.105 | İfade anahtarı → örnek cümle + Türkçesi | Tatoeba (CC BY 2.0 FR) ve AI çevirileri |
| `wfreq` | 22.491 | Kelime sıklığı | Tatoeba derleminden sayım (bkz. §7 "tom" sorunu) |
| `exfreq` | 4.164 | İfade sıklığı | aynı |
| `own_word` | 41.269 | Kendi sözlük satırları (anlam listesi JSON, `keep_tr`, `status`, `reviewed`) | **41.177'si `ai_draft_unreviewed` (reviewed=0)**, 92'si `contrib` (reviewed=1, Hamit'in katkıları) |
| `own_expr` | 10.781 | Kendi ifade satırları | **10.092 AI taslağı**, 689 katkı |
| `meta` | 2 | sürüm, katkı dosyaları listesi | — |
| `wd` | 0 | boş | — |

Kayıt yapıları:

- **Kelime anlamı (ana liste):** `ft.tr` = `["banka", "bankaya para yatırmak, nehir/göl kıyısı, sal", …]`. Bir eleman
  birden çok Türkçe karşılığı virgülle taşır; anlam ile sözcük türü arasında bağ yoktur (tür bilgisi yok).
- **WordNet anlamı:** `syn(id, pos, gloss, examples[], words[], tr[], extr)`. `tr` yalnız KeNet'in o synset için verdiği
  Türkçedir; 117.659 synset'in 14.171'inde (%12,0) Türkçe var. `extr` (örnek cümlelerin Türkçesi) bu sürümde
  **hiçbir satırda dolu değil** (32.884 örnekli synset, 0 Türkçe örnek).
- **Kendi sözlük anlamı:** `own_word.senses` = `[{pos: "isim", tr, note, en (tanım), ex, ex_tr, more[], src?}]`.
  81.196 anlamın 81.029'unda örnek var, ama bunların tamamına yakını incelenmemiş AI çıktısıdır.
- **İfade:** `expr(id, phrase, cat, tr, en, forms, ex, entr, extr)`; 7.275 ifadede (%40,0) Türkçe yok, 2.643'ünde
  hiç örnek yok. Aynı ifade 55 kez iki ayrı kategoride kayıtlı.
- **Örnek cümle:** `exs(key="phrase|cat", en, tr)`.

### Kaynak öncelik kuralı (PR #110, `DictDb.sourcePolicy = true`, `SourceTier`)
`verified` (Hamit'in katkısı, `reviewed=1`) > `trusted` (ft, WordNet, expr, exd) > `draft` (AI taslağı). Taslak
silinmez, terfi etmez; yalnız "doğrulanmamış" etiketli kapalı bölümde gösterilir (`trDraft`, `draftSenses`).
Taslak satırındaki tek bir anlam yalnız `src: storilex` **ve** `contrib_verified.dart` kaydıyla eşleşirse doğrulanmış
sayılır (`DictDb.tiered`). Bu, mimarinin en değerli parçası ve korunmalı.

## 2. Türkçe–İngilizce sözlük (`assets/tr_en.db`)

| Tablo | Satır | Ne tutar |
|---|---:|---|
| `lemma` | 55.364 | kelime, sıra (rank), `senses` JSON: `[{p: "noun", g: [İngilizce karşılıklar], s?: "fd"/"wn"/"st"}]` |
| `form` | 401.588 | çekimli biçim → lemma (5.903 biçim birden çok lemmaya gidiyor) |
| `ex` | 84.385 | Türkçe örnek + İngilizcesi (Tatoeba); 13.635 lemmada örnek var (%24,6) |
| `ctx`, `ctxn` | 81.972 / 7.265 | Tatoeba'dan bağlam sözcükleri → anlam sayıları (`meaningInContext`) |
| `meta` | 771 | kaynaklar, sayılar, 764 katkı bağlam cümlesi (`ctx:…=contrib`) |

`meta.sources` = "Kaikki.org / English Wiktionary (CC BY-SA 4.0); FrequencyWords / OpenSubtitles 2018 (CC BY-SA 4.0);
Tatoeba (CC BY 2.0 FR)". **Ancak** tam taramada 23.952 anlam `s: "fd"` (FreeDict tersinden, GPL-2.0+) ve 7.077 anlam
`s: "wn"` (WordNet tersinden) işaretli; bu iki kaynak `meta.sources` satırında yazmıyor (yalnız `meta.reverse`
sayısında geçiyor). FreeDict'ten gelen anlamların sözcük türü boş (`p: ""`, 23.952 satır). Bkz. LICENSE_MATRIX.md.

## 3. Kaynakların lisansı ve kökeni (özet; ayrıntı LICENSE_MATRIX.md)

| Kaynak | Nerede | Lisans | Durum |
|---|---|---|---|
| Wiktionary (kaikki/wiktextract) | ft, expr, tr_en.lemma | CC BY-SA 4.0 + GFDL | Uygun, atıf + share-alike |
| damdafayton/eng-tur-dictionary | ft (yardımcı anlamlar) | README "MIT" diyor ama `MIT.md` bağlantısı **404**, lisans dosyası yok, veri kökeni yazılmamış | **Belirsiz**; Ayarlar'da "(MIT)" yazıyor |
| Kindle EN–TR derlemesi (mybottles) | ft'nin Wiktionary kısmı buradan alınmış | README: içerik **GPL v2.0+** (FreeDict'ten miras) | Ayırma iddiası doğrulanmalı |
| FreeDict eng-tur 0.3 | expr yedeği, tr_en "fd" anlamları | GPL-2.0-or-later | CC BY-SA veritabanı içinde GPL içerik: belirsiz |
| Princeton WordNet 3.0 | syn, sense, exc | WordNet License (izin verici, atıf) | Uygun |
| KeNet | syn.tr | veri CC BY-SA 4.0 (kod GPL-3.0) | Uygun |
| CILI | eşleme | CC BY 4.0 | Uygun |
| Tatoeba | exs, tr_en.ex, ctx, wfreq | CC BY 2.0 FR (cümle bazında farklı olabilir) | Uygun, cümle lisansı ayrıca izlenmeli |
| AI açıklamaları/taslakları | own_word, own_expr, exd, exs.tr kısmen | Servis şartları; insan incelemesi yok | Kalite riski (lisans değil) |

## 4. SenseEngine (bağlama göre anlam seçimi, `lib/nlp/context_sense.dart`, sürüm `'2'`)

- Girdi: cümle, belirteçler, dokunulan kelime veya eşleşen ifade. Önbellek anahtarı: içerik + cümle özeti + konum +
  sözlük sürümü + motor sürümü + `policyVersion` + arayüz dili.
- Adaylar: WordNet synset'leri (`wn:`), kendi sözlük anlamları (`od:`/`ow:`), ana liste (`ft:`), ifade anlamları (`ex:`).
  AI taslağı aday olarak yarışır ama `unverified = true` taşır.
- Puan: anlamsal örtüşme 0,40 + sözcük türü 0,18 + kalıp 0,18 + örnek 0,12 + sıklık 0,12 (`SenseWeights`).
- Güven: `sure` / `likely` / `none`. `sure` için cümlenin bu anlamı rakiplerinden ayırması (fark ≥ 0,08) veya ana
  anlam olması, yakın aday itirazı olmaması ve **taslak tek başına ise kontrollü bir kaynağın aynı Türkçeyi vermesi**
  gerekir. Puan < 0,3 → `none`.
- İfadeler: ayrık phrasal verb ("turn the light off") ayrıca aranır; `isLiteral` ile "lived in Kansas" gibi düz kullanım
  ayrılır. İfade yalnız `sure` ise tekrar kartında onaylanır (MAGPIE ölçümüne dayanan kural).
- `fit()`: tekrar kartlarının tek güven kuralı. Cevap; seçilen anlamın Türkçesiyle aynı, KeNet eşanlamlısı veya ortak
  çeviri ise `confirmed`.

## 5. Cümle analizi, kök bulma, dilbilgisi

- Belirteç/cümle bölme: `lib/nlp/text.dart` (`tokenize`, `sentenceRanges`, kısaltma kuralları; #105).
- İngilizce kök: `DictDb.baseForms` (düzensiz liste + ek kuralları + türe göre izin; "-ly" ayrı kelime), `Lemmatizer`
  (ifade bulmak için geniş liste).
- Türkçe kök: `TrEnDict.lemmas` (tablo + `_endings` + fiil eki kesme → "-mak/-mek").
- Dilbilgisi: `lib/nlp/grammar.dart` (zaman), `lib/nlp/grammar_marks.dart` (3.306 satır kural: koşul, edilgen,
  reported speech …). Kurallı, çevrimdışı; şüphelide işaretlemez.
- PR #104 (açık): geliştirici aracı olarak spaCy 3.8.18 + en_core_web_sm (MIT) ve Zemberek 0.18.0 (Apache-2.0);
  uygulamaya girmiyor. PR #106 (açık): wordfreq 3.1.1 Zipf, `paraphrase-multilingual-MiniLM-L12-v2` ONNX (Apache-2.0)
  ile aday cümlelere `sense_hint`. PR #99 (açık): ayrı `candidates.db`, salt okunur karşılaştırma, kaynak onayı
  (`source_approval`), yalnız eklenebilir günlükler.

## 6. Veri akışı: sözlük → okuyucu → tekrar kartları

```
kitap metni ─ tokenize/sentenceRanges ─► PhraseMatcher (expr) ─► altı çizili ifadeler (filtreler)
     │
     └─ dokunma ─► baseForms/headword ─► DictDb.lookup (own verified > keep_tr > ft ; draft → trDraft)
                                     └─► SenseEngine.resolve ─► "bu cümlede büyük olasılıkla …" kartı
                                                               └─► kaydet (yalnız sure ise anlamla) ─► user_db
tekrar kartı ─► ReviewQuiz ─► SenseEngine.fit(lemma, cümle, cevap) ─► yalnız confirmed ise notlanır
```
Kullanıcı verisi (`user_db`: kelimeler, ilerleme, kartlar, geri bildirim) sözlük dosyasından ayrıdır. Sözlük
sürümü değişince önbellek anahtarları değişir; kayıtlı kartın anlamı saklanır (#110).

## 7. Mevcut testler, güvenlik kuralları ve bilinen hatalar

- Testler (`test/`, 70+ dosya): `context_sense_test`, `sense_eval_test` (SemCor, KeNet Türkçesiyle; sabit tohum,
  dev/fresh ayrımı), `text_eval_test` (GUM; depoya girmiyor), `source_priority_test`, `grammar_marks_test`,
  `phrase_*`, `tr_en_dict_test`, `own_dictionary_test` … CI'da `quality.yml` → `tools/qa/audit_dict.py` taban çizgisini
  aşan "hata" sayısında başarısız olur.
- Güvenlik kuralları: taslak asla "kesin" değildir; ifade yalnız `sure` ise karta girer; önbellek sözlük sürümüne
  bağlı; ana sözlük salt okunur açılır.
- Bilinen hatalar (QA raporu + bu denetim):
  - ft'de etiket/kısaltma karışmış 1.638 karşılık, bozuk yapışık etiket 8 (`DictDb.badMeaning`), İngilizce karışan
    195 karşılık (`tools/qa` raporu).
  - ft'de Türkçe sözlükte bulunmayan belirteç %6,7 (11.314/169.383); okunan 80 örnekten yaklaşık 20'si bozuk,
    yazım hatalı veya çok eski öztürkçe (ör. "çivermek", "mahsül", "sakçısı", "are → siniz"). Sınıflandırmayı Claude
    yaptı.
  - `wfreq` Tatoeba'dan sayıldığı için en sık 200 kelimede "tom" (1.) ve "mary" var.
  - 41.177 kelimenin kendi sözlük satırı incelenmemiş AI taslağı; ft ile ilk anlamları 19.189 kelimede hiçbir ortak
    kelime paylaşmıyor (QUALITY_BENCHMARK.md §3).

## 8. Yeni kaynak eklerken korunması gereken yapılar

1. `assets/dict.db` ve `assets/tr_en.db` şeması ve satırları (CLAUDE.md §4). Yeni veri **ayrı** tablo/dosyada başlar.
2. `own_word`/`own_expr` alanları `status`, `reviewed`, `src`, `keep_tr` ve `contrib_verified.dart` eşleşmesi.
3. `SourceTier` sırası ve `sourcePolicy`; `policyVersion` + `DictDb.version` önbellek anahtarındaki yeri.
4. Kimlik biçimleri: `wn:<syn.id>`, `ex:<phrase>|<cat>#i`, `od:/ow:<word>#i`, `ft:<word>#i` (geri bildirim ve
   kartlar bunları saklıyor).
5. `SenseEngine.fit` tek güven kuralı; tekrar kartları ona bağlı.
6. PR #99'un `candidates.db` + `source_approval` + yalnız eklenebilir günlük modeli (aday katmanının temeli).
7. Kullanıcı verisi (`user_db`), okuma ilerlemesi ve ayarlar: hiçbir sözlük işi bunlara yazmaz.
