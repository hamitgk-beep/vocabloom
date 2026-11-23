# Görev 5N: Cümleyi kalıplarına bölen ve anlam veren motor

## Kısaca

`SentenceEngine.analyze(cümle)` bir cümleyi tek seferde parçalarına ayırır: her kelime ya bir kalıbın içindedir ya
da tek başınadır. Her parçanın bu cümledeki Türkçe anlamını, cümlenin dil bilgisi işaretleriyle birlikte verir.
Karar artık tek tek kurallarla (yamalarla) değil, cümlenin tamamını okuyan iki küçük modelle veriliyor:

1. **Kalıp mı, düz anlam mı?** "He kicked the bucket last winter" → *nalları dikmek*; "The boy kicked the bucket
   across the yard" → kalıp yok, *tekmelemek + kova*.
2. **Bu kelimenin hangi anlamı?** "The car ran into a tree" → *car: araba* (eskiden *kabin*).

İkisi de aynı küçük model türü (4 katmanlı BERT, 11 MB). Uygulamanın içinde **saf Dart** ile çalışıyor: ek
kütüphane yok, internet yok, her platformda aynı sonuç. Python'daki modelle birebir aynı sayıları veriyor (test var).

## Ölçümler (hepsi gerçekten çalıştırıldı)

### Kalıp mı, düz anlam mı?

İnsan etiketli MAGPIE test kümesi (modelin **hiç görmediği** 306 deyim; bu kümeden eğitimde hiçbir şey yok):

| | doğruluk | düz anlamı yakalama | deyimi yakalama | yanlış gösterilen kalıp | kaçırılan deyim |
|---|---|---|---|---|---|
| mevcut motor | %73,8 | %20,7 | %94,2 | 753 / 949 | 143 / 2.466 |
| **yeni motor** | **%84,7** | **%65,4** | %92,1 | **328 / 949** | 194 / 2.466 |

(Aynı 3.415 örnek; mevcut motorun aday bulduğu örnekler. Model seçimi kitap cümlelerinin ayrılmış kısmıyla yapıldı,
test kümesiyle değil.) Yani öğrenciye yanlış kalıp gösterme %56 azaldı; buna karşılık 51 deyim daha kaçıyor.

Telifsiz kitap cümlelerinin ayrılmış %15'i (1.478 aday, etiket: Claude): yeni %81,8, mevcut %69,6.

### Kelime anlamı

Kitap cümlelerinden 1.518 test kelimesi (etiket: Claude; birden çok anlamı olan kelimeler):

| | doğru anlam |
|---|---|
| mevcut SenseEngine | %57,1 |
| ilk anlam | %55,5 |
| **yeni model** | **%71,1** |

Önemli bulgu: bu kelimelerin **%18'inde sözlükteki seçeneklerin hiçbiri** cümledeki anlama uymuyor (ör. "form an
alliance"). Bunu hiçbir seçici düzeltemez; sözlük tarafında bir iş.

Not: anlam sırasına verilen küçük ağırlık (0,1) bu test kümesinde üç değer arasından seçildi; küçük bir iyimserlik
payı olabilir. Kalıpların kendi anlamları (ör. *go back*: geri dönmek / geçmişe dayanmak) için de aynı model
kullanılıyor; bu kısım ayrıca ölçülmedi, örneklerde iyileşme görüldü.

## Gerçek çıktı

- [ornek_cumleler.md](nlp_5n_results/ornek_cumleler.md): 26 deneme cümlesi.
- [ornek_hikayeler.md](nlp_5n_results/ornek_hikayeler.md): uygulamanın kendi hikâyelerinden (eğitimde kullanılmadı) 25 cümle.

Uygulamanın 120 hikâye cümlesinde eski ve yeni motor 21 cümlede farklı kalıp gösterdi. Yanlış olanlar gitti
("in the refrigerator = garanti olmak", "sit on = ertelemek", "turn someone's head"); doğrusu geldi ("turned her head
away" → *turn away*, "go back to school" → *geri dönmek*). Yeni hata da var: "Ballu fell down with the kite" artık
*fall down* göstermiyor.

Hâlâ yanlışlar var (dürüst liste): "Blacky" (cümle başındaki isim) → *zenci*; "sinks" → *lavabo*; "smoking" →
*tüten*; "better" → *tam, dolu*; "home" → *ev ile ilgili*; "I looked up the word" artık *look up* göstermiyor (0,28).
Bunların çoğu sözlükte doğru seçeneğin olmaması ya da kelime türünün (fiil/isim) yanlış okunması.

## Eğitim verisi ve lisans

Hiçbir korpusun cümlesi modelde yok; hepsi ticari kullanıma açık:

- 6.285 karşıt cümle: 1.200 kalıp için bu proje için yazıldı (aynı kalıp bir deyim, bir düz anlamda).
- 9.763 kalıp adayı: Project Gutenberg kitaplarından (kamu malı) 29.030 cümle; her aday "kalıp / düz" diye etiketlendi.
- 6.307 kelime: aynı kitaplardan; her kelimenin uyan sözlük anlamı seçildi.
- WordNet'in kendi örnek cümleleri (dict.db içinde; WordNet lisansı ticari kullanıma izin verir, bildirim ister).
- Temel model google/bert_uncased_L-4_H-256_A-4 (Apache-2.0).
- MAGPIE (BNC cümleleri) yalnızca ölçmek için kullanıldı, modele girmedi.

Etiketler Claude ajanlarından; insan kontrolü yok. Rastgele örneklerde kalite iyi görünüyor, ama etiket hataları var.
Eğitim betikleri ve veriler `tools/sentence_engine_5n/` altında.

## Hız ve boyut

- İki model, 11,7 MB + 11,7 MB (`assets/models/`). Henüz `pubspec.yaml`'a eklenmedi; uygulama boyutu değişmedi.
- Test ortamında (JIT) cümle başına ~0,5–0,8 saniye, çoğu kelime anlamı modelinden. Cümle başına bir kez
  hesaplanıp saklanıyor. Telefonda ölçülmedi.

## Değişmeyenler

- `assets/dict.db`, `assets/tr_en.db`, kullanıcı verisi: dokunulmadı.
- Tam test takımı: 637 geçti, 3 dosya bu ortamda PDF kütüphanesi (libpdfium) olmadığı için başlayamadı (motorla ilgisiz). `flutter analyze`: yeni dosyalarda sorun yok.
- Okuyucudaki mevcut alt çizgi ve kartlar: değişmedi. Yeni motor şimdilik yalnızca testler ve demo aracında
  çalışıyor. Okuyucuya bağlamak (ve modelleri uygulamaya koymak, +23 MB) sonraki adım.

## Dosyalar

- `lib/nlp/cross_encoder.dart`: küçük BERT, saf Dart (tokenizer + ileri geçiş, int8 ağırlık).
- `lib/nlp/sentence_engine.dart`: motor (adaylar, kalıp kararı, en iyi örtüşmesiz kalıp seti, kelime anlamları, dil bilgisi).
- `assets/models/expr_context_5n.bin`, `assets/models/word_sense_5n.bin`.
- `test/sentence_engine_5n_test.dart`: Dart = Python kontrolü, deyim/düz örnekleri, her kelime bir parçada.
- `tools/sentence_engine_5n/`: demo, aday ve kelime dökümü, dışa aktarma, eğitim betikleri, veriler.
