# Kitap denetimi ve sözlük boşluğu (Görev 6A)

## Kısaca

- Uygulamayla gelen 309 hikâyenin (CC BY 4.0) 12.090 cümlesinin hepsi motora okutuldu. Okunan anlamlar tek tek kontrol edildi.
- Kontrol sonucu `assets/library/verified_6a.json.gz` dosyasında (340 KB) tutuluyor. Bu hikâyelerde öğrenci artık kontrol edilmiş anlamı görüyor. Dosyada 8.817 cümle, 14.764 kelime kararı ve 5.363 deyim kararı var (2. turdan sonra).
- Kontrol dosyası yalnızca sözlükte zaten olan anlamlar arasından seçim yapar; kendisi Türkçe eklemez.
- Denetim sırasında iki gerçek hata bulundu ve düzeltildi:
  1. "king, boy, man, baby" gibi insan isimleri dilbilgisi kelimesi sayılıyordu. Bu yüzden kartta anlam çıkmıyordu.
  2. Anlam önbelleği, okuyucudaki cümlede bir kelimeye aynı cümlenin başka bir kelimesinin cevabını verebiliyordu. Örnek: "the" kelimesine "old" kelimesinin cevabı geliyordu. 113.462 kelimeden 232'si etkilenmişti.
- Sözlük boşluğu da listelendi. Hikâyelerde doğru anlamın sözlükte olduğu ama Türkçesinin olmadığı 1.561 anlam bulundu. Örnekler: friend, house, help, school. Bu anlamlar için Türkçe taslaklar hazırlandı (`tools/library_audit_6a/data/synset_tr_drafts_6a.tsv`).
- **2. tur (Hamit'in onayıyla):** taslaklardan 649'u bütün şartları geçti ve `dict.db`'ye yazıldı. Kütüphaneye 10 yeni kitap eklendi (91 → 101). Öbek fiil başı hatası düzeltildi. Ayrıntılar aşağıda, "2. tur" bölümünde.

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

- Kelimeler: 1. turda 12.901 karardan 12.899'u uygulandı (10.944 "kesin", 1.622 "muhtemel", 333'ünde anlam gösterilmiyor). 2. turda, yeni Türkçelerle, 14.764 karardan 14.631'i uygulandı (13.731 "kesin", 567 "muhtemel", 333'ünde anlam gösterilmiyor).
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

## 2. tur: doğrulanan Türkçeler sözlüğe (24 Kasım)

Hamit şunu istedi: anlamı olmayan kelimelerin taslak Türkçeleri doğruysa ve iki üç farklı cümlede doğrulanıyorsa sözlüğe kaydedilsin. Gerekirse kütüphanedeki kitap sayısı artırılsın.

### Şartlar

Bir anlamın Türkçesi ancak bu şartların hepsini geçerse sözlüğe yazıldı:

1. **Açık sözlükte de var.** Taslaktaki Türkçe, o kelime için `ft` tablosundaki insan yapımı açık sözlüklerde de geçiyor (Wiktionary, damdafayton). `tools/main_meanings.py` her WordNet anlamına bu kuralı uygular. Ayrıca taslağın **ilk (ana) Türkçesi** bu sözlüklerde olmalı. Sadece ikinci planda bir kelimesi tutan 56 anlam alınmadı. Örnek: "river bank" için "kıyı" yoktu, yalnızca "kenar" vardı.
2. **En az iki farklı cümlede doğrulandı.** Kelime, kütüphanedeki en az iki ayrı cümlede bu anlamda kullanılıyor (hikâyeler ve kitaplar). Her cümlede anlam **körlemesine** seçildi: ajan, kelimenin bütün WordNet anlamlarını gördü, hedef anlamın hangisi olduğunu bilmedi.
3. **İkinci, ayrı kontrol.** Ayrı bir ajan cümleleri ve Türkçeyi birlikte okudu. Yalnızca bu cümlelerde doğru ve doğal olan Türkçeleri bıraktı.
4. Taslak "emin değilim" olarak işaretlenmemiş.

| Adım | Anlam |
|---|---|
| Taslak | 1.561 |
| Açık sözlükte de var, emin değilim yok | 1.256 |
| En az 2 cümlede doğrulandı | 804 (hikâyeler + 91 kitap: 732; 10 yeni kitapla: +72) |
| İkinci kontrolü geçti | 705 |
| Ana Türkçesi de açık sözlükte var → **sözlüğe yazıldı** | **649** |

Her satırın kanıtı `tools/library_audit_6a/data/syn_tr_6a_evidence.jsonl` dosyasında: Türkçe, taslak, cümle sayıları ve örnek cümleler. Taslak listesinde (`synset_tr_drafts_6a.tsv`) her satırın sözlüğe girip girmediği ve girmediyse nedeni yazıyor. 452 anlam ikinci cümleyi bulamadığı için girmedi; bunların çoğu nadir anlamlar.

