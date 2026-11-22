# ONNX Runtime ile cihazda çalıştırma (Görev 5E, Aşama 5)

Tarih: 22 Kasım 2026. Betikler: `tools/nlp_research/onnx_bench.py` (Python: dışa aktarma, int8, ölçüm),
`tools/nlp_research/onnx_bench_test.dart` (Dart: aynı modeller uygulamanın kendi FFI katmanıyla),
`tools/nlp_research/int8_check.py` (int8 kararları değiştiriyor mu).

**Ölçüm makinesi:** Linux x64 bulut makinesi, 4 çekirdek (paylaşımlı). Windows, Android ve iOS cihazında
**ölçüm yapılmadı** (bu ortamda cihaz yok). Aşağıdaki mobil sayılar tahmindir ve öyle işaretlendi.

## 1. Altyapı zaten uygulamada

| bileşen | durum |
|---|---|
| ONNX Runtime 1.28.2 | `sherpa_onnx 1.13.8` ile her platformda geliyor: Android `libonnxruntime.so` (arm64: 22,2 MB), Windows `onnxruntime.dll` (17,8 MB), Linux `.so`, iOS/macOS `SherpaOnnxC.xcframework` içinde. |
| Dart FFI bağlayıcısı | `lib/tts/ort.dart` (`Ort.load`, `ort.session`, float32/int64 tensör). Konuşma sentezi için yazılmıştı; bu görevde **değiştirilmedi**, ölçüm betiği onu olduğu gibi kullandı. |
| Yeni yerel kod / yeni paket | **gerekmiyor.** Dart'ta WordPiece belirteçleyici (≈90 satır, `onnx_bench_test.dart` içinde) yeterli. |

