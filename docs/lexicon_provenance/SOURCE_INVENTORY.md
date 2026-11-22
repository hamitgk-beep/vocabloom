# Sözlük kaynak envanteri (Görev 5C, Aşama 1)

Tarih: 22 Kasım 2026. İncelenen kod: `main` @ `6817c28` (PR #112 birleşmiş hâli). **Bu bir hukuki görüş değildir.**

Bütün sayılar `tools/lexicon_provenance/inventory.py` ile iki veritabanı **salt okunur** (`mode=ro&immutable=1`)
açılarak hesaplandı; betik dosyaların SHA-256 değerini önce ve sonra karşılaştırır (değişmedi):

| Dosya | SHA-256 |
|---|---|
| `assets/dict.db` | `ab4a7a53b9fc5e1edbd682da5cb7193c0c109f93236655385bf6231d90221a9c` |
| `assets/tr_en.db` | `49a661b9c8951259ab13fd6a95aa77b68e16f1c4716669dacfb6c12521cfa818` |

Yeniden üretmek için:

```
python3 -I tools/lexicon_provenance/inventory.py --raw RAW --out records.jsonl.gz --stats stats.json
python3 -I tools/lexicon_provenance/report.py records.jsonl.gz
```

`RAW` klasörü isteğe bağlıdır (kenet.xml, ili-map-pwn30.tab, wordnet/, eng-tur.tei, wiktionary_phrases.json.gz;
indirme komutları `.github/workflows/lexicon-provenance.yml` içinde). Olmadan çalışınca `syn.tr`, `expr` alanları ve
`tr_en` "wn" anlamları `unknown` kalır; tahmin yapılmaz. Bu belgedeki rakamlar `RAW` ile alındı; özet dosyaları
`reports/` klasöründe.

## Nasıl sayıldı: metin benzerliği değil, yeniden üretim

| Alan | Kaynağı bulma yöntemi | Güven |
|---|---|---|
| `ft` (kelime anlamları) | Depodaki derleme girdisi `tools/data/main_meanings.jsonl.gz` için `main_meanings.merged()` yeniden çalıştırıldı; **42.154 satırın 42.154'ü birebir aynı çıktı.** Her Türkçe terim, girdideki "wk" (Kindle'ın Wiktionary paragrafları) veya "dm" (damdafayton) listesine bağlandı. | kesin (`exact`) |
| `tr_en` "fd" etiketli anlamlar | `tools/tr_en/add_reverse.py` bellekte, bugünkü `ft` üzerinden yeniden çalıştırıldı; **27.927 başvurunun 27.927'si yeniden üretildi** ve her biri `ft` teriminin kökenini aldı. | kesin |
| `syn.tr`, `expr.tr/en`, `tr_en` "wn" | `build_dict.py`'nin ilk adımları (KeNet, WordNet, FreeDict, kategori listesi, Wiktionary ifadeleri) ham girdilerle bellekte yeniden çalıştırıldı; saklı değer hangi adımın çıktısına eşitse o adıma bağlandı. Ham girdiler bugün yeniden indirildiği için derleme anındakiyle aynı olduğu kanıtlanamaz. | çıkarım (`inferred`) |
| `own_word`, `own_expr` | Satırın kendi `status`, `reviewed`, `source` sütunları | kesin (beyan) |
| `exs`, `tr_en.ex` | Katkı dosyası `storilex_contrib.json` ile birebir eşleşen satırlar katkı; geri kalanı derleme kuralına göre Tatoeba | kesin (veri kümesi düzeyinde) |
| `sense`, `exc`, `fam`, `famg`, `wfreq`, `exfreq`, `form`, `ctx`, `rank` | Tabloyu yazan derleme kodu; tablo başına tek toplu kayıt | kesin / `form` çıkarım |

## 1. İngilizce → Türkçe sözlük (`assets/dict.db`)

### Kullanıcının gördüğü içerik: 465.786 kayıt

