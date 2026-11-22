# spaCy değerlendirmesi (Görev 5E, Aşama 2)

Tarih: 22 Kasım 2026. spaCy 3.8.18; modeller `en_core_web_sm`, `en_core_web_md`, `en_core_web_trf` 3.8.0 (MIT).
Betik: `tools/nlp_research/spacy_eval.py`, `tools/nlp_research/pos_perceptron.py`, `tools/nlp_research/pos_for_rows.py`.

## 1. Neyi ölçtük

- **Aynı belirteçler üzerinde** spaCy ile Storilex'in kendi analizini karşılaştırdık: UD English-EWT train
  örneklemi (her 4. paragraf; 616 paragraf, 45.167 kelime). spaCy'nin İngilizce modelleri OntoNotes ile
  eğitildi, EWT'yi görmedi.
- Final ölçüm hiç kullanılmamış iki ağaç bankasında: **UD English-PUD** ve **GENTLE** (1.059 belge;
  `BENCHMARK_RESULTS.md` §2).
- Storilex'in sözcük türü yalnız "gösterilen anlamın türü" olarak vardır (isim / fiil / sıfat / zarf); bu yüzden
  karşılaştırma iki türlü yapıldı: (a) kelimenin altın UPOS etiketi, (b) **sistem B**: motorun kendi aday anlamları
  arasından spaCy'nin dediği türdeki anlamın seçilmesi.

## 2. Geliştirme sonuçları (EWT train örneklemi)

