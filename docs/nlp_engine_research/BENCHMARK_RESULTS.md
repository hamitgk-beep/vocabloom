# Sistem karşılaştırması ve final ölçümü (Görev 5E, Aşama 6–7)

Tarih: 22 Kasım 2026. Betikler: `tools/nlp_research/run_final.sh`, `final_report.py`, `metrics.py`,
`eval_systems.py`, `idiom_eval.py`, `pos_metrics.py`, `spacy_eval.py`.

## 0. Test güvenliği

- Bütün seçimler (eşikler, λ/T, hangi model, kapı mı yeniden sıralama mı) **geliştirme kümelerinde** yapıldı:
  SemCor 5a/5b, SemEval-2007, MAGPIE geliştirme kümeleri, EWT train örneklemi.
- Eski final kümeleri (5A/5B) bu görevde ayar için **kullanılmadı**; yalnız geliştirme verisi olarak okundu.
- **Yeni, bağımsız final** (`build_final_5e.py`, tohum 20266122): daha önce çekilen hiçbir kelimeyi içermeyen 514
  WSD satırı (Senseval-2/3, SemEval-2013/15; 279'unda KeNet Türkçe referansı), daha önce hiç görülmemiş 287 deyimden
  300 deyimsel / 110 düz MAGPIE cümlesi, UD English-PUD + GENTLE test (1.059 belge).
- Final dosyaları ölçümden önce kilitlendi (sha256: wsd `6e98ef18…`, magpie `2663bb2a…`, pos `8664c062…`,
  `MANIFEST_5e.json` `3002ab62…`); ayar dosyalarının özetleri de çalıştırmadan önce kaydedildi.
- Final **bir kez** çalıştırıldı; ardından hiçbir ayar değiştirilmedi.
- Veriler (BNC cümleleri, Raganato WSD verisi, GENTLE) depoya konmadı.

Finalde ölçülen sistemler (seçim geliştirmede yapıldı):

| ad | ne | dağıtılabilir mi |
|---|---|---|
| **A** | bugünkü motor (main) | – |
| **G0** (= B'nin uygulanabilir hâli) | A + bu görevde EWT ile eğitilen perceptron POS etiketleyici, motorun içinde "zayıf kural" | **evet** (0,9 MB, saf Dart; lisans: CC BY-SA atfı, 5C onayı) |
| **G** (C + F) | G0 + all-MiniLM-L6-v2 uzlaşma kapısı + ms-marco cross-encoder deyim vetosu | hayır (MS MARCO verisi, +46 MB) |
| **E** | G0 + GlossBERT yeniden sıralama (λ = 0,3, T = 0,02; SE07'de seçildi) + GlossBERT kapısı | hayır (kaynak doğrulanamadı, 110 MB) |

## 1. Geliştirme özeti (A–G)

| sistem | SemCor 5b: kesin yanlış | 5b: kesin Türkçe yanlışı | SE07: Türkçe doğru | SE07: kesin yanlış | MAGPIE 5b: düz → deyim / recall | EWT: gösterilen anlamın türü |
|---|---|---|---|---|---|---|
| A motor | %17,6 | 6/67 | %65,0 | %14,4 | %66,0 / %85,3 | %86,1 |
| B + spaCy md (sonradan kural) | – | – | – | – | – | %95,8 (Python, mobilde yok) |
| B + perceptron (motorun içinde) = G0 | %17,6 | 6/63 | %67,5 | %13,7 | %62,9 / ≈ aynı | %93,8 |
| C + MiniLM kapısı | %12,4 | 3/44 | %65,0 | %4,8 | – | – |
| D + ms-marco kapısı | %12,6 | 2/47 | %65,0 | %5,5 | – | – |
| D + ms-marco deyim vetosu | – | – | – | – | %32,1 / %71,3 | – |
| E GlossBERT (SemCor sızıntılı; SE07 temiz) | %12,1 | 0/51 | **%86,2** | %9,6 | – | – |
| F sınıflandırıcı (gruplu CV, 3.457 cümle) | – | – | – | – | %27,4 / %65,2 (veto) | – |
| G = G0 + C + D-veto (anlam kısmı perceptron sonradan kural olarak) | %11,8 | 3/41 | %67,5 | %4,8 | ≈ %32 / ≈ %71 | %93,8 |

Ayrıntılar: `SPACY_EVALUATION.md`, `SENTENCE_TRANSFORMERS_EVALUATION.md`, `IDIOM_CLASSIFIER_EVALUATION.md`.

## 2. Final: kelime anlamı ve Türkçe karşılık (514 satır)

| sistem | doğru anlam (tümü) | **Türkçe doğru** (gösterilen, katı) | kesin (pay) | kesin içinde doğru | **kesin yanlış** (tümüne oranla) | **kesin Türkçe yanlışı** [%95 GA] | kart önerisi, doğru |
|---|---|---|---|---|---|---|---|
| A motor | %31,7 | %68,8 | 192 (%37,4) | %49,0 | %19,1 | 17/125 = **%13,6** [9–21] | 143, %80,4 |
| G0 + etiketleyici | %34,4 | %73,9 | 179 (%34,8) | %52,0 | %16,7 | 13/119 = %10,9 [6–18] | 152, %80,3 |
| G (anlam kısmı: G0 + MiniLM kapısı) | %34,4 | %73,9 | 121 (%23,5) | %55,4 | %10,5 | 3/73 = **%4,1** [1–11] | 71, %90,1 |
| E (G0 + GlossBERT) | **%40,9** | **%84,9** | 134 (%26,1) | %61,9 | **%9,9** | 1/85 = **%1,2** [0–6] | 94, %88,3 |
| (karşılaştırma) ilk anlam | %56,2* | %66,7 | – | – | – | – | – |

\* "Doğru anlam" WordNet anlam kimliğiyle katı eşleşmedir; motor adaylarının bir kısmı WordNet dışı kaynaklardan
geldiği için bu sütun motoru olduğundan kötü gösterir (`CURRENT_ENGINE_BASELINE.md`). Okuyucunun gördüğü şey Türkçe
karşılıktır; o sütunda A ilk anlamı ancak geçiyor (%68,8 / %66,7), G0 +7, E +18 puan önde.

Eşleştirilmiş testler (McNemar, aynı satırlar):

- G0 – A, Türkçe: G0'ın doğru A'nın yanlış olduğu 17 satır, tersi 3; **p = 0,003**. İngilizce anlam: 17 / 3, p = 0,003.
- E – A, Türkçe: 54 / 10, **p = 2·10⁻⁸** (A 187/279, E 231/279). İngilizce anlam: 64 / 17, p = 10⁻⁷.
- G – A, "yanlışlıkla kesin gösterilmeyen satır": G'nin düzelttiği 46, bozduğu 2; p = 10⁻¹¹.

### 2.1 Kesin Türkçe yanlışlarının elle kontrolü (eşanlamlılar)

Katı ölçüde "yanlış" sayılan kesin satırlara tek tek bakıldı. **Bu Claude'un değerlendirmesidir, bağımsız bir
hakem değil.**

| sistem | katı | kabul edilebilir eşanlam | tartışmalı | elle sonra gerçek yanlış |
|---|---|---|---|---|
| A | 17/125 | 4 (instability → dengesizlik, potential → potansiyel, divide → bölmek, teach → öğretmek) | 2 (appreciation → beğeni, likely → muhtemelen) | **11–13/125 = %8,8–10,4** |
| G | 3/73 | 1 (teach → öğretmek) | 0 | **2/73 = %2,7** (interest → "ilgisini çekmek", put → "rahatsız etmek") |
| E | 1/85 | 0 | 1 (appreciation → beğeni) | **0–1/85 = %0–1,2** |

A'nın gerçek yanlışlarından örnekler: "the English" → *İngilizce*, "poster frames" → *iskelet*, "countries" → *bölge*,
"the dose reduced" → *kilo vermek*, "turned on his heel" → *burkmak*.

## 3. Final: deyim / düz (300 deyimsel / 110 düz cümle, deyimler daha önce hiç görülmedi)

| sistem | precision | recall | F1 | **düz → deyim** [%95 GA] | düz ama deyim **kesin** |
|---|---|---|---|---|---|
| A motor | %89,2 | %71,7 | 79,5 | 26/110 = %23,6 [17–32] | 3 |
| G0 | %89,0 | %70,0 | 78,4 | 26/110 = %23,6 | 3 |
| G (ms-marco vetosu) | %91,4 | %53,3 | 67,4 | 15/110 = **%13,6** [8–21] | 1 |

- Veto düz cümlelerin deyim sanılmasını **26'dan 15'e** indirdi (11 düzeltme, 0 bozma; p = 0,001), ama **55
  deyimsel cümleyi de kaçırdı** (recall %71,7 → %53,3; p < 10⁻¹⁵). Görevin "recall korunmalı" şartını sağlamıyor.
- Finalde düz cümle oranı geliştirmeden düşük (110/410), bu yüzden precision geliştirmeden yüksek; sayılar
  geliştirme ile doğrudan karşılaştırılmamalı.
- **Yeni bulgu:** motor 3 düz cümlede deyimi "kesin" gösterdi ("circle the wagons", "poacher turned gamekeeper",
  "she'll be right"). 5B'nin "deyim asla kesin değil" kuralı yalnız sözcük sözcük okumanın Türkçesi varsa çalışıyor;
  bu üç deyimde sözcük sözcük aday yok. Bu bir hata adayı, ayrı bir görevde ele alınmalı.

Varyant türüne göre (A / G, deyim olarak gösterilen):

| varyant | deyimsel: satır / bulundu / A / G | düz: satır / bulundu / A / G |
|---|---|---|
| aynen (identical) | 127 / 127 / 112 / 82 | 4 / 4 / 4 / 0 |
| çekim (inflection) | 36 / 34 / 27 / 21 | 1 / 0 / 0 / 0 |
| tire / büyük-küçük harf | 48 / 47 / 45 / 35 | 6 / 6 / 5 / 3 |
| çekim + başka değişiklik | 35 / **11** / 10 / 5 | 46 / 7 / 5 / 4 |
| araya kelime (insertion-other) | 7 / **0** / 0 / 0 | 11 / 0 / 0 / 0 |
| iyelik (possessive) | 8 / **0** / 0 / 0 | 5 / 0 / 0 / 0 |
| diğer | 39 / 22 / 21 / 17 | 37 / 16 / 12 / 8 |

Araya kelime girmiş ve iyelikli deyimlerin **hiçbiri** bulunamıyor; bu eşleştiricinin sorunu, sınıflandırıcı
çözemez.

## 4. Final: sözcük türü ve kök (UD PUD + GENTLE, 1.059 belge)

| ölçü | A motor | G0 (motor + perceptron) | spaCy sm (B, Python) | spaCy md | spaCy trf |
|---|---|---|---|---|---|
| gösterilen anlamın türü doğru | %85,3 | **%92,1** | %95,1 | %95,1 | %96,5 |
| "kesin" ama türü yanlış | %6,8 (156/2.303) | **%3,7** (78/2.126) | %0,8 | %0,8 | %0,4 |
| gösterilen anlamın kökü doğru | %96,1 | **%97,2** | – | – | – |
| UPOS (isim/fiil/sıfat/zarf) | – | – | %87,2 | %87,7 | %92,5 |
| kök (spaCy'nin kendi) | – | – | %96,9 | %96,9 | %98,0 |
| cümle sınırı P / R | – | – | %84,2 / %86,5 | %84,0 / %85,9 | %98,6 / %87,0 |
| hız | 1,6 ms/kelime çözümü | 1,7 ms (+ etiketleme 0,13 ms/cümle) | 1,5 ms/cümle | 1,7 | 22 ms |
| boyut / bellek | – | +0,9 MB | 15 MB / süreç 745 MB | 57 MB / 1,0 GB | 501 MB / 3,4 GB |

spaCy daha iyi ama mobilde çalışamaz (Python, ONNX yok). Perceptron aradaki farkın yarısından fazlasını 0,9 MB'la
kapatıyor.

## 5. Kaynak tüketimi

| sistem | ek boyut | kelime başına ek süre (masaüstü) | ek bellek |
|---|---|---|---|
| A | – | medyan 1,6 ms, p95 5,8 ms (motorun çözümü) | – |
| G0 | 0,9 MB | +0,1 ms | birkaç MB |
| G | +46 MB (iki int8 model) | ≈ +10–40 ms | ≈ +110–140 MB |
| E | +110 MB (int8) | ≈ +100 ms (7 aday × 15 ms) | ≈ +130 MB |

Mobil cihazlarda ölçülmedi; `ONNX_DEPLOYMENT.md` §4.

## 6. Kriterler (Aşama 7)

| # | kriter | G0 | G | E |
|---|---|---|---|---|
| 1 | doğruluk artışı | **evet**: Türkçe +5,1 puan (p = 0,003), tür +6,8 puan | anlam G0 ile aynı | **evet**: Türkçe +16,1 puan (p = 2·10⁻⁸) |
| 2 | daha az yanlış pozitif (deyim) | hayır (aynı) | evet: düz → deyim %23,6 → %13,6 | – |
| 3 | kesin-yanlış artmıyor | **evet**: %19,1 → %16,7 | evet: → %10,5 | evet: → %9,9 |
| 4 | kart güvenliği | doğru oranı aynı (%80,3), kart sayısı +9 | %90,1 (kart 143 → 71) | %88,3 (94 kart) |
| 5 | çevrimdışı | evet | evet | evet |
| 6 | mobil performans | evet (saf Dart) | cihazda ölçülmedi | cihazda ölçülmedi; ağır |
| 7 | lisans | CC BY-SA atfı, 5C onayı | **hayır** (MS MARCO) | **hayır** (kaynak doğrulanamadı) |
| 8 | kullanıcı verisi değişmez | evet | evet | evet |
| 9 | güvenli geri dönüş | evet (hata → bugünkü kural) | tasarlandı | tasarlandı |
| – | Türkçe yanlışı < %5 (kesin) | hayır (%10,9; elle bakılmadı) | **evet** (%4,1; elle %2,7) | **evet** (%1,2) |
| – | ilk anlamı geçmek (Türkçe) | evet (%73,9 / %66,7) | evet | evet (%84,9) |
| – | recall korunur | evet | **hayır** (%53,3) | – |

Örneklem notu: final 514 satır, ama Türkçe referansı olan kesin satırlar 73–125; tek satır ±1–1,5 puan oynatıyor.
%95 güven aralıkları tablolarda. G ve E'nin "< %5" sonucu bu yüzden üst sınırda (%11 / %6) %5'i garanti etmiyor.
