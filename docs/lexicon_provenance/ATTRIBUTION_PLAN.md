# Lisans bilgilerini kullanıcıya sunma planı (Görev 5C, Aşama 7)

**Bu görevde uygulama arayüzü değiştirilmedi.** Aşağıdakiler, `lib/ui/settings_page.dart` içindeki "Gizlilik ve
lisanslar" sayfası (`LicensesPage`, satır 483–546) için düzeltme listesi ve içerik taslağıdır. Metinler
`L('Türkçe', 'English')` düzenine uygun yazıldı. Doğrulanmamış hiçbir kaynak "lisanslı" diye gösterilmedi.

## 1. Bugünkü ifadeler ve düzeltme gereği

| Satır | Bugünkü ifade | Sorun | Öneri |
|---|---|---|---|
| 508–509 | "Kelime anlamları: Wiktionary çevirileri, kaikki.org üzerinden; Murat Uysal'ın Kindle İngilizce–Türkçe sözlüğü derlemesi (CC BY-SA 4.0)" | Kindle derlemesi bir bütün olarak GPL-2.0+ dağıtılıyor; alınan kısım Wiktionary (CC BY-SA 4.0). İfade derlemenin kendisini CC BY-SA gösteriyor. | "Wiktionary çevirileri (CC BY-SA 4.0), Murat Uysal'ın Kindle derlemesindeki Wiktionary bölümünden" |
| 510 | "Yardımcı kelime anlamları: damdafayton/eng-tur-dictionary (MIT)" | **MIT kanıtlanamadı** (lisans dosyası yok, veri kökeni yok). Üstelik "yardımcı" değil: `ft` terimlerinin %71'i, ana anlamların %58'i buradan. | "(MIT)" kaldırılmalı. Kaynak durumu netleşene kadar: "damdafayton/eng-tur-dictionary (lisansı doğrulanamadı; kaynak sahibine soruldu)". Kalıcı çözüm REMEDIATION_PLAN §1. |
| 511 | "FreeDict English–Turkish (GPL-2.0+)" | FreeDict bugün `ft`'de yok, `tr_en`'de hiç yok (yalnız etiket), `expr`'de çıkarımla 1 kayıt. | Tek kayıt ayıklanınca satır kaldırılabilir; kalırsa "GPL-2.0-or-later, bu içerik CC BY-SA altında değil" uyarısıyla. |
| 513 | KeNet (CC BY-SA 4.0) | Doğru. | Sürüm (commit) eklenmeli. |
| 515 | "Kalıplar: İngilizce ve Türkçe Vikisözlük, kaikki.org üzerinden (CC BY-SA 4.0)" | Türkçe Vikisözlük lisansı bu denetimde okunamadı. | Doğrulanınca aynı kalabilir. |
| 516 | "Çevirili örnek cümleler: Tatoeba (CC BY 2.0 FR)" | Cümle başına farklı lisans olabilir; yazar adları gösterilmiyor (CC BY şartı). | "Tatoeba katkıcıları; her cümlenin yazarı ve lisansı cümlenin yanında" (cümle kimlikleri saklanınca). |
| 521–522 | "kelime sıklığı: FrequencyWords / OpenSubtitles 2018 (CC BY-SA 4.0)" | CC BY-SA 4.0 dayanağı bulunamadı. | "kelime sıklığı sırası: FrequencyWords (Hermit Dave), OpenSubtitles 2018 verisinden" — lisans adı doğrulanana kadar yazılmamalı. |
| 517–518 | Storilex katkıları | Doğru. | |
| — (yok) | AI taslakları | `own_word`/`own_expr` taslakları, `exd`, `expr.entr` ve 1.766 `syn.tr` terimi AI çıktısı; sayfada hiç geçmiyor. | Yeni satır (aşağıda §2). |
| — (yok) | Princeton WordNet bildirimi | WordNet lisansı bildirimin "her kopyada" bulunmasını ister. | Tam bildirim metni (aşağıda §3) bir alt sayfada. |
| 528–529 | "Uygulamadaki sözlük veritabanı … aynı lisansla (CC BY-SA 4.0) paylaşılır." | Kanıtlanamayan (damdafayton) ve GPL (FreeDict, 1 kayıt) içerik bu beyanla çelişiyor. | Düzeltmeler yapılana kadar: "Sözlük veritabanının açık kaynaklı bölümleri CC BY-SA 4.0 ile paylaşılır. Lisansı doğrulanamayan bölümler için kaynak sayfasına bakın." |
| 475 / 538 | "© 2026 Hamit Gök. Tüm hakları saklıdır." ile "Storilex açık kaynaklıdır (GPL-3.0)" | Çelişkili görünüyor. | "© 2026 Hamit Gök. Uygulama kodu GPL-3.0, sözlük verisi CC BY-SA 4.0 (ayrıntı: Kaynaklar)." |

