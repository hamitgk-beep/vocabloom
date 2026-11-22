# Sentence Transformers, cross-encoder ve WSD modelleri (Görev 5E, Aşama 3)

Tarih: 22 Kasım 2026. Betikler: `tools/nlp_research/score_senses.py` (her aday anlamı bir modelle puanlar),
`eval_systems.py` (sistemler ve geliştirme seçimi), `gate_analysis.py` (kapının anlamlılığı), `metrics.py`.
Modeller yerel Hugging Face önbelleğinden çalıştı; **hiçbir kullanıcı metni dışarı gönderilmedi** (ölçüm
cümleleri SemCor / SemEval / MAGPIE'dir).

## 1. Ne denendi

Motor bir kelime için aday anlamları zaten buluyor (`wn:`, `od:`, `ow:` …). Model yeni anlam **üretmiyor**; yalnız
motorun adaylarını cümleye göre puanlıyor. Her aday "kelime: İngilizce açıklama (e.g. örnek)" olarak modele verildi;
cümlede hedef kelime tırnak içinde işaretlendi.

| tür | model | puan |
|---|---|---|
| bi-encoder | all-MiniLM-L6-v2, bge-small-en-v1.5, all-mpnet-base-v2, paraphrase-multilingual-MiniLM-L12-v2 | cümle ↔ açıklama kosinüsü |
| cross-encoder | ms-marco-MiniLM-L6-v2, stsb-roberta-base, bge-reranker-base | çiftin puanı |
| NLI | nli-deberta-v3-xsmall | "bu cümlede X şu demek" için entailment − contradiction |
| **WSD'ye özel** | GlossBERT (bert-base, SemCor ile eğitilmiş; `kanishka/GlossBERT`) | "cümle, açıklama" çiftinin "doğru anlam" logiti |
| WSD'ye özel, incelendi | `sign/Ettin-150m-WSD` | çalıştırılmadı: eğitim verisinin bir kısmı LLM ile üretilmiş, sınıflandırıcı kafası ayrı (lisans matrisi) |

Her model üç biçimde motora bağlandı:

1. **model tek başına:** modelin en yüksek puanlı anlamı gösterilir;
2. **yeniden sıralama:** motor puanı + λ · softmax(model puanı / T); λ ve T geliştirmede seçildi;
3. **uzlaşma kapısı:** gösterilen anlam değişmez; motor "kesin" dediğinde model de **aynı** anlamı ilk sıraya
   koymuyorsa "kesin" → "olası" iner. Kart da (`fit()`) yalnız ikisi aynı anlamda birleşirse önerilir.

## 2. Geliştirme sonuçları

SemCor 5a / 5b (340'ar satır) ve SemEval-2007 (146 satır). "Kesin yanlış" = tüm satırlara oranla "kesin"
gösterilen yanlış anlam. Türkçe = gösterilen anlamın Türkçesi KeNet referansıyla aynı mı (katı).

### 2.1 Modeller tek başına motordan iyi değil (GlossBERT hariç)

| model tek başına | doğru anlam 5a / 5b / SE07 | Türkçe doğru 5a / 5b / SE07 |
|---|---|---|
| **A motor** | 31,2 / 27,6 / 30,1 | 78,6 / 79,5 / 65,0 |
| all-MiniLM-L6-v2 | 28,8 / 23,8 / 22,6 | 77,9 / 68,0 / 61,2 |
| bge-small | 27,4 / 23,5 / 20,5 | 75,6 / 69,7 / 60,0 |
| all-mpnet-base | 28,2 / 24,1 / 24,7 | 77,9 / 71,3 / 58,8 |
| multilingual MiniLM | 27,4 / 22,4 / 20,5 | 75,6 / 68,9 / 57,5 |
| ms-marco cross-encoder | 28,8 / 23,8 / 22,6 | 78,6 / 76,2 / 57,5 |
| stsb-roberta cross-encoder | 30,0 / 22,4 / 19,2 | 79,4 / 71,3 / 53,8 |
| nli-deberta-xsmall | 27,1 / 21,8 / 27,4 | 74,0 / 67,2 / 68,8 |
| **GlossBERT** | **35,6 / 31,5 / 39,0** | **92,4 / 89,3 / 86,2** |

Genel amaçlı benzerlik modelleri anlamı motordan kötü seçiyor. Yeniden sıralamada geliştirmenin seçtiği λ bu
modellerin hepsi için **0** çıktı (yani en iyisi motorun sıralamasına hiç dokunmamak).

**GlossBERT** tek istisna. Ama dikkat: GlossBERT **SemCor ile eğitildi**; SemCor 5a/5b sonuçları sızıntılıdır.
SemEval-2007 GlossBERT'in eğitiminde yok (özgün çalışmada geliştirme kümesiydi), bu yüzden temiz geliştirme
ölçüsü SE07'dir: Türkçe %65,0 → %86,2, doğru anlam %30,1 → %39,0. Ayarlar (λ = 0,3, T = 0,02) de **yalnız SE07'de**
seçildi; final kümesi (Senseval-2/3, SemEval-13/15) GlossBERT'in eğitiminde yok.

### 2.2 Kapı: "kesin yanlış"ı azaltıyor

| sistem | kesin (pay) 5a / 5b / SE07 | **kesin yanlış** 5a / 5b / SE07 | kesin Türkçe yanlışı 5a / 5b / SE07 | kart, doğru 5a / 5b |
|---|---|---|---|---|
| A motor | %33,2 / %32,4 / %31,5 | %13,8 / %17,6 / %14,4 | 6/78, 6/67, 4/35 | 68 %83,8; 68 %86,8 |
| + MiniLM kapısı | %25,9 / %23,8 / %12,3 | **%7,9 / %12,4 / %4,8** | **1/63, 3/44, 1/12** | 47 %95,7; 42 %85,7 |
| + bge-small kapısı | %26,5 / %24,1 / %11,6 | %9,1 / %12,4 / %4,1 | 2/63, 3/44, 0/12 | 48 %93,8; 41 %87,8 |
| + mpnet kapısı | %26,2 / %23,8 / %13,0 | %9,1 / %12,4 / %4,8 | 1/61, 0/43, 1/13 | 53 %88,7; 47 %89,4 |
| + ms-marco kapısı | %27,6 / %24,7 / %11,0 | %10,0 / %12,6 / %5,5 | 4/67, 2/47, 2/10 | 52 %94,2; 49 %89,8 |
| + nli-deberta kapısı | %26,2 / %25,3 / %18,5 | %10,0 / %13,5 / %8,2 | 3/62, 3/49, 1/19 | 47 %89,4; 44 %84,1 |
| + GlossBERT kapısı | %28,2 / %26,5 / %24,7 | %9,1 / %12,1 / %9,6 | 1/66, 0/51, 3/27 | 55 %92,7; 54 %92,6 |

Bedeli: "kesin" gösterilen kelime sayısı azalıyor (SE07'de MiniLM ile üçte bire).

**Kapı yalnız "daha az kesin" demek mi?** Hayır. Motorun "kesin" dediği satırlarda, modelin onayladıkları ile
onaylamadıkları karşılaştırıldı (Fisher kesin testi, üç geliştirme kümesi birlikte):

| model | onaylanan: doğru anlam | indirilen: doğru anlam | p | onaylanan: Türkçe doğru | indirilen | p |
|---|---|---|---|---|---|---|
| all-MiniLM-L6-v2 | 111/187 = %59,4 | 30/82 = %36,6 | 0,0009 | 114/119 = %95,8 | 50/61 = %82,0 | 0,004 |
| bge-small | %58,2 | %38,8 | 0,005 | %95,8 | %82,0 | 0,004 |
| all-mpnet-base | %57,7 | %40,0 | 0,011 | %98,3 | %77,8 | 0,00001 |
| ms-marco | %56,2 | %42,7 | 0,057 | %93,5 | %85,7 | 0,097 |
| stsb-roberta | %57,3 | %38,6 | 0,008 | %96,8 | %77,8 | 0,0001 |
| nli-deberta-xsmall | %54,5 | %46,3 | 0,26 | %94,6 | %82,0 | 0,016 |
| GlossBERT (SemCor sızıntılı) | %61,3 | 5/47 = %10,6 | 10⁻¹⁰ | %97,2 | %66,7 | 10⁻⁶ |

Yani modelin onayı gerçekten bilgi taşıyor: onaylanmayan "kesin"ler belirgin biçimde daha sık yanlış.

## 3. Uygulanabilirlik

| model | int8 boyut | Dart'ta çift başına (masaüstü, int8, 1 iş parçacığı) | lisans / veri | sonuç |
|---|---|---|---|---|
| all-MiniLM-L6-v2 | 22,9 MB | 4,1 ms | Apache-2.0; eğitimde **MS MARCO** (ticari olmayan) | araştırma: en iyi kapı / boyut dengesi, ama veri riski |
| ms-marco-MiniLM-L6 | 23,1 MB | 3,7 ms | MS MARCO | araştırma (deyim vetosunda kullanıldı) |
| nli-deberta-v3-xsmall | 87,1 MB | 14,4 ms (Python) | veri en temiz | kapı zayıf (p = 0,26) |
| GlossBERT | 110,3 MB | 15,6 ms (Python) | MIT, SemCor; HF kopyasının kaynağı doğrulanamadı | **en doğru**; boyut ve kaynak yüzünden üretime değil |

Ayrıntılar `ONNX_DEPLOYMENT.md`, lisanslar `MODEL_LICENSE_MATRIX.md`, finaldeki sonuçlar `BENCHMARK_RESULTS.md`.

## 4. Kısıtlar

- Örneklemler küçük (geliştirmede 146–340 satır; "kesin Türkçe yanlışı" 12–78 satır üzerinden). Güven aralıkları
  tablolarda; çoğu fark tek başına anlamlı değil, Fisher testleri ise üç küme birlikte yapıldı.
- Türkçe doğruluğu yalnız KeNet referansı olan satırlarda ölçüldü; eşanlamlı Türkçe karşılıklar katı ölçüde
  "yanlış" sayılır (finalde elle bakıldı, `BENCHMARK_RESULTS.md`).
- Modeller yalnız motorun bulduğu adaylar arasında seçer; doğru anlam aday listesinde yoksa model kurtaramaz.