Yani bir model eklemek yalnız **model dosyasının** (ve `vocab.txt`'nin) boyutunu getirir; çalışma altyapısının
maliyeti zaten ödenmiş.

## 2. Dönüştürme

| model | ONNX nereden | not |
|---|---|---|
| all-MiniLM-L6-v2, bge-small, ms-marco-MiniLM-L6, nli-deberta-v3-xsmall | Hugging Face deposundaki `onnx/model.onnx` | hazır |
| GlossBERT | bu görevde `torch.onnx` ile dışa aktarıldı (opset 17, 5 s) | sorunsuz |
| spaCy sm / md / trf | **mümkün değil** | spaCy/thinc'in ONNX dışa aktarıcısı yok (`SPACY_EVALUATION.md` §3) |

**Belirteçleyici uyumu:** Dart WordPiece, Python `tokenizers` ile aynı kimlikleri üretti; all-MiniLM-L6-v2'de
200 çift üzerinde Dart ve Python puanları arasında Pearson **0,9999999998**, en büyük fark 5·10⁻⁶. DeBERTa
(SentencePiece) için Dart belirteçleyici yazılmadı; o model zaten seçilmedi.

## 3. int8 nicemleme (`quantize_dynamic`, yalnız ağırlıklar)

| model | fp32 MB | int8 MB | int8 / fp32 puan korelasyonu | karar değişimi (geliştirme kümelerinde) |
|---|---|---|---|---|
| all-MiniLM-L6-v2 | 90,4 | **22,9** | 0,947 | modelin ilk seçimi %87–91 aynı; **kapı sonucu neredeyse aynı** (aşağıda) |
| bge-small-en-v1.5 | 133,1 | 33,8 | 0,972 | – |
| ms-marco-MiniLM-L6 | 91,0 | **23,1** | 0,995 | ilk seçim %94–96 aynı; **veto kararı %96,5–96,9 aynı** |
| nli-deberta-v3-xsmall | 284,2 | 87,1 | 0,943 | – |
| GlossBERT | 438,2 | 110,3 | 0,985 | – |

int8'in son sisteme etkisi (geliştirme; PyTorch fp32 puanları ile int8 ONNX puanları aynı kuralla):

| küme | kapı (fp32): "kesin" ama yanlış anlam | kapı (int8) | kesin Türkçe yanlışı fp32 → int8 |
|---|---|---|---|
| SemCor 5a | %7,9 | %8,5 | 1/63 → 2/61 |
| SemCor 5b | %12,4 | %12,4 | 3/44 → 3/46 |
| SemEval-07 | %4,8 | %5,5 | 1/12 → 1/12 |

| küme | deyim vetosu (fp32): düz → deyim | veto (int8) | recall fp32 → int8 |
|---|---|---|---|
| MAGPIE 5a | %33,3 | %34,0 | %68,0 → %66,0 |
| MAGPIE 5b | %32,1 | %31,4 | %71,3 → %71,3 |

Sonuç: int8, boyutu dörtte bire indiriyor ve kararları küçük örneklem içindeki gürültü kadar değiştiriyor.
Uygulamaya bir model girecekse int8 olarak girmeli; ama eşikler int8 puanlarıyla **yeniden doğrulanmalı**.

## 4. Hız, bellek, yükleme (Dart, uygulamanın FFI katmanı, 200 çift, en çok 128 belirteç)

| model | biçim | iş parçacığı | yükleme | çift başına medyan | p95 | süreç RSS: önce → yüklendikten sonra → çalıştıktan sonra |
|---|---|---|---|---|---|---|
| all-MiniLM-L6-v2 (bi-encoder, çift = 2 cümle kodlama) | fp32 | 1 | 224 ms | 12,4 ms | 16,0 ms | 122 → 246 → 261 MB |
| | fp32 | 2 | 218 ms | 7,0 ms | 10,4 ms | → 269 MB |
| | **int8** | 1 | 127 ms | **4,1 ms** | 5,3 ms | 121 → 174 → **192 MB** |
| | int8 | 2 | 126 ms | 3,5 ms | 4,8 ms | → 192 MB |
| ms-marco-MiniLM-L6 (cross-encoder, çift = 1 çalıştırma) | fp32 | 1 | 240 ms | 12,4 ms | 17,1 ms | 122 → 247 → 252 MB |
| | fp32 | 2 | 242 ms | 6,9 ms | 9,1 ms | |
| | **int8** | 1 | 155 ms | **3,7 ms** | 5,5 ms | 122 → 175 → **182 MB** |
| | int8 | 2 | 145 ms | 4,1 ms | 5,2 ms | → 183 MB |

"122 MB" Flutter test sürecinin kendisidir; modelin eklediği bellek int8'de ≈ **55–70 MB**, fp32'de ≈ 130–145 MB.

Python ONNX Runtime ile (1 iş parçacığı, int8, taze süreç): bge-small 5,0 ms, ms-marco 2,7 ms, nli-deberta-xsmall
14,4 ms (tepe 395 MB), GlossBERT 15,6 ms (fp32 65 ms; tepe 249 MB).

**Bir kelimeye dokunulduğunda maliyet:** motor bir kelime için ortalama 5–7 aday anlam tartıyor (SemCor geliştirme: medyan 4, satırların %90'ında en çok 11). int8 MiniLM ile
cümle bir kez, her anlam açıklaması bir kez kodlanır (açıklamalar önbelleğe alınabilir): masaüstünde ≈ 10–40 ms.
GlossBERT gibi bir cross-encoder'da her aday ayrı çalıştırma ister: ≈ 7 × 15 ms ≈ 100 ms (11 adayda ≈ 170 ms).

### Platform tahmini (ölçülmedi)

| platform | beklenti | dayanak |
|---|---|---|
| Windows x64 | Linux ile aynı mertebe | aynı ORT sürümü, aynı CPU sınıfı |
| Android (orta sınıf arm64) | masaüstünün **2–4 katı yavaş**: int8 MiniLM çift başına ≈ 10–20 ms | genel ORT mobil ölçümleri; **cihazda doğrulanmalı** |
| iOS | Android'e benzer ya da daha hızlı | `ort.dart` Apple'da ORT'yi süreçten açıyor (`DynamicLibrary.process`); bu yol TTS için yazıldı, bu görevde iOS'ta denenmedi |

## 5. Uygulama boyutuna etkisi

| ne eklenir | boyut |
|---|---|
| ONNX Runtime | 0 (zaten var) |
| EWT perceptron etiketleyici (sinir ağı değil) | **0,9 MB** |
| int8 MiniLM / ms-marco + `vocab.txt` | ≈ 23 MB + 0,2 MB (her biri) |
| int8 GlossBERT | ≈ 110 MB |

Görev kuralı ("büyük model ekleme") ve lisans matrisi gereği bu görevde **hiçbir sinir ağı modeli uygulamaya
eklenmedi.** Bir model ileride girerse uygulama paketine değil, isteğe bağlı indirilebilir bir paket olarak girmesi
daha uygun olur (sesler gibi); o zaman çevrimdışı çalışma indirildikten sonra korunur.

## 6. Flutter / FFI entegrasyonu: ne gerekir

1. `Ort.load()` + `ort.session(model)` (var). Oturum ilk kullanımda açılır, ≈ 130–160 ms (int8).
2. Dart WordPiece belirteçleyici (`onnx_bench_test.dart`'taki sınıf, `lib/nlp/` altına taşınır).
3. Ortalama havuzlama + normalleştirme (bi-encoder) ya da logit (cross-encoder): birkaç satır.
4. Hata olursa ya da model yoksa: bugünkü SenseEngine kararı (zaten varsayılan yol).
5. Arka plan işçisi (isolate): ana iş parçacığını kilitlememek için puanlama isolate'te yapılmalı.

Tahmini emek: model indirme paketi hariç 2–3 gün; cihaz ölçümleri ve eşiklerin int8 ile yeniden doğrulanması dahil
bir hafta.