| ölçüm | Storilex (main) | spaCy sm | spaCy md | spaCy trf | EWT perceptron (bizim, saf Dart'a uygun) |
|---|---|---|---|---|---|
| Belirteç sınırları (yazılı kelime aynı yerde) | – (5B: %99+) | %98,0 | %98,0 | %98,0 | – (UD belirteçleri kullanır) |
| Cümle sınırı P / R | (GUM'da ölçüldü) | %92,9 / %86,6 | %90,9 / %86,9 | %95,4 / %88,5 | – |
| UPOS doğru (isim/fiil/sıfat/zarf) | – | %90,9 | %91,3 | %93,3 | %92,7 |
| Kök (isim/fiil/sıfat/zarf) | %95,6 | %97,0 | %97,0 | %97,4 | – |
| İki+ türü olan kelimede doğru tür | – | %91,8 | %92,1 | %94,2 | %92,4 |
| **Gösterilen anlamın türü doğru** | **%86,1** | B: %95,8 | B: %95,8 | B: %97,2 | B: %94,6; motorun içinde: **%93,8** |
| **"Kesin" ama türü yanlış** | **%6,8** (267/3.902) | B: %1,0 | B: %1,2 | B: %0,8 | B: %1,8; motorun içinde: **%3,4** (120/3.513) |
| Özel ad yakalama (PROPN ya da varlık) | – | %94,2 | %95,1 | %95,6 | – |
| Hız (bu makine, 4 çekirdek, Python) | – | 1,5 ms/cümle | 1,6 ms/cümle | 18,6 ms/cümle | 0,25 ms/cümle (Python), 0,13 ms (Dart) |
| Boyut | – | 15 MB | 57 MB | 501 MB | **0,9 MB** |
| Bellek (süreç tepe RSS) | – | ≈1,0 GB* | ≈1,3 GB* | ≈3,7 GB* | birkaç on MB |

\* Python + PyTorch süreci; modelin kendi ihtiyacı daha küçüktür ama mobilde Python yok.

"B" satırları sonradan uygulanan basit bir kuraldır (spaCy'nin türündeki en iyi aday seçilir, tür değişirse
"olası"). "Motorun içinde" ise etiketleyicinin motorun kendi karar zincirine girdiği deneysel entegrasyondur
(`SenseEngine(tagger: …)`): etiket türü seçer, ama tek başına "kesin" için kanıt sayılmaz (zayıf kural).

**Önemli bir geliştirme bulgusu:** etiketleyici ilk denemede "güçlü kural" sayılınca daha çok anlam "kesin" oldu ve
SemCor'da *yanlış anlamın kesin gösterilmesi* arttı (%13,8 → %16,5; %17,6 → %22,6). Zayıf kural yapılınca bu düzeldi
(%12,1; %17,6) ve tür doğruluğu yine %93,8 kaldı. Final ölçümde bu ikinci hâli kullanıldı.

### Bağlamsal anlama etkisi (SemCor / SemEval-07 geliştirme)

Doğru tür, doğru anlam demek değil: SemCor'da motorun hatalarının çoğu aynı türün içindeki anlamlar arasında.
Etiketleyiciyle Türkçe doğruluk +1,8 ile +2,5 puan arttı (%78,6 → %80,9; %79,5 → %81,3; %65,0 → %67,5),
"kesin" Türkçe yanlışı aynı kaldı ya da azaldı (6/78 → 5/75; 6/67 → 6/63; 4/35 → 4/33). Küçük örneklemlerde bu
farklar anlamlı değildir.

## 2.1 Final (UD PUD + GENTLE, 1.059 belge, bir kez)

| ölçüm | Storilex (main) | motor + perceptron (G0) | spaCy sm (B) | spaCy md (B) | spaCy trf (B) |
|---|---|---|---|---|---|
| Gösterilen anlamın türü doğru | %85,3 | **%92,1** | %95,1 | %95,1 | %96,5 |
| "Kesin" ama türü yanlış | %6,8 (156/2.303) | **%3,7** (78/2.126) | %0,8 | %0,8 | %0,4 |
| Gösterilen anlamın kökü | %96,1 | **%97,2** | – | – | – |
| UPOS (isim/fiil/sıfat/zarf) | – | – | %87,2 | %87,7 | %92,5 |

GENTLE (yasa metni, şiir, tıp, ders programı, sözlük maddesi gibi alışılmadık türler) geliştirmeden zor; spaCy'nin UPOS'u %91 → %87 düştü.
Perceptron'lu motor geliştirmedekiyle aynı farkı korudu (+7 puan). Ayrıntı: `BENCHMARK_RESULTS.md` §4.

## 3. Mobil uygulamaya nasıl girebilir (dört seçenek)

| seçenek | uygulanabilirlik | karar |
|---|---|---|
| 1. spaCy'yi yalnız geliştirmede / veri hazırlamada kullanmak | Kolay. Sözlük örnek cümlelerinin, ücretsiz kütüphane kitaplarının etiketlenmesi gibi işler için uygun. | **Önerilir** (araç olarak). |
| 2. spaCy çıktısını çevrimdışı veri olarak hazırlamak | Yalnız önceden bilinen metinler için (ücretsiz kütüphane, sözlük örnekleri). Kullanıcının kendi içe aktardığı kitaplar cihazda işlenir; onlar için işe yaramaz. | Kısmi. |
| 3. spaCy modelini ONNX'e dönüştürmek | **Denendi, mümkün değil:** spaCy/thinc'in ONNX dışa aktarıcısı yok (thinc 8.3, spaCy 3.8 incelendi). sm/md modelleri thinc'in HashEmbed + CNN katmanları ve kural/tablo tabanlı kök bulucudan oluşur; trf modelinin yalnız RoBERTa gövdesi `torch.onnx` ile çıkarılabilir, spaCy'nin etiketleme/ayrıştırma başları çıkmaz. Elle yeniden yazmak gerekir. | Hayır. |
| 4. Mobil için küçük bir POS modeli | **Denendi ve çalışıyor:** UD English-EWT ile eğitilen ortalama perceptron (0,9 MB, saf Dart, yerel kod yok). spaCy md'ye 1–2 puan yakın. Python ile birebir aynı etiketleri verdiği doğrulandı (31.367/31.367 etiket). | **Deneysel entegrasyon adayı** (bayrak arkasında, kapalı). |

## 4. Kısıtlar

- Perceptron, UD belirteçlerine göre eğitildi; uygulamanın belirteçleri bazı yerlerde farklı ("don't" gibi).
  Etkisi motorun içindeki ölçüme dahildir (%93,8).
- Perceptron yalnız etiket verir; kök bulmaz. Kök için motorun kuralları %95,6; spaCy %97,0. Motorun içinde
  etiketleyiciyle **gösterilen anlamın kökü** %95,6 → %97,0'ye çıktı (doğru tür, doğru kökü de seçtiriyor).
- spaCy'nin bağımlılık ayrıştırması ve NER'i (özel adlar) mobil tarafa taşınamaz; özel ad sorunu için
  perceptron'un PROPN etiketi kullanılabilir, ama bu görevde ölçülmedi.
