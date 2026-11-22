# Model ve veri lisans matrisi (Görev 5E)

Tarih: 22 Kasım 2026. Lisanslar model kartlarından ve kaynak depolardan okundu (Hugging Face API, GitHub).
**Bu bir hukuki görüş değildir.** Lisans/provenance işi Görev 5C'de ayrıca yürüyor; buradaki "üretime uygun mu"
sütunu yalnız bu görevin kuralını uygular: *eğitim verisi, lisansı ve kaynağı doğrulanamayan model üretime uygun
sayılmaz.*

Uygulamanın kendisi GPL-3.0. Uygulamaya model **ağırlığı** koymak, o ağırlıkları dağıtmak demektir; bu yüzden
"ağırlık lisansı" kadar "eğitim verisinin koşulları" da önemlidir.

## 1. Kütüphaneler ve çalışma altyapısı

| bileşen | lisans | uygulamada mı | not |
|---|---|---|---|
| ONNX Runtime 1.28.2 | MIT | **zaten var** (sherpa-onnx ile geliyor; `lib/tts/ort.dart`) | Android, iOS, Windows, Linux, macOS ikilileri sherpa-onnx paketinde. Yeni bağımlılık gerekmez. |
| spaCy 3.8 | MIT | hayır (yalnız geliştirici makinesi) | Python; mobil uygulamaya konmaz. |
| Sentence Transformers 6.3 | Apache-2.0 | hayır | Python; yalnız ölçüm için. |
| NLTK 3.9 (PerceptronTagger kodu) | Apache-2.0 | hayır | Etiketleyici Dart'a yeniden yazıldı (`lib/nlp/pos_tagger.dart`), NLTK kodu kopyalanmadı; özellik tanımı aynı. |

## 2. Modeller

| model | ağırlık lisansı | eğitim verisi (model kartına göre) | veri koşulu riski | boyut (fp32) | üretime uygun mu |
|---|---|---|---|---|---|
| **EWT perceptron etiketleyici** (bu görevde eğitildi) | eğitim verisinin lisansı: CC BY-SA 4.0 | UD English-EWT (CC BY-SA 4.0) | Ağırlıklar EWT'nin uyarlaması sayılabilir → atıf + aynı lisansla paylaşım. CC BY-SA 4.0'dan GPLv3'e tek yönlü uyumluluk Creative Commons tarafından ilan edildi (2015). | 0,9 MB (gzip JSON) | **Aday** – 5C'nin atıf/uyumluluk onayıyla. Dağıtım hakkı açık: modeli biz eğittik. |
| spaCy `en_core_web_sm` / `md` 3.8.0 | MIT | OntoNotes 5 (LDC), ClearNLP, WordNet 3.0; md: Explosion vektörleri | OntoNotes LDC lisanslıdır; Explosion ağırlıkları MIT ile dağıtıyor. | 15 / 57 MB | Yalnız geliştirme aracı olarak. Mobilde çalışmaz (Python). |
| spaCy `en_core_web_trf` 3.8.0 | MIT | aynı + roberta-base | aynı | 501 MB | Hayır (boyut, Python). |
| `sentence-transformers/all-MiniLM-L6-v2` | Apache-2.0 | 1 milyar cümle çifti, 21 veri kümesi; **MS MARCO dahil** (MS MARCO koşulları "yalnız ticari olmayan araştırma") ve Reddit, Stack Exchange vb. | **Yüksek**: eğitim verisinin bir kısmı ticari kullanımı kısıtlıyor. | 90 MB (int8: 23 MB) | **Hayır** (provenance karışık). Ölçüm için kullanıldı. |
| `BAAI/bge-small-en-v1.5` | MIT | BAAI'nin büyük çift derlemi; ayrıntılı liste yok | **Doğrulanamadı** | 133 MB | Hayır |
| `sentence-transformers/all-mpnet-base-v2` | Apache-2.0 | all-MiniLM ile aynı 1B çift | Yüksek (MS MARCO) | 438 MB | Hayır (boyut + veri) |
| `paraphrase-multilingual-MiniLM-L12-v2` | Apache-2.0 | çok dilli paralel veri (damıtma); ayrıntı kısmi | Orta / doğrulanamadı | 471 MB | Hayır |
| `cross-encoder/ms-marco-MiniLM-L6-v2` | Apache-2.0 | **MS MARCO** | **Yüksek** (veri koşulu ticari değil) | 91 MB | **Hayır** |
| `cross-encoder/stsb-roberta-base` | Apache-2.0 | STS benchmark (CC BY-SA 4.0), roberta-base (MIT) | Düşük | 499 MB | Boyut yüzünden hayır |
| `cross-encoder/nli-deberta-v3-xsmall` | Apache-2.0 | SNLI (CC BY-SA 4.0) + MultiNLI (çoğu OANC, serbest); deberta-v3-xsmall (MIT) | Düşük–orta | 283 MB (int8 ≈ 85 MB) | Veri açısından en temiz cross-encoder; doğruluk yetersiz (bkz. benchmark) |
| `BAAI/bge-reranker-base` | MIT | ayrıntılı liste yok | Doğrulanamadı | 1,1 GB | Hayır |
| `kanishka/GlossBERT` | MIT (yükleyen kişi); özgün depo HSLCY/GlossBERT da MIT | SemCor 3.0 (Princeton WordNet lisansı, serbest) + bert-base-uncased (Apache-2.0) | Veri temiz; ama Hugging Face kopyası **özgün yazarlar tarafından yüklenmedi**, ağırlıkların özgün checkpoint olduğu doğrulanamıyor | 438 MB (int8 ≈ 110 MB) | **Hayır** (provenance + boyut). Özgün depodan yeniden eğitim yapılabilir. |
| `sign/Ettin-150m-WSD` (yalnız incelendi, çalıştırılmadı) | Apache-2.0 | SemCor, WordNet örnekleri, **LLM ile üretilmiş cümleler**, 1B öğretmen modelden damıtma, Wikipedia | Üretilmiş verinin kaynağı ve öğretmenin verisi belirsiz | ≈300 MB (bf16) | Hayır; özel sınıflandırıcı kafası ayrı depoda |
| MAGPIE ile eğitilen deyim sınıflandırıcı (bu görevde, lojistik regresyon) | – | MAGPIE etiketleri (CC BY 4.0) + cümleler **BNC** (yeniden dağıtılamaz) | Sınıflandırıcı yalnız sayısal özelliklerle (puan farkları) eğitildi, BNC metni modelde yok; ama BNC'den türetilmiş ağırlık dağıtımı 5C'de netleşmeli | < 1 KB | Teknik olarak dağıtılabilir; **lisans 5C onayına kadar hayır** |

