# Kalan hukuki riskler (Görev 5D)

Bu bir hukuki görüş değildir. "Gerekebilir" diye işaretlenenler için uzman görüşü önerilir.

| # | Risk | Bugünkü yayın | Aday | Uzman görüşü |
|---|---|---|---|---|
| 1 | damdafayton verisi: lisans dosyası yok, veri kökeni (`lugat1.xls`) bilinmiyor | 104.061 kayıt dağıtılıyor | Karantinada, dağıtılmıyor | Önceki sürümlerdeki dağıtım için gerekebilir |
| 2 | damdafayton'un **seçim etkisi**: 671 (adayda 702) kelimede ilk Wiktionary anlamını, `syn.tr` süzgecinde hangi KeNet teriminin kalacağını belirledi | Var | İlk anlam etkisi kalktı; KeNet süzgeç etkisi kaldı | Muhtemelen gerekmez (içerik kopyası değil), ama belgelendi |
| 3 | Kindle derlemesi (GPL-2.0+) içinden alınan Wiktionary bölümünün CC BY-SA 4.0 sayılması | 33.748 `ft` terimi, 7.247 tr_en karşılığı | Aynı (needs_review) | Gerekebilir; kalıcı çözüm doğrudan kaikki dökümü |
| 4 | Tatoeba: cümle başına lisans ve yazar yok; CC BY 2.0 FR içeriğin CC BY-SA 4.0 veritabanında uyarlaması | 146.981 örnek | Aynı (needs_review) | Uyumluluk için gerekebilir |
| 5 | AI çıktısı: sağlayıcı şartları okunmadı, model/tarih kayıtlı değil | `own_word`/`own_expr`/`exd`/`expr.entr` | Aynı ("doğrulanmamış" etiketli) | Sağlayıcı şartları için gerekebilir |
| 6 | FrequencyWords / OpenSubtitles lisans dayanağı yok | Yalnız sıra | Aynı | Hayır (sıra bilgisi), ama doğrulanmalı |
| 7 | Türkçe Vikisözlük lisans sayfası okunmadı | `expr` bir kısmı | Aynı | Hayır |
| 8 | `expr` içinde kaynağı bilinmeyen 6.137 Türkçe anlam, 9.571 örnek, 453 tanım | Var | Aynı (unknown) | Hayır; kaynak izi gerekli |
| 9 | Storilex katkılarının kapalı sözlüklerden kopyalanmadığına dair yazılı beyan yok | 14.189 kayıt | Aynı | Hayır |
| 10 | FreeDict GPL içeriği önceki sürümlerde (`ft` 17.11.2026 öncesi) dağıtıldı | Bugün 1 ifade | 0 | Paket GPL değilse gerekebilir |
| 11 | Uygulama kodu GPL-3.0, veri CC BY-SA 4.0: CC BY-SA 4.0 → GPLv3 tek yönlü uyumlu; GPL içerik BY-SA'ya alınamaz | Metin düzeltildi | — | Hayır |
| 12 | Legacy istisna onaylanırsa: bilinen lisans sorunu olan dosyalar yeniden dağıtılır | — | — | Sahibin bilinçli kararı; süreli |

**Sözlük hâlâ lisans güvenli değildir.** Aday sözlükte `blocked` kalmadı ama 813.880 `needs_review` ve 117.085
`unknown` kayıt var; `gate --mode release` başarısız.