### Sözlüğe nasıl yazıldı

- Türkçeler `tools/data/syn-claude-6a.jsonl.gz` dosyasında. Bu, `tools/pretranslate.py` sonuçlarıyla aynı biçim. Böylece `tools/build_dict.py` sözlüğü baştan kurarken bu dosyayı da okur; bu yol daha önce `syn-claude.jsonl.gz` için de kullanılıyordu.
- Mevcut `assets/dict.db` dosyasına `tools/library_audit_6a/apply_tr_6a.py` yazdı. Yalnızca Türkçesi boş olan (`tr` NULL veya `[]`) 649 `syn` satırı değişti.
- Önce ve sonra bütün tablolar karşılaştırıldı: başka hiçbir satır ya da sütun değişmedi. `integrity_check` sonucu `ok`.
- Sözlük sürümü `DictDb.version` 36'dan 37'ye çıktı. Bu sayede cihazlar yeni sözlüğü kopyalar (`test/fixtures/dict_db.stamp`).
- Kaynak kaydı: `tools/lexicon_provenance/inventory.py` bu 649 Türkçeyi KeNet'te olmayan, yapay zekâ ile doldurulmuş Türkçe olarak sayıyor (`ai_pretranslate`). Önceki kayıtlarda hiçbir şey değişmedi ve silinmedi. Yayın kapısındaki 1.205 "regression" satırı değişiklikten önce de vardı (Tatoeba örnekleri).
- Yan bulgu: `tools/main_meanings.py` iki harfli Türkçe kelimeleri ("ev", "su", "at") her zaman atıyordu. "House" için "ev" bu yüzden boştu. Kural düzeltildi: tam bir anlam her uzunlukta sayılır. Sözlük yeniden kurulduğunda bu satırlar da düzelir. Mevcut dosyada yalnızca bu turda doğrulanan anlamlar değişti.

Etkisi: hikâyelerde uyan anlamı olup Türkçesi olmayan kelime kullanımı 4.214'ten 1.364'e indi. Örnekler: friend → arkadaş, dost; house → ev; help → yardım etmek; school → okul.

Bu Türkçeler artık sözlüğün kendi Türkçesi gibi "kesin" gösterilebilir. Bunlara yapay zekâ karar verdi; bir insan gözden geçirmedi. Ancak her birinin Türkçesi bir insan yapımı açık sözlükte de bulunuyor.

### Kütüphaneye 10 yeni kitap

Kitaplar Project Gutenberg'den alındı (kamu malı, GITenberg aynası). Kütüphanedeki kitap sayısı 91'den 101'e çıktı.

| Kitap | Yazar | Seviye |
|---|---|---|
| The Princess and the Goblin | George MacDonald | B1 |
| Ozma of Oz | L. Frank Baum | B1 |
| Dorothy and the Wizard in Oz | L. Frank Baum | B1 |
| Rebecca of Sunnybrook Farm | Kate Douglas Wiggin | B1 |
| The Phoenix and the Carpet | E. Nesbit | B1 |
| At the Back of the North Wind | George MacDonald | B2 |
| Anne of Avonlea | L. M. Montgomery | B2 |
| The Prince and the Pauper | Mark Twain | B2 |
| Tales from Shakespeare | Charles ve Mary Lamb | B2 |
| Twenty Thousand Leagues under the Sea | Jules Verne | B2 |

- `tools/library/add_books.py`, yalnızca verilen kitapları `build_library.py` ile aynı yoldan işler. Gerekçe: tam kurulum için her kitabın HTML kopyası gerekir; o olmadan var olan kitapların resimlerini silerdi.
- Kitaplar `books.tsv` dosyasına da eklendi.
- Eklenmeyenler:
  - Doctor Dolittle kitapları: içerikteki ırkçı bölümler yüzünden.
  - The Marvelous Land of Oz ve The Red Fairy Book: bölümler düzgün ayrılamadı.
- Bu kitapların kontrol edilmiş okumaları henüz yok. Kitaplar şimdilik yalnızca sözlük doğrulaması için cümle kaynağı olarak kullanıldı.

### Öbek fiil başı düzeltmesi

Ayrık öbek fiil kuralı (`_separable`) artık 5M yapı ayrıştırıcısının kuralını izliyor:

- Parçacık, cümleciği kapatmalı.
- Kelimenin önünde belirleyici olmamalı.
- Arada edat ya da yeni cümlecik olmamalı.

Örnek: "The elephant carried the princess on his back" artık "carry on" olarak okunmuyor; "Please turn the light off." yine "turn off" olarak okunuyor.

