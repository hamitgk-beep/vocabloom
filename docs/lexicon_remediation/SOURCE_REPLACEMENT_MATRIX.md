# Güvenli alternatif kaynaklar (Görev 5D, Aşama 3)

Kural: yalnız kökeni kanıtlanabilen içerik kabul edilir. Yapay zekâ çıktısı hiçbir zaman bağımsız doğrulama sayılmaz
(`evidence_value: none`). "Sürüm" sütunu boşsa kaynak kullanılmadan önce sabitlenmeli.

| Kaynak | URL | Sürüm / SHA-256 | Lisans kanıtı | Kayıt kimliği | Dönüşüm | damdafayton'un yerini tutar mı? | Durum |
|---|---|---|---|---|---|---|---|
| KeNet Türkçe WordNet | github.com/StarlangSoftware/TurkishWordNet | commit `89fee78`, `kenet.xml` `4023b4f8…d66c` | README "Licensing": CC BY-SA 4.0 (commit `0a0ba22`, 05.10.2026) | KeNet sentez kimliği + CILI ile PWN 3.0 ofseti | `build_dict.load_kenet` (CILI eşlemesi), `main_meanings.apply` süzgeci | **Kısmen.** Silinen 24.314 kelimenin 5.628'inde kelime paneli zaten KeNet Türkçesi gösteriyor (anlam satırında) | Kullanılıyor; sürüm sabitlenmeli (iş akışı `master` indiriyor) |
| Collaborative Interlingual Index | github.com/globalwordnet/cili | `ili-map-pwn30.tab` `13b67413…6627` (master) | LICENSE: CC BY 4.0, Francis Bond | ILI kimliği | KeNet ↔ PWN eşlemesi | Dolaylı (KeNet için gerekli) | Kullanılıyor; commit sabitlenmeli |
| Princeton WordNet 3.0 | wordnet.princeton.edu (nltk_data) | `wn.zip` `cbda5ea6…ab59` | WordNet 3.0 LICENSE (tam metin uygulamada) | synset ofseti | `build_dict` | **Hayır** (İngilizce tanım; Türkçe yok) | Onaylı |
| Open English WordNet | github.com/globalwordnet/english-wordnet | sabitlenmedi | CC BY 4.0 (OEWN README) | `oewn-…` kimlikleri | — | **Hayır**: yalnız İngilizce. PWN 3.0'ın güncel hali; Türkçe anlam vermez | Değerlendirildi, bu görevde kullanılmadı |
| Wiktionary çevirileri, doğrudan kaikki.org dökümü | kaikki.org/dictionary/English (wiktextract) | döküm tarihi + SHA sabitlenmeli | Wiktionary:Copyrights, CC BY-SA 4.0 (+GFDL) | sayfa başlığı + çeviri sırası (`translations[]`), dökümde `wiktextract` sürümü | Türkçe (`code: tr`) çevirileri anlam grubuna göre | **Kindle bölümünün yerine geçer** (GPL derlemeye bağımlılığı kaldırır). Kindle'da olmayan sözcükleri de kapsayabilir; damdafayton'un yerini **ne kadar** tuttuğu ölçülmedi | Ölçülemedi: bu ortam kaikki.org'a erişemiyor. CI'da (GitHub Actions erişebiliyor) ayrı bir veri işi önerildi |
| İngilizce Vikisözlük Türkçe maddeleri (kaikki) | kaikki.org/dictionary/Turkish | döküm tarihi sabitlenmeli | CC BY-SA 4.0 | sayfa başlığı | `tr-en-data.yml` | tr_en için zaten ana kaynak (27.985 anlam) | Kullanılıyor |
| Tatoeba | tatoeba.org/downloads | döküm tarihi sabitlenmeli | Varsayılan CC BY 2.0 FR, bazı cümleler CC0; yazar adı şartı | cümle kimliği (iki yön) | `tatoeba_extract.py` (bugün kimlik atıyor) | Hayır (örnek cümle) | Kimlik/yazar planı: `TATOEBA_ATTRIBUTION_PLAN.md` |
| Storilex katkıları | `tools/contrib/` | xlsx dosya adları `meta.contrib`'de | Sahip beyanı (`owner_declared`) | katkı satırı | `contrib/apply.py` | **Evet, elle.** Doğrulanmış kişi katkısı tek "approved" Türkçe anlam yolu | Kullanılıyor; yazılı beyan önerildi (5C §13) |
| FreeDict eng-tur 0.3 | freedict.org | `eng-tur.tei` `2bc21fa1…043e` | GPL-2.0-or-later (TEI başlığı) | TEI girdisi | — | **Hayır**: GPL içerik CC BY-SA veritabanına konamaz | Reddedildi |
| Apertium eng-tur | github.com/apertium | — | GPL | — | — | **Hayır** (GPL) | Reddedildi |
| Wikidata sözcükbirimleri | wikidata.org | — | CC0 | L-kimliği / sense | — | Türkçe anlam bağlantıları az; ölçülmedi | Gelecek araştırma |
| AI ön çevirileri (`own_word`, `exd`, `syn.tr` dolguları) | — | model/sağlayıcı/tarih kayıtlı değil | Lisans değil, sağlayıcı şartları | — | — | **Hayır**: AI çıktısı doğrulama sayılmaz; yalnız "doğrulanmamış taslak" olarak görünebilir | Taslak katmanı korunur; `syn.tr` içindeki 1.766 AI terimi adayda çıkarıldı (KeNet diye görünüyorlardı) |

## Neden aday sözlükte yeni bir anlam üretilmedi?

* Yeni bir kaynaktan anlam eklemek için o kaynağın dökümü sabit sürüm ve SHA ile indirilmeli ve her terim kayıt
  kimliğiyle yazılmalı. Bu ortam kaikki.org ve tatoeba.org'a erişemiyor; GitHub'daki KeNet zaten kullanılıyor.
* KeNet Türkçesi damdafayton'suz kelimelerde **zaten** kelime panelinde (WordNet anlamlarının altında) görünüyor;
  `ft`'ye kopyalamak aynı veriyi iki kez göstermek olur ve `ft`'nin "ana anlam" düzenini değiştirir.
* AI çıktısıyla doldurmak yasak (kural).

## Önerilen sonraki veri işi (onay gerektirir)

`dictionary-data.yml`'a elle başlatılan bir `kaikki-translations` işi: kaikki İngilizce dökümünü indirip SHA'sını ve
tarihini yazar, yalnız Türkçe çevirileri `translations.jsonl.gz` olarak (sayfa, anlam no, çeviri) bir veri sürümüne
yükler. Ardından `main_meanings.py extract` Kindle yerine bu dosyayı okur. Kapsam ölçümü bu işin çıktısıyla yapılır.