| Tablo / alan | Kayıt | Kaynak (köken) | Kesinlik | Not |
|---|---:|---|---|---|
| `ft` Türkçe terimler | 117.129 | **damdafayton 83.381 (%71,2)**; Kindle-Wiktionary 33.748 (%28,8; bunların 12.345'i damdafayton'da da var) | kesin | 42.154 kelime. **Ana anlam (ilk terim) 24.314 kelimede (%57,7) yalnız damdafayton'dan geliyor**; 17.840 kelimede Wiktionary'den. 24.314 kelimenin tüm anlamları yalnız damdafayton. 671 kelimede ilk satırın sırasını damdafayton belirledi. |
| `syn` tanım, örnek, eş anlamlı | 117.659 | Princeton WordNet 3.0 | kesin | |
| `syn.tr` Türkçe terimler | 21.448 | KeNet 19.682; **AI (pretranslate "syn") 1.766** | çıkarım | 14.171 synset. AI terimleri, KeNet'in Türkçe vermediği synset'lere `load_syn` ile doldurulmuş. |
| `expr.tr` | 10.934 | katkı 2.486; kategori listesi 902; `expr_fixes` 234; Wiktionary 699; KeNet 475; FreeDict 1; **bilinmeyen 6.137** | kesin/çıkarım | Bilinmeyenlerin olası kaynağı AI "gl-" kısa anlamları, eski katkı sürümleri veya değişmiş Wiktionary dökümü. |
| `expr.en` | 15.326 | Wiktionary 12.715; WordNet 2.158; bilinmeyen 453 | çıkarım | |
| `expr.entr` | 4.184 | AI (yalnız `load_gloss` yazar) | kesin | |
| `expr.ex` | 11.412 | katkı 1.841; **bilinmeyen 9.571** (büyük olasılıkla Wiktionary örnekleri; dökümün o günkü sürümü yok) | | |
| `exd` öğretmen anlatımı | 2.510 | AI | kesin | |
| `exs` örnek cümle çiftleri | 70.105 | Tatoeba 63.717; katkı 6.388 | kesin (küme) | **Tatoeba cümle kimliği, yazar ve cümle lisansı saklanmıyor.** |
| `own_word` anlamları | 81.196 | **AI taslağı 80.997** (incelenmemiş); katkı 100; taslak satırında `src: storilex` 99 | kesin (beyan) | 41.269 kelime (41.177 AI, 92 katkı) |
| `own_expr` anlamları | 13.883 | **AI taslağı 13.110**; katkı 691; taslakta `storilex` 82 | kesin (beyan) | 10.781 ifade |

