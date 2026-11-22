# Güvenli aday sözlük derlemesi (Görev 5D, Aşama 4)

`assets/` altındaki dosyalar değiştirilmez. Aday bir çalışma klasöründe üretilir ve **depoya konmaz**.

## Komutlar (yeniden üretim)

```bash
W=/tmp/work                      # depo dışında bir klasör
RAW=/path/to/raw                 # kenet.xml, ili-map-pwn30.tab, wordnet/, eng-tur.tei, wiktionary_phrases.json.gz
# 1. Bugünkü sözlüğün provenance kayıtları (salt okunur)
python3 -I tools/lexicon_provenance/inventory.py --dict assets/dict.db --tr-en assets/tr_en.db --repo . \
    --raw "$RAW" --out $W/base/records.jsonl.gz --stats $W/base/inventory.json
# 2. Aday + karantina
python3 -I tools/lexicon_remediation/build_candidate.py --dict assets/dict.db --tr-en assets/tr_en.db --repo . \
    --records $W/base/records.jsonl.gz --records-stats $W/base/inventory.json --out $W/candidate
# 3. Bütünlük ve etki
python3 -I tools/lexicon_remediation/check_candidate.py --cand $W/candidate --json $W/impact.json
# 4. Adayın kendi provenance kayıtları ve kapı (release modu)
python3 -I tools/lexicon_provenance/inventory.py --dict $W/candidate/dict.db --tr-en $W/candidate/tr_en.db --repo . \
    --raw "$RAW" --out $W/cand/records.jsonl.gz --stats $W/cand/inventory.json
python3 -I tools/lexicon_provenance/gate.py --records $W/cand/records.jsonl.gz --mode release --out $W/cand/gate
```

Süre: her adım 7–20 saniye. Aday iki kez üretildi, iki seferde de aynı SHA (deterministik).

## Ne değişir (profil `blocked-out`)

| Yer | Değişiklik | Sayı |
|---|---|---:|
| dict.db `ft` | `main_meanings.merged(kelime, wiktionary, [])`: projenin kendi birleştirme kuralı, damdafayton'suz. Kalan her terimin o kelimenin Wiktionary terimi olduğu ayrıca kontrol edilir | 24.314 kelime çıktı, 9.784 kelime değişti (702'sinin ilk anlamı), 8.056 aynı |
| dict.db `ft` terimleri | karantinaya `damdafayton_only` | 83.381 |
| dict.db `syn.tr` | KeNet'te o sentez için olmayan (AI ile doldurulmuş) Türkçe terimler | 1.766 terim, 1.239 sentez (hepsi tamamen AI doluydu) |
| dict.db `expr.tr` | FreeDict (GPL) kökenli tek anlam | 1 |
| tr_en.db `"fd"` grupları | damdafayton kökenli İngilizce karşılıklar çıktı, kalanlar `"rv"` | 20.680 çıktı, 7.247 kaldı (7.005 grup) |
| tr_en.db `"wn"` | AI `syn.tr` terimlerinin tersinden gelen anlamlar | 360 |
| tr_en.db başvuru | anlamı kalmayan başvurular, örnekleri ve bağlam satırlarıyla | 16.145 başvuru, 2.249 örnek, 129 `ctx`, 68 `ctxn` |
| tr_en.db `ctx`/`ctxn`/`meta ctx:` | düz anlam sırası (gloss index) yeniden numaralandı | 87 / 6 / 2 |

Değişmeyen (bayt düzeyinde kontrol edildi): `sense`, `exc`, `fam`, `famg`, `exs`, `wfreq`, `exfreq`, `exd`, `wd`,
`own_word`, `own_expr`; sentez kimlikleri, ifade kimlikleri, sıralar (`rank`), formlar. AI taslakları
(`own_word`/`own_expr`) zaten "doğrulanmamış" katmanda gösterildiği için olduğu gibi kaldı.

## Sessiz yanlış anlam yok

