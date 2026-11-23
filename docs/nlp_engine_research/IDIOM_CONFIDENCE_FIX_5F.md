# Deyimlerde yanlış kesinlik ve güvenli fallback (Görev 5F)

Tarih: 23 Kasım 2026. Temel: `main` @ `bf30630` (#112 ve #113 birleşmiş hâli). Flutter 3.50.0 (CI ile aynı).
Bu belge Görev 5E'nin (Draft PR #115) bulgusuna dayanır, ama #115'i gerektirmez: #115'teki POS etiketleyicisi ve
araştırma betikleri bu dala alınmadı.

## 1. Kısa sonuç

- 5E'nin bildirdiği 3 hata gerçek MAGPIE cümleleriyle **tekrar üretildi** (MAGPIE id 51620, 32520, 50299; üçü de
  annotatör uzlaşması 1,0 ile "düz" etiketli). Üçünde de motor deyimi **kesin** gösterdi ve
  `SenseEngine.fit` kartı **onayladı** (yani otomatik kart puanlaması yanlış okumayı "doğru" sayabilirdi).
- Kök neden: 5B'nin "sıradan kelimelerden oluşan deyim asla kesin değildir" kuralı, sözcük sözcük okumanın
  **Türkçesi sözlükte varsa** çalışıyordu. Bu üç deyimde sözcük sözcük adayları var ama Türkçeleri yok
  (`poacher`, `gamekeeper`, `circle`ın ilgili fiil anlamları) ya da hiç aday yok (`she'll`). Yani "literal
  karşılığın sözlükte bulunmaması" mecaz lehine kanıt sayılıyordu.
- Düzeltme (genel kural, kelime listesi yok): bir kalıbın sözcük sözcük okunabilmesi, o okumanın Türkçesine değil,
  **kelimelerin sözlükte kendi anlamı olmasına** bakılarak belirlenir. Phrasal verb'ler kendi kurallarıyla kalır.
- Ek olarak iki küçük, genel hata düzeltildi: (a) kart puanlama yolu (`SenseQuery.find`) kalıbı **cümle sınırının
  ötesinde** de eşleştirebiliyordu; (b) motorun bir önbelleği (WordNet anlamı ortak olan iki kelime, ör.
  "draw"/"get") yüzünden **aynı sorgunun cevabı daha önce neye dokunulduğuna bağlıydı** (panel ile kart birbirini
  tutmayabiliyordu).

## 2. "Kesin" nerede üretiliyor, nereye gidiyor

| adım | yer | ne yapar |
|---|---|---|
| eşleşme | `PhraseMatcher.match` (`lib/nlp/text.dart`) | kalıbı cümlede arar; `text:` verilince tek cümle içinde kalır |
| anlam ve güven | `SenseEngine._resolvePhrase` → `_decide` (`lib/nlp/context_sense.dart`) | kalıp anlamları ile sözcük sözcük okuma yarışır; `sure` / `likely` / `none` |
| 5B kuralı | `_resolvePhrase`, `canBeLiteral` | sözcük sözcük okunabilen kalıbı `sure` → `likely` indirir |
| panel | `ContextSenseCard` (`lib/ui/context_sense_card.dart`) | `sure` kesin, `likely` "olası" gösterilir; panel tek cümlenin belirteçlerini verir |
| kart | `SenseEngine.fit` ← `ReviewQuiz.confirms` (`lib/data/review_quiz.dart`) | kalıp yalnız `sure` ise onaylanır; onaylanmayan kart puanlanmaz, düz kart gösterilir |

Hata zinciri: `canBeLiteral = false` (Türkçeli literal aday yok) → `_decide` "clear" → `sure` → `fit` `confirmed`
→ kart otomatik doğru sayılır.

## 3. Gerçek örnekler (kaynakta bulundu, uydurulmadı)

MAGPIE (Haagsma, Bos, Nissim 2020; etiketler CC BY 4.0, cümleler BNC). BNC metni yeniden dağıtılamadığı için
cümleler depoya konmadı; test, `MAGPIE_JSONL` verilince bu kimliklerdeki cümleleri yerelden okur.