## 2. "Sözlük kaynakları" alt sayfası için içerik taslağı

Önerilen konum: Ayarlar > Gizlilik ve lisanslar > **Sözlük kaynakları** (yeni alt sayfa; bugünkü liste kısa özet olarak
kalır). Ayrıca kelime panelinde her anlamın yanında küçük bir kaynak etiketi (ör. "Wiktionary", "KeNet",
"Storilex katkısı", "Doğrulanmamış AI taslağı") ve örnek cümlenin altında "Tatoeba #403982, yazar: …".

```dart
// Taslak: yalnız içerik. Bu görevde uygulamaya eklenmedi.
SectionLabel(L('Sözlük kaynakları', 'Dictionary sources')),
item(L('Kelime anlamları: İngilizce Vikisözlük çevirileri (CC BY-SA 4.0), Murat Uysal\'ın Kindle İngilizce–Türkçe derlemesindeki Vikisözlük bölümünden. Yazarlar: Vikisözlük katkıcıları.',
       'Word meanings: English Wiktionary translations (CC BY-SA 4.0), from the Wiktionary part of Murat Uysal\'s Kindle English–Turkish compilation. Authors: Wiktionary contributors.')),
item(L('Ek kelime anlamları: damdafayton/eng-tur-dictionary. Lisansı ve kaynağı doğrulanamadı.',
       'Additional word meanings: damdafayton/eng-tur-dictionary. Its licence and origin could not be verified.')),
item(L('İngilizce tanımlar, eş anlamlılar, kök biçimler: Princeton WordNet 3.0 (WordNet Lisansı). Tam bildirim aşağıda.',
       'English definitions, synonyms, base forms: Princeton WordNet 3.0 (WordNet License). Full notice below.')),
item(L('Anlamların Türkçesi: KeNet Türkçe WordNet, Starlang Yazılım / Özyeğin Üniversitesi (CC BY-SA 4.0); Collaborative Interlingual Index ile eşlendi (CC BY 4.0, Francis Bond).',
       'Turkish for senses: KeNet Turkish WordNet, Starlang Software / Özyeğin University (CC BY-SA 4.0); linked through the Collaborative Interlingual Index (CC BY 4.0, Francis Bond).')),
item(L('Kalıplar ve deyimler: İngilizce ve Türkçe Vikisözlük, kaikki.org / wiktextract (Tatu Ylonen) üzerinden (CC BY-SA 4.0).',
       'Expressions and idioms: English and Turkish Wiktionary via kaikki.org / wiktextract (Tatu Ylonen) (CC BY-SA 4.0).')),
item(L('Örnek cümleler: Tatoeba katkıcıları (tatoeba.org), varsayılan lisans CC BY 2.0 FR; bazı cümlelerin lisansı farklı olabilir.',
       'Example sentences: Tatoeba contributors (tatoeba.org), default licence CC BY 2.0 FR; some sentences may carry another licence.')),
item(L('Türkçe → İngilizce: İngilizce Vikisözlük\'ün Türkçe maddeleri, kaikki.org üzerinden (CC BY-SA 4.0); eksik kelimeler İngilizce → Türkçe verinin tersinden.',
       'Turkish → English: Turkish entries of the English Wiktionary via kaikki.org (CC BY-SA 4.0); missing words from the English → Turkish data, reversed.')),
item(L('Kelime sıklığı sırası: FrequencyWords (Hermit Dave), OpenSubtitles 2018 verisinden.',
       'Word frequency rank: FrequencyWords (Hermit Dave), from OpenSubtitles 2018 data.')),
item(L('Yapay zekâ taslakları: bazı anlam, açıklama ve örnekler yapay zekâ ile hazırlandı ve henüz bir insan tarafından kontrol edilmedi. Uygulamada "doğrulanmamış" etiketiyle gösterilir.',
       'AI drafts: some meanings, explanations and examples were drafted with AI and have not been checked by a person yet. The app marks them as "unverified".')),
item(L('Storilex katkıları: kullanıcılarımızın elle hazırlayıp kontrol ettiği anlamlar, örnekler ve deyimler. Katkı verenler: Hamit',
       'Storilex contributors: meanings, examples and idioms prepared and checked by hand. Contributors: Hamit')),
item(L('Değişiklikler: kaynak metinler kısaltıldı, birleştirildi, sıralandı ve yazım hataları temizlendi.',
       'Changes: source texts were shortened, merged, reordered and cleaned.')),
```

