# Kayıt düzeyinde kaynak izlenebilirliği (Görev 5C, Aşama 3 ve 5)

Amaç: her kelime, anlam, çeviri, deyim ve örnek cümle için "nereden geldi, hangi lisansla, kim değiştirdi, kim
doğruladı" sorusunu yanıtlamak. **Uygulamanın veritabanı şeması değişmedi.** İzlenebilirlik bilgisi bugün
sözlük dosyalarının dışında, `tools/lexicon_provenance/` araçlarının ürettiği kayıtlarda (JSON Lines) tutulur.
İleride yeni bir sözlük sürümü derlenirken aynı alanlar derleme sırasında yazılmalı (bkz. REMEDIATION_PLAN.md).

## 1. İki katman

1. **Kaynak kayıt defteri** — `tools/lexicon_provenance/registry.json`. Her kaynak bir kez tanımlanır: adı, sürümü,
   URL'si, lisansı, lisans kanıtı, veri kökeni, ticari kullanım ve yeniden dağıtım durumu, zorunlu atıf metni,
   soy ağacı (`derived_from`) ve doğrulama değeri (`evidence_value`). Lisanslar da burada tanımlanır
   (atıf, share-alike, copyleft, NC, ND ve paket lisansına uyum).
2. **Kayıt** — her içerik parçası için bir JSON satırı. Kaynağın ayrıntısı kayıt defterinden gelir; kayıt yalnız
   hangi kaynağa, hangi kaynak kaydına ve hangi yöntemle bağlandığını taşır.

## 2. Kayıt alanları

| Alan | Zorunlu | Anlamı | Örnek |
|---|---|---|---|
| `id` | evet | Kararlı kayıt kimliği: `<db>/<tablo>/<anahtar>#<sıra>:<alan>` | `dict.db/ft/bank#0.1:tr` |
| `db`, `table`, `key`, `field` | evet | Kaydın sözlükteki yeri | `dict.db`, `ft`, `bank`, `tr` |
| `kind` | evet | `translation`, `definition`, `sense`, `expression`, `example`, `explanation`, `frequency`, `inflection`, `word_family`, `statistic` | |
| `count` | hayır (1) | Toplu kayıtlarda (bütün bir tablo) temsil edilen satır sayısı | `206941` |
| `sources[]` | evet | Kaynak bağları (aşağıda) | |
| `transforms[]` | hayır | Dönüştürme / birleştirme geçmişi, sırasıyla | `["main_meanings.extract", "main_meanings.merged"]` |
| `ai` | evet | Yapay zekâ katkısı: `none`, `assisted`, `generated`, `unknown` | `generated` |
| `human_verified` | evet | `true` (bir insan kontrol etti), `false` (kontrol edilmedi), `null` (bilinmiyor) | |
| `evidence[]` | hayır | Doğruluğu destekleyen başka kaynak kimlikleri (köken değil, kanıt) | `["kenet"]` |
| `claimed_status` | hayır | Kayda dışarıdan yazılmış bir onay durumu; kapı bunu doğrular | `approved` |
| `notes[]` | hayır | Açıklama; `conflict:` ile başlayanlar çakışma raporuna girer | |

**Kapı çıktısı (kayda yazılmaz, raporda üretilir):** `status` (`approved` / `needs_review` / `unknown` / `blocked`),
`findings[]` (kural kodları), `licenses[]`, zorunlu atıf metinleri (kayıt defterindeki kaynaktan).

### Kaynak bağı (`sources[]` öğesi)

| Alan | Anlamı |
|---|---|
| `id` | Kayıt defterindeki kaynak kimliği; bilinmiyorsa `unknown` |
| `role` | `origin` (içerik buradan geldi; lisans buna göre) veya `support` (yalnız sıralama/eşleme etkisi; lisans yükü yok sayılmaz, raporlanır) |
| `origin_record` | Kaynaktaki karşılık: `kindle-en-tr:bank`, `pwn30:02787772-n`, `tatoeba:403982` |
| `method` | `derivation` (derleme yeniden üretildi), `rebuild_match` (ham girdilerle yeniden çalıştırma), `input_match` (bilinen girdi dosyasıyla birebir), `build_rule` (tabloyu yalnız bu kaynak yazar), `declared` (satırın kendi beyanı) |
| `confidence` | `exact`, `inferred`, `unknown` |
| `license_id` | Kayıt başına lisans (Tatoeba gibi cümle başına lisanslı kaynaklar için) |
| `candidates[]` | Kaynak bilinmiyorsa olası kaynaklar; **bilgi amaçlı, karar için kullanılmaz** |

### Kurallar
- Kaynağı bilinmeyen kayıt `{"id": "unknown", "confidence": "unknown"}` taşır; kaynak uydurulmaz. Eski kayıtların
  varsayılanı budur.
- Benzer metin köken kanıtı değildir. `inventory.py` yalnız derleme kodunu yeniden çalıştırarak veya derlemenin bilinen
  girdi dosyasıyla birebir eşleşerek bağ kurar; ham girdi bugün yeniden indirildiyse güven `inferred` olur ve kapı
  bunu `needs_review` sayar.

## 3. Kaynak kayıt defteri alanları

