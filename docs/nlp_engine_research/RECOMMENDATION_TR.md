# Öneri (Görev 5E ön araştırma)

Tarih: 22 Kasım 2026. Bütün sayılar yeni, bağımsız final kümesinden (bir kez çalıştırıldı); ayrıntı
`BENCHMARK_RESULTS.md`. Mobil cihazda ölçüm yapılmadı; mobil sayılar masaüstü ölçümünden tahmindir.

**Kısa cevap:** Üretime aday olan tek parça, bu görevde eğittiğimiz **küçük sözcük türü etiketleyicisi**
(0,9 MB, saf Dart). Sinir ağı modelleri ölçülebilir biçimde daha iyi (özellikle GlossBERT), ama hiçbirinin
lisansı/kaynağı ve boyutu bugün üretime uygun değil. spaCy mobilde çalışamaz.

## 1. Hangi model veya kütüphane seçildi?

- **Üretime aday:** EWT perceptron POS etiketleyicisi (`lib/nlp/pos_tagger.dart`), SenseEngine'in içinde "zayıf
  kural" olarak. Kodu PR'da, **bayrak arkasında ve kapalı** (uygulama etiketleyiciyi hiç vermiyor). Model dosyası
  depoya konmadı (lisans onayı bekliyor); `tools/nlp_research/pos_perceptron.py` ile yeniden üretilir.
