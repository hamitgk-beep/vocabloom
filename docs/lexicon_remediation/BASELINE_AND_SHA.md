# Başlangıç durumu ve SHA değerleri (Görev 5D, Aşama 0)

Ölçüm tarihi: 22 Kasım 2026. Hukuki görüş değildir.

## Üç ayrı durum

| Durum | Ne | dict.db SHA-256 | tr_en.db SHA-256 |
|---|---|---|---|
| **Yayındaki sürüm** | `latest` ön sürümü, hedef commit `7721b01` (Storilex 8.3) | `ab4a7a53b9fc5e1edbd682da5cb7193c0c109f93236655385bf6231d90221a9c` | `49a661b9c8951259ab13fd6a95aa77b68e16f1c4716669dacfb6c12521cfa818` |
| **main** | `bf306302d0ba2d92747a03bc4b42967b49f6d51b` (PR #113 birleşmesi) | aynı | aynı |
| **Yeni aday** | `tools/lexicon_remediation/build_candidate.py` çıktısı, **depoya konmadı** | `70a10b76bd5fd594c3fbffa25862847978a691647360f6455d9d2b7e223e5566` | `0f11a12f7051a90c508ae7e51749c1b3b83944e8984ea7b86e43fbc39ac823aa` |

Yayındaki sözlük ile main'deki sözlük bayt bayt aynıdır (5C'de doğrulandı; 8.3'ten bu yana `assets/*.db` değişmedi).
Aday iki kez sıfırdan üretildi ve iki seferde de aynı SHA çıktı (deterministik).

Bu görevde `assets/dict.db` ve `assets/tr_en.db` **değiştirilmedi**; görevin sonunda SHA'lar yukarıdakiyle aynı.

## Tablo kayıt sayıları

| Tablo | Yayın / main | Aday | Fark |
|---|---:|---:|---:|
| dict.db `ft` | 42.154 | 17.840 | −24.314 |
| dict.db `syn` (satır) | 117.659 | 117.659 | 0 (1.239 sentezin Türkçesi boşaldı) |
| dict.db `sense` | 206.941 | 206.941 | 0 |
| dict.db `expr` | 18.209 | 18.209 | 0 (1 satırın `tr`'si boşaldı) |
| dict.db `exs` | 70.105 | 70.105 | 0 |
| dict.db `own_word` / `own_expr` | 41.269 / 10.781 | aynı | 0 |
| dict.db `exc`, `fam`, `famg`, `exd`, `wfreq`, `exfreq` | 5.952 / 31.120 / 11.874 / 2.510 / 22.491 / 4.164 | aynı | 0 |
| dict.db `meta` | 2 | 3 | +1 (`candidate` anahtarı) |
| tr_en.db `lemma` | 55.364 | 39.219 | −16.145 |
| tr_en.db `form` | 401.588 | 401.588 | 0 |
| tr_en.db `ex` | 84.385 | 82.136 | −2.249 |
| tr_en.db `ctx` / `ctxn` | 81.972 / 7.265 | 81.843 / 7.197 | −129 / −68 |
| tr_en.db `meta` | 771 | 772 | +1 |

## 5C sayılarının yeniden üretimi

`inventory.py --raw` + `gate.py --mode legacy`, aynı ham girdilerle (aşağıda) yeniden çalıştırıldı:

| Ölçü | 5C | 5D yeniden üretim |
|---|---:|---:|
| Toplam kayıt (sayım ağırlıklı) | 1.443.477 | 1.443.477 |
| blocked | 104.062 | 104.062 (= 83.381 `ft` + 20.680 `tr_en` + 1 `expr`) |
| Ana anlamı yalnız damdafayton olan kelime | 24.314 | 24.314 |
| unknown | 119.088 | 119.088 |
| dict.db içerik kayıtlarından kaynağı bilinmeyen | 16.161 | 16.161 (5C `traceability.json`) |

## Ham girdiler (SHA-256)

| Dosya | Kaynak / sürüm | SHA-256 |
|---|---|---|
| `kenet.xml` | StarlangSoftware/TurkishWordNet `master` = `89fee78` (17.10.2026) | `4023b4f815dcae78171c69d26e6f31aae3ba70c98fb2e44919a09e87d673d66c` |
| `ili-map-pwn30.tab` | globalwordnet/cili `master` | `13b6741395a8bdf20e5a19686ffa49167653696d4f523db17a79dce3211a6627` |
| `wn.zip` | nltk_data WordNet 3.0 | `cbda5ea6eef7f36a97a43d4a75f85e07fccbb4f23657d27b4ccbc93e2646ab59` |
| `eng-tur.tei` | FreeDict eng-tur 0.3 (2017-12-03) | `2bc21fa1a784f68df6d94edfcde900ac185e51a6088e3245d9e08d8563c0043e` |
| `wiktionary_phrases.json.gz` | sürüm `data-wiktionary` | `cc275a4a9132f65b4e8545ff00937221131453c325b9b5c0c8458a410c1236a0` |
| `tatoeba_en_tr.tsv.gz` | sürüm `data-tatoeba` | `9e978d08837ed96900575fbe94eb44e89a807775b5d37559d16861eea453f0d5` |
| damdafayton deposu | `f8f1a3d4c24c8cbb7a492367ff07694f966dee2c` (17.02.2022), `english_turkish.sqlite` | `f8b7908d44b43ec26015f548883b64c81a4d53b9625374d109c14e12f27d7ef2` |

Provenance kayıtları (depoya konmadı, yeniden üretilebilir): taban `records.jsonl.gz`
`628682f8496daa2888df775bed90e56a479ae14f29bd19cbdd6c07088cbb417f`, aday `b42aff71cfb354cb9189b6fa92bf58bbd14cfb07f92f0bdd420a035e21c4030e`.

## İş akışları

`build.yml` (PR/push testleri, derleme ve yayın provası), `release.yml` (tek yayın yolu; elle, sahip, YAYINLA,
production onayı, **5D ile `dictionary-gate`**), `lexicon-provenance.yml` (5C/5D sentetik testler ve legacy rapor),
`dictionary-data.yml`, `tr-en-data.yml` ve diğer veri iş akışları. Bu görevde hiçbir iş akışı elle başlatılmadı ve
yayın tetiklenmedi.