| MAGPIE id | deyim | varyant | main | sözcük sözcük adaylar | 5F |
|---|---|---|---|---|---|
| 51620 | poacher turned gamekeeper | identical ("a literal case of …") | sure, kart onaylı | 3 aday, hiçbirinde Türkçe yok | likely, kart puanlanmaz |
| 32520 | circle the wagons | misc ("circling its wagons") | sure, kart onaylı | 3 fiil adayı, Türkçe yok | likely, kart puanlanmaz |
| 50299 | she'll be right | dashes ("she'll be right over") | sure, kart onaylı | **hiç aday yok** | likely, kart puanlanmaz |

Bütün uzlaşma-1,0 havuzunda (aşağıda §5.3) bir dördüncü örnek de çıktı: "chew the cud" (düz, sure, kart onaylı).

Hangi nedenler **değil**: eşik değil (puan farkı büyük, "clear"), POS değil (kalıp anlamının türü yok),
cümle sınırı değil (üçü tek cümle), fallback değil. Neden: **literal aday yokluğu / Türkçesizliği** + buna bağlı
olarak bağlamın hiç tartılmaması. Bağlam eksikliği ikincil: "a literal case of" gibi açık bir işaret var ama motor
bunu okuyan bir kurala sahip değil (bu görevde eklenmedi, §8).

## 4. Uygulanan genel kural

`lib/nlp/context_sense.dart`:

1. `canBeLiteral = e.cat != 'phrasal_verbs' && (cands.any((c) => c.literal) || _ordinaryWords(q.tokens, idx))`
   (eskisi: `cands.any((c) => c.literal && c.tr.isNotEmpty)`). `_ordinaryWords`: kalıbın her kelimesi bir dilbilgisi
   kelimesi ya da sözlükte (Türkçesi olsun olmasın) anlamı olan bir kelime mi; "she'll" → "she", tireli kelime
   parça parça. Yalnız kendi başına anlamı olmayan bir kelime içeren kalıp kesin olabilir.
   Gerekçe: deyimin **bulunması** mecaz kullanımın **kanıtı değildir**; motorda mecazı kanıtlayan bir sinyal yok
   (5E: ayıran tek şey denenmiş modellerdi ve lisans/recall nedeniyle önerilmedi), o hâlde kesinlik yalnız düz
   okumanın imkânsız olduğu durumda verilir.
2. `SenseQuery.find` artık `matcher.match(toks, text: sentence)` çağırır: kart yolunda da kalıp tek cümle içinde
   olmalı (panel zaten öyleydi).
3. `_Profile` önbellek anahtarına adayın kelimesi eklendi (`id|lemma|literal`). Önceden WordNet anlamı iki kelimede
   ortaksa, örnek cümle profili hangi kelime önce sorulduysa onun için hesaplanıp diğerine de kullanılıyordu.
4. `SenseEngine.version` 3 → 4 (önbellek ve geri bildirim kayıtlarında eski motorun seçimleri ayrılsın).

Değişmeyenler: arayüz (yeni UI yok; "olası" gösterimi ve diğer anlamlar listesi aynen), phrasal verb kuralları,
kart güvenlik kuralları (hiçbiri gevşetilmedi; yalnız daha az şey onaylanır), sözlükler, kullanıcı verisi, kayıt
biçimleri, bağımlılıklar.

## 5. Değerlendirme

### 5.1 Kümeler

| küme | kaynak | satır | etiket | kullanım |
|---|---|---|---|---|
| `dev5f_magpie.tsv` | MAGPIE, uzlaşma 0,70–0,99 | 407 deyimsel / 184 düz, 269 deyim | insan (kitle) çoğunluk etiketi | geliştirme, teşhis |
| `final5f_magpie.tsv` | aynı havuz, **başka deyimler** | 828 deyimsel / 416 düz, 537 deyim | insan çoğunluk etiketi | **tek ölçüm** |
| `test/data/idiom_5f_claude.tsv` | **Claude yazdı ve etiketledi** | 70 (dev 22 / final 48) | Claude (AI) — insan doğrulaması **değil** | MAGPIE'de olmayan durumlar |
| `seen5f_conf1.tsv` | MAGPIE uzlaşma 1,0, tüm sözlük deyimleri | 22.724 / 7.477 | insan oybirliği | **görülmüş** havuz; yalnız hata sıklığını saymak için |