Bu turda ikinci bir küçük kural eklendi. Seçilen anlamın Türkçesi ilk anlamın Türkçesiyle aynı fiilden geliyorsa (durmak / durdurmak), seçim "ilk anlam değil" diye "muhtemel"e düşürülmüyor. Bu kural eklenmeden "Please stop the car." cümlesi, "durmak" eklenince "muhtemel"e düşüyordu.

## Sınırlar

- Etiketleri Claude ajanları verdi. Bir insan bunları kontrol etmedi. İkinci göz kontrolü yalnızca 400 maddelik bir örneklem üzerinde yapıldı.
- İki motorun anlaştığı kelimelerin yalnızca %12'si okundu. Kalan anlaşılan kelimeler kontrol edilmedi ve motorun cevabı olduğu gibi kalıyor.
- Kontrol yalnızca birebir aynı cümleye uygulanır. Hikâye metni değişirse o cümlenin kararı kullanılmaz.
- Kitapların kontrol edilmiş okumaları yok. Kitaplar (101 kitap, yaklaşık 300 bin cümle) yalnızca sözlük doğrulamasında cümle kaynağı oldu. Hepsini tek tek etiketlemek bu yöntemle çok büyük bir iş; örnekleme ile yapılabilir.
- Sözlüğe yazılan 649 Türkçeyi bir insan gözden geçirmedi.

## Lisans

- Hikâyeler CC BY 4.0 lisanslı.
- Kontrol dosyası yalnızca cümle metnini (anahtar olarak) ve sözlükte zaten olan aday kimliklerini içerir. Yeni sözlük içeriği yoktur. Bu yüzden #114 lisans ve kaynak kapısı etkilenmez.
- Türkçe taslaklar yapay zekâ üretimidir ve öyle işaretlenmiştir.

## Veri bütünlüğü

| Dosya | Önce | Sonra |
|---|---|---|
| `assets/dict.db` | `ab4a7a53b9fc5e1edbd682da5cb7193c0c109f93236655385bf6231d90221a9c` | `84a0b2c6c8e34d14467fbb12184a74db9ec10dcd55a6dbe91d0ef4884e2531df` (2. tur: 649 `syn.tr` satırı) |
| `assets/tr_en.db` | `49a661b9c8951259ab13fd6a95aa77b68e16f1c4716669dacfb6c12521cfa818` | aynı |

1. turda `dict.db` değişmedi. 2. turda Hamit'in onayıyla yalnızca Türkçesi boş olan 649 satır doldu. Sözlükteki satır sayıları aynı kaldı (syn: 117.659). Türkçesi olan anlam sayısı 14.171'den 14.820'ye çıktı.

## Testler

`test/verified_readings_6a_test.dart` dosyasında 7 test var:

- Kontrol edilmiş anlam cevap olur.
- "-" işareti ve bilinmeyen bir kimlik beklendiği gibi davranır.
- Ayrı kelimeler olarak işaretlenmiş deyim literal sayılır.
- Bozuk dosya, kontrol edilmiş okuma olmadığı anlamına gelir.
- İnsan isimlerinin anlamı çıkar, zamirler dilbilgisi kelimesi olarak kalır.
- Önbellek hatası için regresyon testi. Bu test eski anahtarla başarısız oluyor: "the" yerine "old" geliyor.
- Uygulamayla gelen dosyayla "The dog sees a bird." cümlesindeki "sees" kelimesi "görmek" ve "kesin" olarak okunuyor.

2. turda eklenen test: kendi isim öbeği olan parçacık ayrık öbek fiil sayılmıyor (8 testin hepsi geçti).

İki eski testin beklentisi yeni Türkçeye göre güncellendi:
- `review_quiz_test`: "simply" artık "sadece" olarak notlanıyor, çünkü anlamın Türkçesi var.
- `idiom_confidence_5f_test`: "circle" kelimesinin artık Türkçesi olduğu için test öncülü bu deyimde atlanıyor. Deyimin "kesin" gösterilmemesi kontrolü yerinde.

2. tur sonrası tam takım: 645 geçti, 12 atlandı, 3 başarısız (aynı 3 PDFium testi).

1. tur tam takım (`flutter test`, önbellek düzeltmesinden sonra): 644 geçti, 12 atlandı, 3 başarısız. Başarısız olan 3 test `text_repair_test`, `picture_book_test` ve `import_completeness_test`. Üçü de bilinen ortam hatası: bu makinede PDFium kütüphanesi yok, bu yüzden `setUpAll` aşamasında düşüyorlar. Bu hata değişikliklerden önce de vardı.

`flutter analyze` değişen dosyalarda yeni bir uyarı vermedi. Çıkan 2 bilgi notu, var olan `material.dart` kullanımdan kalkma notu.
