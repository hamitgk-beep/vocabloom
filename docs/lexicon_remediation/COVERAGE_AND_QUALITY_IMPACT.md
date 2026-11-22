# Kapsam ve kalite etkisi (Görev 5D)

Aday = `blocked-out` profili (`SAFE_DICTIONARY_BUILD.md`). Sayılar `reports/impact.json` ve `build_report.json`.

## Kazanımlar

| | Önce | Aday |
|---|---:|---:|
| blocked kayıt | 104.062 | **0** |
| damdafayton kökenli içerik (ft terim + tr_en karşılık) | 104.061 | 0 (karantinada) |
| FreeDict (GPL) içerik | 1 | 0 |
| KeNet diye gösterilen AI terimi (`syn.tr`) | 1.766 | 0 |
| "KeNet / WordNet" diye gösterilen AI kökenli tr_en anlamı | 360 | 0 |
| tr_en'de yanlış "fd" etiketi | 27.927 | 0 |
| unknown | 119.088 | 117.085 |

## Kayıplar

| | Önce | Aday | Kayıp |
|---|---:|---:|---:|
| `ft` kelimesi (ana Türkçe anlam listesi) | 42.154 | 17.840 | 24.314 (%57,7) |
| `ft` Türkçe terimi | 117.129 | 33.748 | 83.381 |
| tr_en başvurusu | 55.364 | 39.219 | 16.145 (%29,2) |
| tr_en örnek cümlesi | 84.385 | 82.136 | 2.249 (2'si Hamit'in doğrulanmış katkı örneği: "elden geçirmek", "üzerinde durmak"; karantinada) |
| İlk anlamı değişen kelime | — | 702 | |

### `ft` satırı kalkan 24.314 kelime uygulamada ne gösterir?

`DictDb.lookup` kodu ve aday verisiyle ölçüldü (aynı kelime yalnız bir sınıfta sayıldı):

| Gösterilen | Kelime |
|---|---:|
| Doğrulanmış katkı (own_word contrib) | 0 |
| WordNet anlamı + KeNet Türkçesi (anlam satırında) | 5.628 |
| Yalnız "doğrulanmamış" AI taslağı | 18.610 |
| Yalnız İngilizce WordNet tanımı | 55 |
| Hiçbir şey | 21 |

Yani **24.314 kelimenin 5.628'i (%23)** güvenli bir Türkçe kaynakla karşılanıyor; 18.610'u (%77) yalnız AI taslağına
kalıyor. Ayrıca 4.879 kelime WordNet'te yok; `ft` satırı kalkınca kök bulucu (lemmatizer) bu kelimeleri tanımaz.

### Sık kelimeler

`wfreq` (Tatoeba sıklığı, çekimli biçimler dahil) sırasında ilk 1.000 kelimeden 104'ü, ilk 5.000'den 636'sı, ilk
10.000'den 1.507'si `ft` satırını kaybediyor. Örnekler: the, a, an, could, any, anything, us, let, off, else, ago,
tonight, nobody, likely, sick. Çekimli biçimler (going, had, said) kök kelimeden bulunur; asıl kayıp işlev
kelimeleri ve bazı sık sözcüklerdir. **Bu, adayın olduğu gibi yayımlanamayacağının ana nedenidir.**

## Uygulama testleri (aday veriyle)

Deponun bir kopyasında `assets/*.db` aday dosyalarla değiştirilip tam `flutter test` çalıştırıldı (Flutter 3.50.0,
yerel). Asıl depoya dokunulmadı.

| | Geçen | Atlanan | Kalan |
|---|---:|---:|---:|
| main verisi | 536 | 11 | 3 (PDFium kütüphanesi bu ortamda yok: text_repair, picture_book, import_completeness kurulumları) |
| aday veri | 520 | 11 | 19 (aynı 3 + **16 veri kaynaklı**) |

Aday veriyle yeni kalan 16 test:

* `dict_version_test`: sözlük değişince `DictDb.version` artmalı (beklenen; uygulamaya alınırsa yapılacak).
* `source_priority_test` (10): kayıtlı kart anlamları (book, course), tekrar kartları (want, course "golf sahası"),
  Türkçe eş anlamlı ve AI taslağı kuralları. Örnekler damdafayton anlamlarına dayanıyor.
* `review_quiz_test` (2): "simply" için "sadece" bekleniyor, adayda "basitçe" ilk anlam.
* `context_sense_test`, `context_sense_ui_test`: "know" için "tanımak" bekleniyor; adayda "bilmek, anlamak, haberi
  olmak" (damdafayton'un "tanımak"ı çıktı).
* `word_gaps_test`: "nThe market" onarılmadı. Onarım bir kelimenin sözlükte olup olmadığına bakıyor; büyük olasılıkla
  "the" `ft` satırını kaybettiği (WordNet'te de yok) için (neden ayrıca doğrulanmadı).

Bu testler **gevşetilmedi ve değiştirilmedi**. Aday uygulamaya alınacaksa her biri bir kalite kararıdır (anlam
gerçekten yanlış mı, yoksa güvenli kaynakta eksik mi?).

## Kalite örneklemi

Bağımsız kalite örneklemi (kişi değerlendirmesi) bu görevde yapılmadı: Türkçe anlam doğruluğunu bir kişinin
kontrol etmesi gerekir; AI değerlendirmesi doğrulama sayılmaz. Önerilen yöntem: kaybolan sık 500 kelimeden ve kalan
`ft` satırlarından tohumlu rastgele 200'er örnek, Hamit'in elle kontrol edeceği bir xlsx (`tools/contrib`
biçiminde); sonuçlar katkı olarak geri döner.