- Bağımsızlık: önceki bütün çekimler (5A/5B/5E, `tools/eval/build_*.py`, `build_final_5e.py`) yalnız uzlaşma 1,0
  cümleleri aldı; 5F dev/final yalnız 0,70–0,99 aralığını alır, yani **hiçbir önceki cümle bu kümelerde olamaz**.
  Deyim **türü** örtüşmesi önlenemedi: önceki deyim listeleri yalnız yerelde tutulmuştu ve aynı rastgele sayı
  zinciriyle bu ortamda birebir yeniden üretilemedi. Bunun etkisi küçüktür çünkü 5F kuralında bu kümelerde
  ayarlanan bir eşik yok.
- Dev/final ayrımı deyime göre (deyimin sha256'sı); iki kümede ortak deyim **0**. 5E'nin üç deyimi final dışında
  tutuldu (regresyon testleri onlar). Claude kümesinde de ayrım kalıba göre.
- Final dosyası ölçümden önce kilitlendi: `tools/nlp_research_5f/final5f_LOCKED.sha256`
  (`6874e650…`). Baseline ve 5F aynı komutla, aynı satır sırasıyla **bir kez** çalıştırıldı; sonra ayar yapılmadı.
- #115'in final kümesi (5E) bu görevde ne ayar ne ölçüm için kullanıldı; yalnız tarihsel sonuç olarak anılır.
- Uzlaşma < 1,0 etiketler gürültülüdür (ör. dev'de "on the trot" düz görünen bir cümlede deyimsel etiketli);
  bu, oranları her iki sistem için aynı yönde etkiler.

Komutlar (depo kökünden):

```
python3 -I tools/nlp_research_5f/build_sets_5f.py assets/dict.db MAGPIE_unfiltered.jsonl OUT [seen]
NLP_5F_SETS=final=OUT/final5f_magpie.tsv,claude=test/data/idiom_5f_claude.tsv NLP_5F_OUT=W \
  flutter test tools/nlp_research_5f/dump_5f_test.dart        # main çalışma ağacında ve bu dalda
python3 -I tools/nlp_research_5f/metrics_5f.py BASE/final.jsonl FIX/final.jsonl
```

MAGPIE_unfiltered.jsonl sha256 `541ee535…`, dict.db `ab4a7a53…` (değişmedi).

### 5.2 Kilitli final (1.244 cümle, bir kez)

| ölçü | baseline (main) | 5F |
|---|---|---|
| deyim bulundu (deyimsel satırlar) | 670/828 = %80,9 | 670/828 = %80,9 |
| precision | 562/730 = %77,0 [74–80] | 560/729 = %76,8 [74–80] |
| recall | 562/828 = %67,9 [65–71] | 560/828 = %67,6 [64–71] |
| F1 | 72,1 | 71,9 |
| düz → deyim gösterildi | 168/416 = %40,4 [36–45] | 169/416 = %40,6 [36–45] |
| **yanlış kesin** (düz satır, deyim kesin) | 0/416 = %0 [0–1] | 0/416 = %0 [0–1] |
| kesin kapsamı (tüm satırlar) | 4/1.244 = %0,3 | 0/1.244 = %0 |
| kesin içinde yanlış (yüksek güven alt kümesi) | 0/4 | – (kesin yok) |
| kart yanlış onay (düz satır) | 0/245 | 0/245 |
| kart onayı (deyimsel satır) | 4/481 = %0,8 | 0/481 |
| eşleştirilmiş: deyim gösterilen deyimsel satır | – | 2 kayıp, 0 kazanç (McNemar p = 0,5) |
| süre (çözüm başına, masaüstü) | 3,65 ms | 3,74 ms |

Okuma: bu bağımsız kümede main'in hiç yanlış kesini **yoktu**, yani iyileşme burada **gösterilemez**. Ölçülen etki
maliyettir: doğru 4 kesin karar "olası"ya indi ve bu 4 kart artık otomatik puanlanmıyor (kullanıcı kendisi
değerlendirir). Recall'daki 2 kayıp ("rub shoulders", "reach for the stars") önbellek düzeltmesinden (§4.3),
kesinlik kuralından değil; fark anlamlı değil.

### 5.3 Hata ne kadar sık? (görülmüş havuz, 30.201 cümle; ayar yok)

| ölçü | baseline | 5F |
|---|---|---|
| yanlış kesin (düz satır) | 4/7.477 = %0,05 | **0/7.477** |
| kesin deyim kararlarında yanlış | 4/131 = %3,1 [1–8] | – |
| kart yanlış onay (düz satır) | 4/4.704 | **0/4.704** |
| kart onayı (deyimsel satır) | 123/12.913 = %1,0 | 0/12.913 |
| recall / precision | %76,5 / %86,0 | %76,5 / %86,0 |
| eşleştirilmiş: yanlış kesin | – | 4 düzeldi, 0 bozuldu (p = 0,12) |

Hata nadir ama gerçek: kesin gösterilen deyim kararlarının yaklaşık %3'ü düz kullanımdı ve hepsi kartı yanlışlıkla
onaylıyordu. 5F'de sıradan kelimelerden oluşan deyim hiç kesin olmuyor; bedeli, deyimsel kullanımların %1'inde
kartın otomatik değil elle değerlendirilmesi. 5E finalinde de (tarihsel, 110 düz cümle) aynı tablo vardı: 3 düz
cümle kesin.

### 5.4 Claude'un yazdığı kümede (AI etiketli; insan doğrulaması değil)

Final kısmı (48 satır): main ile 5F aynı (yanlış kesin 0/20, kart yanlış onay 0/20, recall 28/28). Dev kısmında
tek fark: bölünmüş "look the word up" kart yolunda artık bulunuyor (cümle metni verildiği için; panel zaten
buluyordu). Bu küme, MAGPIE'de olmayan durumların (cümle sınırı, parçalı deyim, olumsuzluk, alıntı, özel isim,
bölünmüş phrasal verb, eşdizim) motorda bozulmadığını gösterir; sayıları istatistik iddiası taşımaz.

### 5.5 Kelime anlamı (önbellek düzeltmesinin yan etkisi; depodaki SemCor kümeleri, görülmüş veri)

| küme | ölçü | main | 5F |
|---|---|---|---|
| sense_eval_semcor | yanlış cevabın doğru puanlanması (bugünkü kural) | 21/260 | 20/260 |
| | bağlamdaki anlam doğru | 175 | 174 |
| sense_eval_semcor_fresh | yanlış cevabın doğru puanlanması | 22/260 | 22/260 |
| | yeni kart: yanlış kayıt | 13 | 12 |
| | bağlamdaki anlam doğru | 182 | 183 |
| sense_eval_semcor_dev | hepsi | aynı | aynı |

Fark ±1 satır; anlamlı değil, yönü karışık. Beklenen budur: düzeltme, her sorgunun "temiz süreçte tek başına
sorulduğunda" alacağı cevabı her zaman verir.

## 6. Testler ve CI

- Yeni: `test/idiom_confidence_5f_test.dart` (10 test). main'de (MAGPIE verilerek) 7'si **başarısız**, bu dalda hepsi geçiyor:
  üç deyimin düz kullanımı (Claude'un yazdığı benzer cümleler, aynı mekanizma: Türkçeli literal aday yok) kesin
  değil ve kart onaylamıyor; aynı deyimlerin mecaz kullanımı hâlâ bulunuyor ve "olası" gösteriliyor; iki cümlelik
  kart bağlamında kalıp bulunmuyor; parçalı deyim eşleşmiyor; gerçek deyimler gösteriliyor ama kesin/puanlı değil;
  phrasal verb'ler aynı; sorgu sırası cevabı değiştirmiyor. Üç gerçek MAGPIE cümlesi testi `MAGPIE_JSONL`
  verilince çalışır (yerelde çalıştırıldı ve geçti; CI'da veri olmadığı için **atlanır**, geçmiş sayılmamalı).
- `flutter test` (tümü): bu dal 529 geçti, 12 atlandı, 3 başarısız; main 520 geçti, 11 atlandı, 3 başarısız
  (fark: yeni dosyanın 9 geçen + 1 atlanan testi). İlgili dosyalar MAGPIE ile birlikte
  (`idiom_confidence_5f`, `sense_confidence`, `context_sense`, `context_sense_ui`, `review_quiz`, `phrase_*`):
  87/87 geçti.
- `flutter analyze`: main 124, bu dal 124 bulgu; hepsi önceden var olan `info`, hata/uyarı 0, yeni dosyalarda 0.
- Python: `tools/release/test_release_check.py` 23/23, `release_check.py check-workflows` geçti,
  `tools/lexicon_provenance/test_provenance.py` "unchanged: true".
- Bilinen ortam sınırı: `text_repair_test`, `picture_book_test`, `import_completeness_test` bu ortamda PDFium
  kütüphanesi olmadığı için `setUpAll`'da düşüyor; main'de de birebir aynı 3 hata var. CI'da ayrıca görülecek.

## 7. Boyut, bağımlılık, lisans, veri

- Yeni bağımlılık yok (`pubspec.yaml`/`pubspec.lock` değişmedi), yeni varlık/model yok, ağ çağrısı yok;
  uygulama boyutu değişmez (yalnız birkaç satır Dart). Değerlendirme betikleri Python standart kütüphanesi.
- Lisans: yeni üçüncü taraf veri depoya girmedi. MAGPIE etiketleri CC BY 4.0, BNC cümleleri yalnız yerel.
  Claude kümesi bu proje için yazıldı (GPL-3.0). #114'ün lisans/yayın kapısına dokunulmadı.
- `assets/dict.db` ve `assets/tr_en.db` SHA-256 başta ve sonda aynı ve main ile aynı:
  `ab4a7a53b9fc5e1edbd682da5cb7193c0c109f93236655385bf6231d90221a9c`,
  `49a661b9c8951259ab13fd6a95aa77b68e16f1c4716669dacfb6c12521cfa818`.
- Kullanıcı kitapları, kartları, öğrenme kayıtları ve yedekleri okunmadı/değişmedi; kayıt biçimi aynı.
  `SenseEngine.version` artışı yalnız bellekteki önbelleği ve yeni geri bildirim kayıtlarının motor sürümü
  alanını etkiler.

## 8. Riskler ve kalan işler

- **Ana ödünleşim:** sıradan kelimelerden oluşan deyimler artık hiç "kesin" değil; doğru kesin kararların küçük bir
  kısmı (finalde 4/1.244, görülmüş havuzda deyimsel satırların %1'i) "olası"ya iner ve bu deyim kartları otomatik
  puanlanmaz. Bağımsız finalde yanlış kesin zaten 0 olduğu için iyileşme orada istatistiksel olarak
  gösterilemedi; kanıt gerçek 3 (+1) örnek ve görülmüş havuzdaki 4 → 0. Birleştirme kararı bu ödünleşimin kabulüne
  bağlı.
- Düz kullanımın deyim sanılması (%40) bu görevin kapsamı dışında kaldı; kesinliği değil, gösterilen anlamı
  etkiler ("olası" olarak). Bunu azaltmak bir sınıflandırıcı/model ister (5E: lisans ve recall sorunları).
- "a literal case of", tırnak içi alıntı gibi açık düz-kullanım işaretlerini okuyan kural yok.
- Araya kelime girmiş ve iyelikli deyimler hâlâ bulunmuyor (5E bulgusu; eşleştiricinin işi).
- Mobil cihazda ölçüm yapılmadı (bulut ortamı); masaüstünde süre farkı ölçüm gürültüsü içinde.
