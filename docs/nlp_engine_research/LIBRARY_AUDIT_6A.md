# Kitap denetimi ve sözlük boşluğu (Görev 6A)

## Kısaca

- Uygulamayla gelen 309 hikâyenin (CC BY 4.0) 12.090 cümlesinin hepsi motora okutuldu. Okunan anlamlar tek tek kontrol edildi.
- Kontrol sonucu `assets/library/verified_6a.json.gz` dosyasında (320 KB) tutuluyor. Bu hikâyelerde öğrenci artık kontrol edilmiş anlamı görüyor. Dosyada 8.391 cümle, 12.901 kelime kararı ve 5.363 deyim kararı var.
- Dosya yalnızca sözlükte zaten olan anlamlar arasından seçim yapar. Sözlüğe hiçbir Türkçe eklemez. `dict.db` ve `tr_en.db` değişmedi.
- Denetim sırasında iki gerçek hata bulundu ve düzeltildi:
  1. "king, boy, man, baby" gibi insan isimleri dilbilgisi kelimesi sayılıyordu. Bu yüzden kartta anlam çıkmıyordu.
  2. Anlam önbelleği, okuyucudaki cümlede bir kelimeye aynı cümlenin başka bir kelimesinin cevabını verebiliyordu. Örnek: "the" kelimesine "old" kelimesinin cevabı geliyordu. 113.462 kelimeden 232'si etkilenmişti.
- Sözlük boşluğu da listelendi. Hikâyelerde doğru anlamın sözlükte olduğu ama Türkçesinin olmadığı 1.561 anlam bulundu. Örnekler: friend, house, help, school. Bu anlamlar için Türkçe **taslaklar** hazırlandı (`tools/library_audit_6a/data/synset_tr_drafts_6a.tsv`). Taslaklar sözlüğe yazılmadı ve uygulamada gösterilmiyor. Bir insanın kontrolünü bekliyorlar.

## Yöntem

1. `tools/library_audit_6a/dump_6a_test.dart` her cümleyi bugünkü okuyucuyla ve 5N cümle motoruyla okur. Kelime başına aday anlamların hepsini kimlikleriyle birlikte yazar.
2. `make_items.py` kontrol edilecek maddeleri seçer:
   - Bütün deyim adayları.
   - İki motorun ayrıştığı bütün kelimeler.
   - İki motorun anlaştığı kelimelerin %12'si (sabit, tekrar üretilebilir bir örneklem).
3. Claude ajanları her maddeyi `AUDIT_SPEC.md` kurallarıyla etiketledi. Her kelime için cevap dört türden biridir:
   - Uyan anlam (bir seçenek numarası).
   - "Sözlükte uyan anlam yok".
   - "Deyimin parçası".
   - "Özel isim".

   Deyimler için cevap, "deyim olarak mı kullanılmış, ayrı kelimeler olarak mı" sorusudur.
4. `build_overlay.py` cevapları uygulamanın dosyasına ve istatistiklere çevirir. `carry_answers.py` önbellek düzeltmesinden sonra değişmeyen maddelerin cevaplarını taşıdı. Taşınan cevap sayısı 9.649. Kalan 16.274 madde yeniden etiketlendi.

Uygulamada kuralın nasıl işlediği (`lib/nlp/verified_readings.dart`, `SenseEngine._applyVerified`) aşağıda.

**Kelimeler**

| Kontrol sonucu | Uygulamada ne olur |
|---|---|
| Uyan anlamın kendi Türkçesi var | Bu anlam "kesin" gösterilir. Türkçe türetilmiş ya da doğrulanmamışsa en fazla "muhtemel" gösterilir. |
| Sözlükte uyan anlam yok | Hiçbir anlam cevap olarak gösterilmez ("-"). |
| Uyan anlamın Türkçesi yok | Motorun cevabı kalır, ama asla "kesin" gösterilmez ("~"). Örnek: "School is over" cümlesinde "okul". |
| Motorun hiç düşünmediği bir kimlik | Hiçbir şey değişmez. |

