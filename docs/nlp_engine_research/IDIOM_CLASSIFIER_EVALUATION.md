# Deyim / düz kullanım ayrımı (Görev 5E, Aşama 4)

Tarih: 22 Kasım 2026. Betikler: `tools/nlp_research/idiom_eval.py`, `score_senses.py`, `dump_engine_test.dart`.
Veri: MAGPIE (Haagsma, Bos, Nissim 2020; etiketler CC BY 4.0, cümleler çoğunlukla BNC: **yalnız yerel**, depoya
konmadı, bu belgede BNC cümlesi alıntılanmadı). Yalnız annotatör uzlaşması 1,0 olan cümleler.

## 1. Soru ve yöntemler

Motor bir kalıbı cümlede bulduğunda iki okuma yarışır: deyim anlamı ve sözcük sözcük okuma. Görev, deyimin bu
cümlede **gerçekten mecaz** kullanılıp kullanılmadığını söylemek; emin değilse kararsız kalmak.

| # | yöntem | nasıl |
|---|---|---|
| 1 | Mevcut SenseEngine | kalıp anlamı ile sözcük sözcük okumanın puanları (`_resolvePhrase`) |
| 2 | Anlamsal benzerlik (bi-encoder) | cümle ile her okumanın açıklaması arasındaki kosinüs; fark = en iyi deyim anlamı − en iyi düz anlam |
| 3 | Cross-encoder / NLI / GlossBERT | aynı fark, cümle + açıklama birlikte modele verilerek |
| 4 | Deyim kullanımına özel eğitilmiş hazır model | Hugging Face'te arandı ("idiom", "idiomatic", "literal"): bulunan birkaç model (`jlsalim/bert-…-idiomatic-literal-recognizer`, `imranraad/idiom-xlm-roberta` …) ya lisanssız ya eğitim verisi belirtilmemiş ya da deyim *tespiti* (dizi etiketleme) için; hiçbiri "bu cümlede mecaz mı" sorusuna lisansı açık bir cevap vermiyor. **Çalıştırılmadı.** |
| 5 | Küçük bir sınıflandırıcı (bu görevde eğitildi) | lojistik regresyon; özellikler: motorun kararı ve puan farkı, kalıp kategorisi, cümle uzunluğu, beş modelin fark puanı; isteğe bağlı olarak cümlenin kelimeleri (TF-IDF) |

Her yöntem üç türlü karar verebilir: **deyim**, **düz**, **kararsız**. Uygulamaya en kolay girecek biçim
"**veto**"dur: model yalnız "bu düz kullanım" diyebilir; diyemezse motorun bugünkü kararı (deyim, *olası*) kalır.
Böylece kararsız durumda okuyucu bugünkü gibi deyim anlamını "olası" olarak görür.

## 2. Geliştirme sonuçları

Eşikler dört geliştirme kümesinde seçildi, beşincisinde (5B finali, 150 deyimsel / 159 düz) gösterildi.
Amaç fonksiyonu: doğru tanınan deyim − 1,5 × deyim sanılan düz cümle (düz kullanımı deyim göstermek, deyimi
kaçırmaktan daha kötü kabul edildi: deyim kaçınca okuyucu yine kelimelerin anlamını görür).

| yöntem (5B finali, 150/159) | precision | recall | F1 | düz → deyim | kararsız (deyimsel/düz) |
|---|---|---|---|---|---|
| 1 motor | %54,9 | %85,3 | 66,8 | 105/159 = **%66,0** | – |
| 2 all-MiniLM-L6-v2, veto | %66,9 | %60,7 | 63,6 | 45/159 = %28,3 | – |
| 2 bge-small-en-v1.5, veto | %65,6 | %66,0 | 65,8 | 52/159 = %32,7 | – |
| 2 multilingual MiniLM, veto | %64,0 | %59,3 | 61,6 | 50/159 = %31,4 | – |
| 3 ms-marco-MiniLM-L6 cross-encoder, veto | **%67,7** | %71,3 | **69,5** | 51/159 = **%32,1** | – |
| 3 ms-marco-MiniLM-L6, üç yollu | %65,4 | %79,3 | 71,7 | 63/159 = %39,6 | 28/83 |
| 3 stsb-roberta-base, veto | %61,7 | %58,0 | 59,8 | 54/159 = %34,0 | – |
| 3 nli-deberta-v3-xsmall, veto | %56,3 | %50,7 | 53,3 | 59/159 = %37,1 | – |