- **Yalnız araştırma:** GlossBERT (en doğru), all-MiniLM-L6-v2 uzlaşma kapısı, ms-marco cross-encoder deyim vetosu.
- **Seçilmedi:** spaCy (Python; ONNX'e dönüştürülemiyor; geliştirme aracı olarak faydalı).

## 2. Neden?

Etiketleyici küçük, hızlı, internetsiz, yerel kod istemiyor, dağıtım hakkı açık (biz eğittik) ve finalde motoru
anlamlı biçimde iyileştirdi. Sinir ağı modelleri ya ticari kullanımı kısıtlayan veriyle eğitilmiş (MS MARCO), ya
kaynağı doğrulanamıyor (GlossBERT'in Hugging Face kopyası), ya da 23–110 MB ekliyor.

## 3. Ne kadar daha doğru?

| | A motor | G0 = motor + etiketleyici | E = + GlossBERT (araştırma) |
|---|---|---|---|
| Türkçe karşılık doğru | %68,8 | **%73,9** (+5,1; p = 0,003) | %84,9 (+16,1; p = 2·10⁻⁸) |
| Gösterilen anlamın türü doğru | %85,3 | **%92,1** (+6,8) | – |
| İlk anlamı seçmek (Türkçe) | %66,7 | motor ilk anlamı geçiyor | geçiyor |

## 4. Deyim hataları ne kadar azaldı?

Etiketleyici deyim hatalarını **değiştirmiyor** (düz → deyim %23,6). Araştırma vetosu (ms-marco) düz cümlelerin
deyim sanılmasını **%23,6 → %13,6**'ya indirdi (26 → 15 cümle), ama deyimlerin dörtte birini kaçırdı (recall
%71,7 → %53,3). Recall korunmadığı için önerilmiyor. Araya kelime girmiş ve iyelikli deyimlerin hiçbiri
bulunamıyor: bu, sınıflandırıcının değil eşleştiricinin işi.

## 5. Yanlış kesinlik oranı nedir?

| | "kesin" ama yanlış anlam (tüm satırlara oranla) | "kesin" Türkçe yanlışı (katı) | elle eşanlamlara bakınca |
|---|---|---|---|
| A motor | %19,1 | 17/125 = %13,6 | ≈ %9–10 |
| G0 | %16,7 | 13/119 = %10,9 | (bakılmadı) |
| G (+ MiniLM kapısı, araştırma) | %10,5 | 3/73 = %4,1 | 2/73 = %2,7 |
| E (+ GlossBERT, araştırma) | %9,9 | 1/85 = %1,2 | 0–1/85 |

"%5'in altı" hedefine yalnız model kapılı araştırma sistemleri ulaşıyor; G0 bugünkü motordan iyi ama hedefin
üstünde. Elle kontrol Claude'un değerlendirmesidir. Ayrıca motorun 3 düz cümlede deyimi "kesin" gösterdiği
bulundu (sözcük sözcük adayı olmayan deyimlerde 5B kuralı çalışmıyor).

## 6. Boyutu kaç MB?

Etiketleyici **0,9 MB**. (Araştırma modelleri int8: MiniLM 22,9 MB, ms-marco 23,1 MB, GlossBERT 110 MB.)
ONNX Runtime zaten uygulamada (sherpa-onnx), ek altyapı boyutu yok.

## 7. Windows / Android / iOS performansı?

Etiketleyici saf Dart: masaüstünde cümle başına 0,13 ms, kelime çözümü 1,6 → 1,7 ms. Android/iOS'ta birkaç kat
yavaş olsa da fark edilmez (tahmin; cihazda ölçülmedi). Araştırma modelleri int8 ile masaüstünde çift başına
3,5–4 ms (MiniLM, ms-marco), GlossBERT ≈ 15 ms; telefonda 2–4 kat yavaş beklenir. Bu bulut ortamında Windows,
Android ve iOS cihazı olmadığı için **cihaz ölçümü yapılamadı**.

## 8. İnternetsiz çalışıyor mu?

Evet. Etiketleyici de, denenen bütün modeller de cihazda çalışır; ölçümlerde hiçbir metin dışarı gönderilmedi.

## 9. Lisans uygun mu?

- Etiketleyici: eğitim verisi UD English-EWT (CC BY-SA 4.0). Ağırlıklar uyarlama sayılabilir: atıf + aynı lisans;
  CC BY-SA 4.0 → GPLv3 tek yönlü uyumlu. **5C (lisans) görevinin onayı gerekir.**
- MiniLM ve ms-marco: ağırlık Apache-2.0, ama eğitim verisinde MS MARCO (yalnız ticari olmayan araştırma): **hayır**.
- GlossBERT: MIT, SemCor; ama Hugging Face kopyasının özgün olduğu doğrulanamıyor: **hayır**.
- Tablo: `MODEL_LICENSE_MATRIX.md`.

## 10. Kullanıcıya etkisi ne olur?

Bayrak açılırsa: dokunulan kelimenin türü daha sık doğru olur ("works hard" gibi isim/fiil/sıfat karışıklıkları
azalır), Türkçe karşılık yaklaşık her 20 kelimeden birinde daha doğru olur, yanlış "kesin" gösterimler biraz azalır.
Arayüz, kayıtlı kelimeler, okuma ilerlemesi ve sözlük değişmez. Bayrak kapalıyken (bugünkü hâl) hiçbir şey
değişmez.

## 11. Entegrasyon zorluğu?

Etiketleyici için düşük: model dosyasını varlık olarak eklemek, açılışta `PosTagger.load` ile yüklemek ve
`SenseEngine(..., tagger: t)` vermek; yüklenemezse bugünkü kurallar çalışır (testli). ≈ 1 gün + 5C onayı + cihaz
testi. Bir sinir ağı modeli için: Dart belirteçleyici ve ONNX çağrısı hazır (ölçüm betiğinde), isolate, isteğe
bağlı indirme paketi ve int8 eşiklerinin yeniden doğrulanması: ≈ 1 hafta, **ama önce lisansı temiz bir model
gerekir** (öneri: MIT tabanlı küçük bir modeli SemCor + WordNet + EWT ile kendimiz eğitmek, GlossBERT yöntemiyle).

## 12. Neler henüz üretime alınmamalı?

- Hiçbir sinir ağı modeli (MiniLM, ms-marco, GlossBERT, bge, nli-deberta): lisans/kaynak ve boyut.
- ms-marco deyim vetosu: lisans + deyimlerin dörtte birini kaçırıyor.
- Deyim sınıflandırıcısı (lojistik regresyon): beş model istiyor; BNC'den türetilmiş ağırlık 5C'de netleşmeli.
- spaCy: mobilde çalışmaz.
- Etiketleyici bayrağı da **5C lisans onayı ve gerçek cihaz testi gelmeden açılmamalı.**

## Bu PR'da ne var, ne yok

- Var: belgeler, `tools/nlp_research/` ölçüm betikleri, `lib/nlp/pos_tagger.dart` ve SenseEngine'de isteğe bağlı
  `tagger` parametresi (varsayılan: yok), `test/pos_tagger_test.dart` (7 test).
- Yok: model dosyası, değerlendirme verisi (BNC/MAGPIE cümleleri, WSD verisi, GENTLE), sözlük ya da kullanıcı
  verisi değişikliği, arayüz değişikliği, yeni paket.