**Deyimler**

| Kontrol sonucu | Uygulamada ne olur |
|---|---|
| Ayrı kelimeler olarak kullanılmış | Altı çizilmez ve dokununca deyim kartı açılmaz. |
| Deyim olarak kullanılmış | Kontrol edilen anlamı gösterilir. |

Dosya yoksa ya da bozuksa okuyucu eskisi gibi çalışır. Kitaplar (içe aktarılan ve 91 hazır kitap) bu turda yok.

## Sonuçlar (hikâyeler)

**Deyimler**

| | Doğru | Yanlış gösterilen | Kaçırılan |
|---|---|---|---|
| Bugünkü okuyucu | 3.902 / 5.398 (%72) | 1.157 | 339 |
| 5N motoru | 4.137 / 5.508 (%75) | 241 | 1.130 |

**Kelimeler**

- İki motorun anlaştığı kelimelerin yaklaşık %82'si doğru.
- İki motorun ayrıştığı kelimelerde bugünkü panel yaklaşık %37, 5N yaklaşık %62 doğru.
- Ağırlıklı tahmin: bugünkü okuyucu yaklaşık %62, 5N yaklaşık %73 doğru. Kontrol dosyası eklenince bu hikâyelerde oran yaklaşık %90 olur. Bu bir tahmindir, çünkü anlaşılan kelimelerin yalnızca bir örneklemi okundu.

`check_overlay_6a_test.dart` dosyanın gerçekten uygulandığını kontrol eder:

- Kelimeler: 12.901 karardan 12.899'u uygulandı. 10.944'ü "kesin", 1.622'si "muhtemel" gösteriliyor. 333'ünde anlam gösterilmiyor.
- Deyimler: 5.363 kararın 5.309'una okuyucu ulaşıyor.

## Sözlük boşluğu

5N'nin "uyan anlam yok" dediği 1.089 kelime şöyle dağılıyor:

