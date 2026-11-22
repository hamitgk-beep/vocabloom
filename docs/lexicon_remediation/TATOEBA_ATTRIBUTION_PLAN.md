# Tatoeba: cümle kimliği, yazar ve lisans planı (Görev 5D, Aşama 5)

## Bugün

| Yer | Satır | Saklanan | Eksik |
|---|---:|---|---|
| dict.db `exs` | 70.105 (63.717 Tatoeba, 6.388 katkı) | İngilizce + Türkçe metin, anahtar | iki cümle kimliği, yazarlar, lisanslar, döküm tarihi |
| tr_en.db `ex` | 84.385 (83.264 Tatoeba, 1.121 katkı) | metinler + **Türkçe** cümle kimliği (70.326 farklı) | İngilizce kimlik, yazarlar, lisanslar |
| `tatoeba_en_tr.tsv.gz` (veri sürümü) | 668.131 çift | yalnız metin | kimlikler, yazarlar |

CC BY 2.0 FR yazar adını ister (Tatoeba kullanım şartları: "only allowed if the name of the author is cited");
bazı cümleler CC0. Bugün uygulama yazar göstermiyor; metin bunu açıkça söylüyor (LICENSE_TEXT_CORRECTIONS).

## Bağımsız örneklem (22.11.2026)

* Tohum `20261122`, `exs`'ten rastgele 200 satır: 185'i `tatoeba_en_tr.tsv.gz` içinde **aynı metinle** bulundu; geri
  kalanların katkı veya değişmiş metin olduğu düşünülüyor (kontrol edilmedi).
* Bütün `exs`: 63.717 Tatoeba satırının 63.679'u aynı metinle çiftte var; 38'i yok.
* Yani kimlik eklemek için dökümden **birebir metin eşlemesi** büyük ölçüde mümkün; benzerlikle eşleme gerekmiyor.

## Tasarım

1. **Döküm** (`dictionary-data.yml` tatoeba işi): `sentences_detailed.tar.bz2` (kimlik, dil, metin, kullanıcı adı),
   `links.tar.bz2`, `sentences_CC0.tar.bz2`; dosya SHA-256'ları ve döküm tarihi `meta`'ya ve veri sürümü notuna yazılır.
2. **Çiftler**: `tools/lexicon_remediation/tatoeba_ids.py pairs` her İngilizce–Türkçe çift için
   `en_id, tr_id, en, tr, en_user, tr_user, en_license, tr_license, export_date` yazar. CC0 listesindeki cümle
   `CC0-1.0`, diğerleri Tatoeba varsayılanı `CC-BY-2.0-FR`. Kullanıcı adı yoksa `null` kalır (uydurulmaz).
3. **Eşleme**: `tatoeba_ids.py match` her sözlük örneğini, İngilizce **ve** Türkçe metni birebir aynı olan **tek** çifte
   bağlar; tr_en'de saklı Türkçe kimlik de tutmalı. İki aday varsa `ambiguous.tsv`, yoksa `unmatched.tsv`: bunlar
   **doğrulanmamış havuz**dur, yayın kapısında `needs_review` kalır. Benzerlik / bulanık eşleme yoktur.
4. **Saklama** (uygulama şemasını bozmadan): dict.db'ye yeni `exs_src(key, en, tr, en_id, tr_id, en_user, tr_user,
   en_license, tr_license, export_date)` tablosu; tr_en.db `ex`'e `en_id` sütunu + aynı yan tablo. Uygulama eski
   tabloyu okumayı sürdürür; yazar adı örnek cümlenin altında "Tatoeba #403982 · alice / bora" biçiminde gösterilir.
5. **Kapı**: `inventory.py` bu tablodan `license_id` ve `origin_record` alır; `per_record_license_missing` ve
   `origin_record_missing` bulguları kalkar. ND veya "non-marketing" gibi kısıtlı lisans, lisansı bilinmeyen veya
   yazarı silinmiş cümle yayına girmez.
6. **Katkı cümleleri** (6.388 + 1.121): Tatoeba değil; `storilex_contrib` olarak kalır.

## Atıf ve kaldırma talebi süreci

* Ayarlar > Gizlilik ve lisanslar: "Örnek cümlenin yanında yazarı ve kimliği" + tatoeba.org bağlantısı.
* Bir yazar cümlesinin kaldırılmasını veya adının farklı yazılmasını isterse: GitHub issue şablonu
  `data-takedown` (cümle kimliği, istek; şablon henüz yok). Önerilen yanıt süresi 14 gün (sahibin kararı); cümle `exs_src`'de `withdrawn` olarak
  işaretlenir ve sonraki sözlük derlemesinde çıkarılır; karantina kaydı tutulur. Tatoeba'da silinmiş cümleler her
  dökümde otomatik düşer (eşleşmez → doğrulanmamış havuz → yayına girmez).
* Uygulama cümleleri cihazda tuttuğu için kaldırma bir sonraki sözlük sürümüyle kullanıcıya ulaşır; bu süre
  belgede yazılır.

## Bu görevde yapılan / yapılmayan

* Yapıldı: `tatoeba_ids.py` (çift üretme + birebir eşleme), sentetik testleri (`test_tatoeba_ids.py`), örneklem.
* Yapılmadı: gerçek Tatoeba dökümü (bu ortam tatoeba.org'a erişemiyor), şema değişikliği, uygulama arayüzü. Bunlar
  veri işi + ayrı PR ister.