| Alan | Değerler |
|---|---|
| `kind` | `primary` (asıl kaynak), `extraction` (mekanik çıkarım: kaikki, DBnary), `compilation` (üçüncü kişinin seçkisi: Kindle), `internal` (Storilex), `ai` |
| `derived_from[]` | Bu kaynağın üretildiği kaynaklar (soy ağacı) |
| `version`, `version_note` | Derlemede kullanılan sürüm. Boşsa kapı `source_version_missing` der |
| `license_ids[]`, `license_choice` | Kaynağın lisansları ve Storilex'in seçtiği (ikili lisanslarda) |
| `license_status` | `verified`, `owner_declared`, `inherited`, `claimed_unverified`, `conflicting`, `missing`, `unknown` |
| `license_evidence` | Kanıtın kendisi: dosya adı, tarih, kısa alıntı |
| `data_origin` | `known` / `unknown` |
| `commercial_use` | `yes`, `no`, `unverified` |
| `redistribution` | `allowed`, `conditional`, `forbidden`, `evaluation_only`, `research_only`, `unverified` |
| `attribution` | Gösterilmesi zorunlu atıf metni |
| `per_record_license` | `true` ise her kaydın kendi `license_id`'si olmalı |
| `ai` | Kaynağın kendisi AI çıktısıysa `generated`/`assisted` |
| `evidence_value` | `independent`, `derived`, `none` |
| `human_review` | Kaynak insan tarafından kontrol ediliyorsa `true` |

## 4. Kaynak soy ağacı ve bağımsızlık (Aşama 5)

Köken (içerik nereden geldi) ile doğruluk kanıtı (başka biri aynı şeyi söylüyor mu) ayrı tutulur.

```
wiktionary_en ──► kaikki_en ──► kindle_en_tr_wiktionary_part
      │
      └──────────► kaikki (EN+TR ifadeler) ◄── wiktionary_tr
                   dbnary ◄── wiktionary_en, wiktionary_tr
babelnet ◄── wiktionary_en, princeton_wordnet
opensubtitles ──► frequencywords
princeton_wordnet, wiktionary_en ──► ai_pretranslate ──► own_dict_ai
damdafayton (kökeni bilinmiyor)   freedict_eng_tur   kenet   cili   tatoeba   storilex_contrib
```

- `independent_count()` aynı köke inen kaynakları **bir** sayar: Wiktionary + kaikki + DBnary = 1;
  Kindle-Wiktionary + kaikki = 1.
- `evidence_value: none` olan kaynaklar (AI çıktıları, Claude ile yazılmış listeler) hiç sayılmaz: sözlükten
  üretilmiş bir AI taslağı sözlüğü doğrulamaz.
- Bir kayıt `evidence[]` ile "üç kaynak doğruluyor" derse ve kökler çakışıyorsa kapı `evidence_not_independent`
  (needs_review) üretir.
- damdafayton'un kökeni bilinmediği için başka bir kaynakla bağımsızlığı **kanıtlanamaz**; kayıt defterinde ayrı kök
  görünür ama `data_origin: unknown` olduğu için zaten onaylanamaz. Kökeni öğrenilirse `derived_from` eklenmeli.

## 5. SenseEngine ve kaynak öncelik kuralıyla ilişki

Bu tasarım çalışma anındaki davranışı **değiştirmez**. `lib/data/dict_db.dart` içindeki `SourceTier { verified,
trusted, draft }` ve `DictDb.policyVersion` aynen kalır. Eşleme:

| Çalışma anı katmanı (PR #110) | Provenance karşılığı | Yayın kapısı |
|---|---|---|
| `verified` (katkı, `reviewed=1`, `contrib_verified.dart` eşleşmesi) | `storilex_contrib`, `human_verified: true` | approved olabilir |
| `trusted` (ft, WordNet, expr, exd) | Kaynağa göre: WordNet approved; ft içinde damdafayton **blocked**, Kindle-Wiktionary needs_review; exd AI | Kaynak katmanı "trusted" diye lisansı onaylı sayılmaz |
| `draft` (AI taslağı) | `own_dict_ai`, `ai: generated`, `human_verified: false` | needs_review / unknown |

Kurallar SenseEngine'in güven kurallarıyla çelişmez: SenseEngine "taslak tek başına `sure` olamaz" der; provenance
da AI kaydını bağımsız kanıt saymaz. Fark şu: `trusted` bir kalite katmanıdır, lisans onayı değildir. İleride
`trusted` içinde lisansı engelli kayıtlar ayrı bir katmana alınırsa (REMEDIATION_PLAN.md, adım 4) `policyVersion`
artırılmalı ki önbellek yenilensin.

## 6. Kayıt örnekleri

```json
{"id":"dict.db/ft/bank#0.0:tr","db":"dict.db","table":"ft","key":"bank","field":"tr","kind":"translation","count":1,
 "sources":[{"id":"kindle_en_tr_wiktionary_part","role":"origin","origin_record":"kindle-en-tr:bank","method":"derivation","confidence":"exact"},
            {"id":"damdafayton","role":"support","origin_record":"damdafayton:English.english=bank","method":"derivation","confidence":"exact"}],
 "transforms":["main_meanings.extract","main_meanings.merged"],"ai":"none","human_verified":null,"notes":["primary meaning"]}

{"id":"dict.db/syn/4512#bilgisayar:tr","db":"dict.db","table":"syn","key":"4512","field":"tr","kind":"translation",
 "sources":[{"id":"kenet","role":"origin","origin_record":"kenet:pwn30=03082979-n","method":"rebuild_match","confidence":"inferred"},
            {"id":"cili","role":"support","origin_record":"cili:pwn30=03082979-n"}],"ai":"none","human_verified":null}

{"id":"dict.db/own_word/we#1:sense","db":"dict.db","table":"own_word","key":"we","field":"sense","kind":"sense",
 "sources":[{"id":"own_dict_ai","role":"origin","origin_record":"own_word:we#1","method":"declared","confidence":"exact"}],
 "ai":"generated","human_verified":false}
```
(Örneklerdeki synset numarası temsilidir.)