## 3. Zorunlu atıf metinleri ve dayanakları

| Kaynak | Gösterilmesi gereken | Dayanak |
|---|---|---|
| English Wiktionary / Vikisözlük | Eser adı, "Wiktionary contributors", lisans adı + bağlantı (creativecommons.org/licenses/by-sa/4.0), değişiklik yapıldığı bilgisi | CC BY-SA 4.0 §3(a); Wiktionary:Copyrights |
| kaikki.org / wiktextract | Önerilir (lisans şartı değil): "kaikki.org / wiktextract, Tatu Ylonen" | wiktextract README ve MIT kod lisansı |
| Kindle derlemesi | "Murat Uysal (muratuysal.com)" | Derleyicinin README'si; CC BY-SA zincirinde atıfın korunması |
| Princeton WordNet 3.0 | Tam bildirim: "WordNet Release 3.0 This software and database is being provided to you, the LICENSEE, by Princeton University under the following license … WordNet 3.0 Copyright 2006 by Princeton University. All rights reserved." + sorumluluk reddi | WordNet LICENSE: bildirim "ALL copies" içinde yer almalı |
| KeNet | "KeNet, Starlang Software / Özyeğin University, CC BY-SA 4.0" + lisans bağlantısı | KeNet README Licensing |
| CILI | "Collaborative Interlingual Index, Francis Bond, CC BY 4.0" | CILI LICENSE |
| Tatoeba | Her cümlenin yazarı; lisans (CC BY 2.0 FR veya cümlenin kendi lisansı); tatoeba.org bağlantısı | Tatoeba Terms of Use: "only allowed if the name of the author is cited" |
| FreeDict (kalırsa) | "FreeDict English-Turkish 0.3, (C) 1999-2017 various authors, GPL-2.0-or-later" + GPL metni + kaynağın erişim yolu | eng-tur.tei başlığı, GPL §1–3 |
| damdafayton | Atıf metni yazılamıyor: telif sahibi ve lisans bilinmiyor | — (kapı: `attribution_missing`) |
| AI taslakları | Lisans şartı yok; dürüstlük için "AI taslağı, doğrulanmamış" etiketi | Proje kuralı (PR #110) |

Atıf metinleri makinece okunur olarak `tools/lexicon_provenance/registry.json` → `sources.*.attribution` içinde.
Uygulama ileride bu dosyadan üretilecek bir `assets/attribution.json` okuyabilir; böylece ekran ile kayıt defteri
ayrışmaz.

## 4. Önerilen konumlar

1. **Ayarlar > Gizlilik ve lisanslar:** kısa özet + "Sözlük kaynakları" alt sayfasına bağlantı.
2. **Sözlük kaynakları alt sayfası:** §2 metni, WordNet tam bildirimi, lisans bağlantıları, sözlük sürümü ve
   denetim tarihi.
3. **Kelime paneli:** anlamın yanında kaynak etiketi; AI taslakları zaten "doğrulanmamış" bölümünde (PR #110).
4. **Örnek cümle:** Tatoeba cümlelerinde yazar ve cümle kimliği (veri saklanmaya başlayınca).
5. **Depoda:** `docs/lexicon_provenance/` ve uygulama ile dağıtılan bir `DATA_LICENSES.md` (kaynak listesi, lisans
   metinleri bağlantıları).