## 3. Değerlendirme verileri (hiçbiri depoya konmadı)

| veri | lisans | kullanım |
|---|---|---|
| SemCor 3.0 (NLTK) | Princeton WordNet lisansı | geliştirme (5A/5B kümeleri) |
| Senseval-2/3, SemEval-2007/13/15 (Raganato vd. 2017 çerçevesi) | araştırma verisi | 5E final (SE07: geliştirme) — yalnız yerel |
| MAGPIE | etiketler CC BY 4.0, metin BNC | geliştirme, eğitim, 5E final — yalnız yerel |
| UD English-EWT | CC BY-SA 4.0 | geliştirme, etiketleyici eğitimi |
| UD English-PUD | CC BY-SA 3.0 | 5E final (POS/kök) — yalnız yerel |
| UD English-GENTLE | CC BY-NC-SA 4.0 | 5E final (POS/kök), yalnız ölçüm — yalnız yerel |

## 4. Sonuç

- Ölçülen **sinir ağı modellerinin hiçbiri** bugün "eğitim verisi, lisans ve kaynak doğrulandı" koşulunu birlikte
  sağlamıyor; en yakın olanlar (`nli-deberta-v3-xsmall`, `stsb-roberta-base`) ya yeterince iyi değil ya da çok büyük.
- Dağıtım hakkı açık olan tek bileşen, bu görevde **bizim eğittiğimiz** EWT etiketleyicisidir (CC BY-SA 4.0 atıf
  koşuluyla; 5C onayı gerekir).
- Bir sinir ağı modeli ileride üretime alınacaksa en temiz yol: MIT lisanslı bir taban (ör. `microsoft/MiniLM-L12-H384-uncased`)
  + lisansı açık veri (SemCor, WordNet örnekleri, EWT) ile **kendi** WSD modelimizi eğitmek.