* Hiçbir yeni metin yazılmaz; kalan her değer tabanda vardı (`check_candidate.py` kontrol eder).
* `ft` satırı yeniden üretilemiyorsa (tabandaki satır `merged(wk, dm)` değilse) derleme durur (çıkış 2).
* Provenance kayıtları başka bir dosyadan veya `--raw` olmadan üretilmişse derleme durur.
* `ft` satırı kalkan kelimede uygulama başka bir kelimenin anlamına **düşmez**: WordNet anlamları (varsa KeNet
  Türkçesiyle) ve "doğrulanmamış" AI taslağı görünür (`DictDb.lookup` kodu okunarak). 21 kelimede hiçbir şey kalmaz.

## Karantina

`quarantine.db` (dağıtılmaz, depoya konmaz): `removed(db, tbl, key, field, value, reason, record_id)` tablosunda her
çıkarılan değer, nedeni ve provenance kayıt kimliği; `note` tablosunda derleme raporu. Nedenler: `damdafayton_only`,
`ai_not_kenet`, `freedict_gpl`, `damdafayton_reverse`, `reverse_of_ai_syn_tr`, `no_meaning_left`, `lemma_removed`.

## Bütünlük kontrolleri (hepsi geçti)

`PRAGMA integrity_check`; şema aynı; dokunulmaması gereken tablolar aynı; `sense → syn` bağlantıları tam; ifade
kimlikleri ve `tr` dışındaki alanlar aynı; `ft`'de yeni terim yok; tr_en'de `"fd"` kalmadı; her başvurunun en az bir
anlamı var; `form`/`ex`/`ctx`/`ctxn` hepsi var olan başvuruya, `ctx`/`ctxn`/`meta ctx:` var olan anlam sırasına
işaret ediyor ve tabandaki **aynı anlam metnine** karşılık geliyor; Wiktionary ve katkı anlamları değişmedi.

## Kartlar, seçilmiş anlam kimlikleri, SenseEngine

* Kullanıcı verisi (`user.db`: kartlar, `words.meaning`, `sense_feedback`) uygulamada ayrı bir dosyadır; aday onu
  değiştirmez. Kartta kayıtlı anlam metni olduğu gibi kalır.
* `wn:<synId>` kimlikleri değişmez (sentez kimlikleri aynı). `od:`/`ow:` (own_word) ve `ex:`/`xd:` (expr) kimlikleri
  değişmez.
* `ft:<kelime>#<satır>` kimlikleri değişir: 40.444 satır kimliği kayboldu (kelime veya satır çıktı), 1.569 satırın
  numarası değişti. Eşleme `ft_id_map.tsv` (eski → yeni, boşsa kayıp) dosyasında; uygulamaya alınırsa
  `sense_feedback` kayıtları bu tabloyla taşınabilir. Kayıtlar `dict_version` taşıdığı için eski kayıtlar okunur kalır.
* Uygulamaya alınacaksa `DictDb.version` artırılmalı (`dict_version_test` bunu ister) ve SenseEngine önbellek
  anahtarları değişir.

## Aday dosyaları (depoya konmadı)

| Dosya | SHA-256 |
|---|---|
| `candidate/dict.db` (68,5 MB) | `70a10b76bd5fd594c3fbffa25862847978a691647360f6455d9d2b7e223e5566` |
| `candidate/tr_en.db` (42,2 MB) | `0f11a12f7051a90c508ae7e51749c1b3b83944e8984ea7b86e43fbc39ac823aa` |
| `candidate/quarantine.db` | `c961efe8d7dad20f94abad564d662ea2a8b3076752abda3270cb7d4ab6874785` |
| `candidate/ft_id_map.tsv` | `5bef825439346deb71bb60db80661c49c1d16abf7e1c99398f537d0183d10805` |

Çalışma yolu bu oturumda `/tmp/claude-0/work/candidate/` idi (geçici). Küçük raporlar: `reports/build_report.json`,
`reports/impact.json`, `reports/candidate_gate_summary.json`, `reports/candidate_vs_base_gate_summary.json`,
`reports/candidate_by_table.csv`.

## Testler

`tools/lexicon_remediation/test_candidate.py` (sentetik): yeniden üretim, karantina nedenleri, `ctx` yeniden
numaralama, `meta ctx:` anahtarı, kimlik eşlemesi, girdilerin değişmemesi, determinizm, yanlış kayıtların ve yeniden
üretilemeyen `ft` satırının reddi; `check_candidate` yeni metni, `"fd"` etiketini, kırık bağlamı ve değişmiş
`own_word`'ü yakalıyor.