| Durum | Sayı |
|---|---|
| Doğru anlam WordNet'te var ama Türkçesi yok | 535 (%49) |
| Türkçe başka bir tanımın altında zaten vardı | 89 (yalnızca 9'u 6 seçenek sınırı yüzünden kesilmişti) |
| Bir deyimin parçası | 232 |
| Gerçekten eksik anlam | 139 |
| Özel isim | 59 |
| Diğer | 35 |

Hikâye denetiminde bulunan boşluklar şunlar. Hepsi `data/story_gaps_6a.tsv` dosyasında.

- Uyan anlamı olan ama o anlamın Türkçesi olmayan 4.214 kelime kullanımı. Bu kullanımlar 1.561 farklı anlama karşılık geliyor.
- Sözlükte hiç olmayan 399 anlam.
- Deyim olarak kullanılmış ama anlamı sözlükte olmayan 105 deyim.
- 192 "diğer" madde. Bunların çoğu motorun yanlış öbek fiil başı seçmesi, örneğin fell → "fall on" ve put → "put in". Bu hata **düzeltilmedi**, yalnızca raporlandı.

### Türkçe taslaklar

`data/synset_tr_drafts_6a.tsv` dosyasında 1.561 satır var. Her satırda şunlar bulunuyor:

- Anlam kimliği, kelime, tür ve hikâyelerdeki kullanım sayısı.
- İngilizce tanım ve Türkçe taslak.
- Bir örnek cümle.
- `reviewed=no`.

Taslakları Claude yazdı. 8 satır "emin değilim" olarak işaretli. Bu satırlar sözlüğe yazılmadı ve uygulamada gösterilmiyor. Bir insan kontrol ettikten sonra ayrı bir görevde, kaynak notuyla birlikte sözlüğe alınabilirler. Sözlüğe almak için `dict.db` değişikliğine açık onay gerekir.

## İkinci göz kalite kontrolü

Ana etiketlerden 400 madde (300 kelime, 100 deyim) ayrı bir ajana ana cevaplar gösterilmeden verildi.

| | Aynı cevap |
|---|---|
| Kelimeler | 269 / 300 (%90) |
| Deyim mi, ayrı kelimeler mi | 98 / 100 |
| Deyimin hangi anlamı | 41 / 42 |

Ayrışmaların çoğu birbirine çok yakın WordNet anlamları arasında. Örnekler: "things", "day", "party". 10 kelimede bir göz "uyan anlam var", öteki "yok / deyimin parçası" dedi. Buna göre kelime kararlarının yaklaşık onda biri tartışmalı sayılmalı. Bu durum "kesin" etiketinin her zaman doğru olmadığı anlamına gelir; ileride insan kontrolüyle iyileşir. Ham sonuç `data/qc_answers_6a.jsonl` dosyasında.

## Sınırlar

- Etiketleri Claude ajanları verdi. Bir insan bunları kontrol etmedi. İkinci göz kontrolü yalnızca 400 maddelik bir örneklem üzerinde yapıldı.
- İki motorun anlaştığı kelimelerin yalnızca %12'si okundu. Kalan anlaşılan kelimeler kontrol edilmedi ve motorun cevabı olduğu gibi kalıyor.
- Kontrol yalnızca birebir aynı cümleye uygulanır. Hikâye metni değişirse o cümlenin kararı kullanılmaz.
- Kitaplar bu turda yok. 91 kitap 277 bin cümle içeriyor; bu sonraki tura kaldı.
- Öbek fiil başı hatası düzeltilmedi.

## Lisans

- Hikâyeler CC BY 4.0 lisanslı.
- Kontrol dosyası yalnızca cümle metnini (anahtar olarak) ve sözlükte zaten olan aday kimliklerini içerir. Yeni sözlük içeriği yoktur. Bu yüzden #114 lisans ve kaynak kapısı etkilenmez.
- Türkçe taslaklar yapay zekâ üretimidir ve öyle işaretlenmiştir.

## Veri bütünlüğü

| Dosya | SHA-256 (önce ve sonra aynı) |
|---|---|
| `assets/dict.db` | `ab4a7a53b9fc5e1edbd682da5cb7193c0c109f93236655385bf6231d90221a9c` |
| `assets/tr_en.db` | `49a661b9c8951259ab13fd6a95aa77b68e16f1c4716669dacfb6c12521cfa818` |

## Testler

`test/verified_readings_6a_test.dart` dosyasında 7 test var:

- Kontrol edilmiş anlam cevap olur.
- "-" işareti ve bilinmeyen bir kimlik beklendiği gibi davranır.
- Ayrı kelimeler olarak işaretlenmiş deyim literal sayılır.
- Bozuk dosya, kontrol edilmiş okuma olmadığı anlamına gelir.
- İnsan isimlerinin anlamı çıkar, zamirler dilbilgisi kelimesi olarak kalır.
- Önbellek hatası için regresyon testi. Bu test eski anahtarla başarısız oluyor: "the" yerine "old" geliyor.
- Uygulamayla gelen dosyayla "The dog sees a bird." cümlesindeki "sees" kelimesi "görmek" ve "kesin" olarak okunuyor.

Tam takım (`flutter test`, önbellek düzeltmesinden sonra): 644 geçti, 12 atlandı, 3 başarısız. Başarısız olan 3 test `text_repair_test`, `picture_book_test` ve `import_completeness_test`. Üçü de bilinen ortam hatası: bu makinede PDFium kütüphanesi yok, bu yüzden `setUpAll` aşamasında düşüyorlar. Bu hata değişikliklerden önce de vardı.

`flutter analyze` değişen dosyalarda yeni bir uyarı vermedi. Çıkan 2 bilgi notu, var olan `material.dart` kullanımdan kalkma notu.