### Yapısal tablolar: 282.542 kayıt
`sense` 206.941, `exc` 5.952, `fam` 31.120, `famg` 11.874 (WordNet'ten türetilmiş); `wfreq` 22.491, `exfreq` 4.164
(Tatoeba cümlelerinde sayım). `wd` boş. `meta.version = 1`, `meta.contrib` katkı dosyalarını listeler;
**`meta` içinde kaynak veya lisans bilgisi yok.**

### dict.db özet
- Kaynak (veri kümesi) düzeyinde kesin bilinen: 412.129 / 465.786 içerik kaydı (%88,5); çıkarımla bağlanan 37.496 (%8,1);
  **kaynağı bilinmeyen 16.161 (%3,5).**
- Kayıt kimliği (kaynaktaki karşılığı) bulunan: 385.908 (%82,9). Eksik olanlar ağırlıkla Tatoeba cümleleri.
- Lisansı bilinmeyen (AI çıktısı veya bilinmeyen kaynak): 118.728 kayıt.
- Birden fazla kaynağa bağlı: 32.027 kayıt (12.345 `ft` terimi Wiktionary + damdafayton; 19.682 KeNet + CILI).
- AI tarafından üretilmiş: 102.567; AI destekli (Claude ile yazılmış listeler): 1.136; AI katkısı bilinmeyen: 16.161.

## 2. Türkçe → İngilizce sözlük (`assets/tr_en.db`)

### İçerik: 148.197 kayıt

| Alan | Kayıt | Kaynak | Not |
|---|---:|---|---|
| `lemma` anlamları, etiketsiz | 27.985 | kaikki.org / İngilizce Wiktionary'nin Türkçe maddeleri | |
| "st" | 618 | Storilex katkıları | |
| **"fd"** (FreeDict diye işaretli) | 27.927 İngilizce başvuru | **damdafayton 20.680 (%74,0), Kindle-Wiktionary 7.247; FreeDict 0** | `add_reverse.py` 2026-11-19'da çalıştı; o tarihte `ft` 2026-11-17'den beri FreeDict değil, Wiktionary + damdafayton tutuyordu. Etiket yanlış. |
| "wn" | 7.282 | KeNet + WordNet 6.922; **AI + WordNet 360** | Betik "yalnız insan yapımı açık kaynaklar" diyor; ama `syn.tr` AI Türkçesi de içeriyor. |
| `ex` örnek çiftleri | 84.385 | Tatoeba 83.264 (Türkçe cümle kimliği var); katkı 1.121 (kimliksiz, `id` NULL) | İngilizce cümle kimliği, yazarlar ve cümle lisansı yok. |

Yapısal: `lemma.rank` 55.364 (FrequencyWords / OpenSubtitles 2018), `form` 401.588 (kaikki biçimleri, sıklık listesiyle
süzülmüş), `ctx` 81.972 ve `ctxn` 7.265 (Tatoeba sayımları), `meta` içinde 763 katkı bağlam cümlesi.

`meta.sources` = "Kaikki.org / English Wiktionary (CC BY-SA 4.0); FrequencyWords / OpenSubtitles 2018 (CC BY-SA 4.0);
Tatoeba (CC BY 2.0 FR)". **damdafayton, KeNet, WordNet ve AI burada yazmıyor**; `meta.reverse` FreeDict diyor.

### tr_en.db özet
- Kaynak düzeyinde kesin: 140.915 / 148.197 (%95,1); çıkarım 7.282 (%4,9); bilinmeyen 0.
- Lisansı bilinmeyen: 360 (AI). AI üretimi: 360.
- **Lisans açısından engellenen: 20.680 başvuru (damdafayton kökenli).**

## 3. Kaynak listesi (sürüm ve URL)

Kayıt defteri: `tools/lexicon_provenance/registry.json`. Lisans kanıtları: `LICENSE_AUDIT.md`.

| Kaynak kimliği | Ad | Sürüm (derlemede kullanılan) | URL | Lisans | İşlem |
|---|---|---|---|---|---|
| `wiktionary_en` | English Wiktionary | **kaydedilmemiş** | en.wiktionary.org | CC BY-SA 4.0 + GFDL | kaikki dökümü → wiktextract |
| `wiktionary_tr` | Vikisözlük | **kaydedilmemiş** | tr.wiktionary.org | CC BY-SA (bu denetimde okunamadı) | kaikki trwiktionary → `wiktionary_extract.py` |
| `kaikki`, `kaikki_en` | kaikki.org / wiktextract | **kaydedilmemiş** (tarihsiz indirme) | kaikki.org | Wiktionary'den miras; kod MIT | çıkarım (extraction) |
| `kindle_en_tr_wiktionary_part` | Murat Uysal, Kindle EN–TR, yalnız Wiktionary paragrafları | **kaydedilmemiş** (.mobi sürümü yok; README kaikki Mayıs 2026) | github.com/mybottles/kindle-en-tr-dictionary | derleme GPL-2.0+, alınan kısım CC BY-SA 4.0 (miras) | `.mobi` → `main_meanings.extract` → `merged` |
| `damdafayton` | damdafayton/eng-tur-dictionary | son commit `f8f1a3d` (2022-02-17); kullanılan commit kaydedilmemiş | github.com/damdafayton/eng-tur-dictionary | **kanıtlanmamış "MIT"** | sqlite → `main_meanings.extract` → `merged` |
| `freedict_eng_tur` | FreeDict English–Turkish | 0.3 (2017-12-03) | github.com/freedict/fd-dictionaries/eng-tur | GPL-2.0-or-later | `load_freedict` (artık `ft`'de yok) |
| `princeton_wordnet` | Princeton WordNet | 3.0 | wordnet.princeton.edu | WordNet 3.0 License | `load_wordnet` |
| `kenet` | KeNet Türkçe WordNet | **master, commit kaydedilmemiş** | github.com/StarlangSoftware/TurkishWordNet | CC BY-SA 4.0 (veri) | CILI üzerinden `syn.tr` |
| `cili` | Collaborative Interlingual Index | master, commit yok | github.com/globalwordnet/cili | CC BY 4.0 | eşleme |
| `tatoeba` | Tatoeba | **tarihsiz haftalık döküm** | tatoeba.org | CC BY 2.0 FR (cümle başına farklı olabilir) | `tatoeba_extract.py`, `tatoeba_pairs.py` |
| `frequencywords` | FrequencyWords / OpenSubtitles 2018 | 2018 | github.com/hermitdave/FrequencyWords | **doğrulanamadı** | yalnız sıra |
| `storilex_contrib` | Hamit'in katkıları | `storilex_contrib.json` @ `6817c28` | tools/contrib | sahibinin beyanı | `contrib/apply.py` |
| `storilex_categories`, `storilex_expr_fixes` | Kategori listeleri, ifade düzeltmeleri | @ `6817c28` | tools/ | sahibinin beyanı; commit'lerin çoğu Claude'un | elle/AI destekli |
| `ai_pretranslate`, `own_dict_ai` | AI taslakları | model/tarih satırda yok | tools/pretranslate.py, tools/own_dict | lisans yok, sağlayıcı şartları | |

## 4. Bulunan çelişkiler (makinece okunur liste: `conflicts.csv`)

1. `tr_en.db` içinde 27.927 "fd" başvurusu FreeDict diye etiketli ama hiçbiri FreeDict'ten değil (bkz. §2).
2. Ayarlar sayfası "FreeDict English–Turkish (GPL-2.0+)" diyor; FreeDict bugün `dict.db`'de pratikte yok
   (çıkarımla 1 ifade anlamı) ve `tr_en.db`'de hiç yok.
3. `add_reverse.py` belgesi "AI taslakları kullanılmadı" diyor; 360 "wn" anlamı AI Türkçesinden ters çevrilmiş.
4. 671 kelimede ana anlam sırasını lisansı kanıtlanmamış damdafayton belirledi.
5. `build_dict.py` başındaki açıklama `ft` için hâlâ "FreeDict" diyor; gerçek kaynak `main_meanings.py`.