En iyi denge ms-marco cross-encoder vetosunda: düz cümlelerin deyim sanılması **%66 → %32**, buna karşılık deyim
tanıma %85 → %71. Final için bu seçildi (`IDIOM_MODEL = ce_marco`, eşik geliştirmede sabitlendi).

### 2.1 Sınıflandırıcı ve test sızıntısı

Havuz: tüm MAGPIE geliştirme cümleleri + eğitim havuzu (final deyimleri hiç yok) = 3.457 cümle (2.525 deyimsel,
932 düz), 844 deyim. 5 katlı çapraz doğrulama iki türlü yapıldı:

- **deyime göre gruplu:** bir deyimin bütün cümleleri aynı katta; test deyimleri eğitimde hiç görülmedi;
- **rastgele:** aynı deyimin başka cümleleri eğitimde olabilir.

| sınıflandırıcı | bölme | precision | recall | F1 | düz → deyim |
|---|---|---|---|---|---|
| sayısal özellikler, üç yollu | gruplu | %90,8 | %47,8 | 62,7 | %13,2 |
| sayısal özellikler, üç yollu | rastgele | %90,8 | %47,6 | 62,5 | %13,1 |
| sayısal özellikler, veto p ≤ 0,5 | gruplu | %86,6 | %65,2 | 74,4 | %27,4 |
| sayısal özellikler, veto p ≤ 0,5 | rastgele | %87,3 | %65,4 | 74,8 | %25,9 |
| **kelimeler + özellikler**, üç yollu | **gruplu** | %90,7 | %60,4 | 72,5 | **%16,8** |
| **kelimeler + özellikler**, üç yollu | **rastgele** | %93,2 | %60,2 | 73,1 | **%11,9** |
| motor (aynı cümleler) | – | %76,8 | %87,8 | 81,9 | %71,8 |

**Sızıntının etkisi:** yalnız puan farkı kullanan sınıflandırıcı deyimi "ezberleyemediği" için iki bölmede aynı
sonucu veriyor. Cümlenin kelimelerini de gören sınıflandırıcı ise aynı deyimin başka cümlelerini eğitimde görünce
**olduğundan iyi görünüyor**: düz → deyim hatası %16,8 yerine %11,9, precision %90,7 yerine %93,2. Yani aynı deyimin
cümleleri eğitimle test arasında bölünürse hata yaklaşık **5 puan (üçte bir) az ölçülür.** Bu yüzden 5E finali
yalnız **hiç görülmemiş deyimlerden** kuruldu ve sınıflandırıcı/eşikler o deyimlerin hiçbirini görmedi.

Sınıflandırıcı beş ayrı modelin puanını istediği için (≈5 model çalıştırmak) mobilde pahalıdır; final sisteme
tek modelli veto alındı. Sınıflandırıcı araştırma sonucu olarak kalıyor.

## 3. Deyimin biçimi

Bulma, eşleştiricinin işidir; sınıflandırıcı bulunmayan deyimi kurtaramaz. Geliştirmede (`CURRENT_ENGINE_BASELINE.md`
§2.4): araya kelime girmiş deyimler **%0**, çekim + başka değişiklik %48, belirteç düşmüş %17 bulunuyor. Final
sonuçları varyant türüne göre `BENCHMARK_RESULTS.md` §3'te.

## 4. Final sonuçları

Ayrıntı `BENCHMARK_RESULTS.md` §3. Özet (300 deyimsel / 110 düz, deyimler hiç görülmedi):

| sistem | precision | recall | F1 | düz → deyim |
|---|---|---|---|---|
| motor | %89,2 | %71,7 | 79,5 | 26/110 = %23,6 |
| ms-marco vetosu | %91,4 | %53,3 | 67,4 | 15/110 = %13,6 |

Veto, düz cümle hatasını geliştirmedeki gibi azalttı (11 düzeltme, 0 bozma), ama finalde geliştirmeden **çok daha
fazla deyim kaçırdı** (recall −18 puan; geliştirmede −14). Görevin "recall korunsun" şartını sağlamadığı ve modelin
eğitim verisi (MS MARCO) ticari kullanımı kısıtladığı için **önerilmiyor**.
