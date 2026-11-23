# Deyim mi, düz kullanım mı? Bağlama göre ayrım ve güvenli kalıp eşleştirme (Görev 5G)

Tarih: 23 Kasım 2026. Temel: PR #116 (Görev 5F) head `ca737ad`; bu dal onun üstünde (stacked). Flutter 3.50.0.
Bu belge #115'in (5E) koduna dayanmaz; 5E'nin POS etiketleyicisi bu dala alınmadı.

## 1. Kısa sonuç

- **Ne değişti:** Kalıbı bir edat öbeği olan deyim (`on a roll`, `for a song`, `under a cloud`) cümlede **biçimi
  değişmiş** geçtiğinde (başka belirleyici: "on *the* roll", "to *our* turn"; başka sayı: "for the song*s*",
  "in the dock*s*") artık sözcük sözcük okunuyor; deyim anlamı "diğer anlamlar" listesinde kalıyor. Kural genel
  (deyimlerin biçimce sabit olması; Fazly, Cook & Stevenson 2009), kelime listesi yok. Ayrıca tırnak içinde ya da
  "the idiom …", "the phrase …" ardından geçen kalıp (metadil) hiçbir zaman "kesin" olmuyor.
- **Kilitli bağımsız finalde** (895 cümle; 5E/5F'de hiç kullanılmamış cümleler, tek çalıştırma):
  düz cümlenin deyim gösterilmesi **134/359 = %37,3 → 120/359 = %33,4** (14 düzeldi, 0 bozuldu; McNemar
  p = 0,0001). Deyim recall'u %66,4 → %66,0 (2 kayıp, anlamlı değil, p = 0,5). Precision %72,7 → %74,7.
  Yanlış "kesin" 0 → 0, yanlış kart onayı 0 → 0.
- Bu iyileşme **küçük ama gerçek**: düz kullanım hatalarının yaklaşık onda biri. Kalanların çoğu cümlenin
  anlamını anlamadan ayrılamıyor (§3); denenen öğrenilmiş yöntemlerin hiçbiri bu setlerde kurallardan iyi değildi
  (§4). Bu yüzden büyük bir model ya da sınıflandırıcı **eklenmedi**.
- Kalıp eşleştirme genişletmesi (iyelikli "someone's", araya sözcük giren deyimler) ölçüldü: deyim bulma artıyor
  ama düz cümle hatası **daha çok** artıyor. Deneysel bayrakta (**kapalı**) bırakıldı.
- Uygulamada `SenseEngine.defaultLiteralCues = true` (tek satırla kapatılır; kapalıyken motor 5F ile birebir aynı,
  testli). Birleştirme kararı kullanıcınındır (§9).

## 2. Akış: "bulundu", "gösterildi", "kesin", "kart onaylandı"

| adım | yer | sonuç |
|---|---|---|
| bulundu | `PhraseMatcher.match` (`lib/nlp/text.dart`) | kalıp cümlede eşleşti (tek cümle içinde) |
| gösterildi | `SenseEngine._resolvePhrase` → `_decide` (`lib/nlp/context_sense.dart`) | deyim anlamı mı (`cat` dolu, `literalPhrase` boş) yoksa sözcük sözcük okuma mı |
| kesin | aynı yer, `canBeLiteral` (5B/5F) | sıradan kelimeli deyim asla `sure` değil |
| kart onayı | `SenseEngine.fit` ← `ReviewQuiz` (`lib/data/review_quiz.dart`), kart yolu `SenseQuery.find` | yalnız `sure` deyim kartı otomatik puanlar |
| panel | `ContextSenseCard` | `likely` "olası" diye gösterilir |

Bu dört ölçü raporda hep ayrı tutuldu. 5F'den sonra "kesin" ve "kart onayı" düz cümlelerde zaten 0; 5G'nin konusu
ikinci satır: **düz cümlede deyim anlamının "olası" olarak gösterilmesi**.

## 3. Aşama 1: Kök nedenler (yalnız geliştirme kümesinde)

Geliştirme kümesi (`dev5g`, §5.1): 1.919 deyimsel, 350 düz cümle. Baseline = 5F motoru.

### 3.1 Yanlış deyim gösterimi (düz cümle, deyim gösterildi): 144/350 = %41,1

- Eşleştirici düz cümlelerin %57'sini buluyor (199/350); bulunan düz cümlelerin **%72'sinde** deyim gösteriliyor,
  bulunan deyimsel cümlelerde %88'inde. Yani motorun puanı iki kullanımı zayıf ayırıyor: deyim–düz puan farkının
  AUC'si **0,63** (0,5 = yazı tura).
- Motorun gerekçesine göre (144): taslak (doğrulanmamış AI) anlam 47, yakın rakip 46, "sıradan kelimeler" (5F
  kuralı, olası) 19, "deyim ya da kelimeler" 18, açık kanıt yok 14. Hiçbiri tek başına düz kullanımın işareti değil.
- Rastgele 70 hatalı cümleyi okudum (**Claude'un okuması, insan değerlendirmesi değil**):

| tür | sayı | örnek tür (BNC cümlesi alıntılanmadı) |
|---|---|---|
| gerçekten düz, yüzeyde işaret yok | 34 | oyun parkındaki salıncaklar, yüze tükürmek, gerçek yeşil ışık, sözlük anlamıyla "dead and buried" |
| **biçim değişmiş** (belirleyici/sayı) | 10 | "have his ball", "for the songs", "men and boys", "to our turn" |
| etiket gürültüsü (bence deyimsel ama "düz" etiketli) | 10 | uzlaşma < 1,0 olan MAGPIE etiketleri |
| sözcük türü uyuşmazlığı: fiil deyimi isim öbeği içinde | 6 | "the smell of burning rubber" |
| isim öbeği sürüyor (eşdizim) | 5 | "oil and water levels", "in the raw water" |
| belirsiz | 3 | |
| komşu kelimenin parçacığı (phrasal verb) | 2 | "filled the bill out", "take off the record" |
| alıntı/metadil, olumsuzlama, özel isim, cümle sınırı | 0 | MAGPIE cümleleri tek cümle; bu durumlar Claude kümesinde ve testlerde |

### 3.2 Gerçek deyimin gösterilmemesi: 452/1.919

- **Bulunamadı (258, %13,4):** MAGPIE varyant türü: çekim + başka değişiklik 115, çeşitli 31, **iyelik 28**,
  birleşik 25, **araya sözcük girmesi 24**, çekim 19. Sözlükte 218 kalıp "someone's" ile yazılmış ve eşleştirici
  bunu hiçbir iyelikle eşleştirmiyor ("burst his bubble" bulunmuyor); "one's" yalnız iyelik zamirlerini alıyor.
- **Bulundu, sözcük sözcük okuma kazandı (194):** açık fark 85, kelimenin anlamının Türkçesi yok (hiçbir şey
  gösterilmiyor) 58, yakın 28, diğer 23.

### 3.3 Sonuç

Yüksek kesinlikli, genel ve ölçülebilir tek sinyal **biçim değişikliği**; o da yalnız edat öbeği deyimlerde
(fiil deyimlerinde iyelik deyimin olağan biçimi: "stake his claim", "press your flesh"). Geliştirme + ayar
kümelerinde biçim işaretli cümleler: edat öbeğinde **31 düz / 2 deyimsel**, diğer kategorilerde 30 düz / 38
deyimsel (bu yüzden yalnız edat öbeğine uygulandı). İsim öbeği sürmesi edat öbeklerinde motorda zaten var
(5B, `continues`); diğer kategorilerde 15 düz / 59 deyimsel: işaret değil.

## 4. Aşama 2: Aday yöntemler (geliştirme ve ayar kümeleri; final kullanılmadı)

| # | yöntem | dev: düz → deyim | dev: deyim recall | tune: düz → deyim | tune: recall | karar |
|---|---|---|---|---|---|---|
| 1 | 5F motoru (baseline) | 144/350 = %41,1 | 1.467/1.919 = %76,4 | 85/211 = %40,3 | 674/873 = %77,2 | referans |
| 2 | **genel kurallar** (biçim değişikliği + metadil) | 138/350 = %39,4 | 1.466 | **72/211 = %34,1** | 673 | **seçildi** |
| 3 | lojistik regresyon, 27 sayısal özellik (motor puanları, işaretler, kategori), deyime göre gruplu 5 katlı CV, veto p ≥ 0,5 | −11 hata | −8 deyim | – | – | kurallardan iyi değil; MAGPIE'den öğrenilmiş ağırlık |
| 3b | aynı, gradient boosting | −7 | −8 | – | – | aynı |
| 4a | WordNet tanım örtüşmesi (Sporleder & Li 2009 tarzı bağlam uyumu) | AUC 0,55 | | | | işaret yok |
| 4b | GloVe 6B-100d kelime vektörleriyle bağlam uyumu (araştırma) | AUC 0,54 | | AUC 0,61 | | motor puanından (0,63) kötü |
| 5a | all-MiniLM-L6-v2 bi-encoder (cümle ↔ deyim tanımı vs. kelime tanımları; araştırma) | AUC 0,58 | | AUC 0,62 | | |
| 5b | ms-marco-MiniLM-L6-v2 cross-encoder (5E'nin en iyisi; araştırma) | AUC 0,66 | | AUC 0,62 | | |
| 5c | 5b ile veto, en düşük %5 | −6 / 136 | −73 / 1.427 | −4 / 83 | −34 / 670 | 1 hata için ~8 deyim kaybı: **ret** |
| 6 | geniş eşleştirme (iyelik + 1 ara sözcük), §6 | 172/350 (+28) | 1.564 (+97) | 110/211 (+25) | 702 (+28) | düz hata artıyor: **kapalı** |

- 3: POS etiketleyici (5E) kullanılmadı: kodu #115'te birleşmemiş ve modelin lisansı (UD EWT, CC BY-SA 4.0) 5C
  onayını bekliyor. Bağımlılık/ağaç ayrıştırıcısı yok; dilbilgisi ipuçları (sözcük türü, isim öbeği) sözlüğün
  kendi sözcük türü bilgisiyle denendi (dev + tune'da fiil deyimi isim öbeği içinde: 57 deyimsel / 11 düz; işaret
  değil).
- 5: Modeller yalnız bu makinede, yalnız dev/tune cümleleriyle çalıştırıldı; hiçbir kullanıcı metni dışarı
  gitmedi. 5E'nin tespitleri geçerli: MiniLM ve ms-marco'nun eğitim verisinde MS MARCO (ticari olmayan araştırma)
  var; GlossBERT kaynağı doğrulanamıyor. Bu görevde de hiçbiri **kurallardan iyi değil**; üretime adayı yok.
- GloVe: ağırlıklar PDDL, ama eğitim verisinde Gigaword (LDC lisanslı) var; yalnız araştırma. Uygulamaya girmedi.
- Final kümesine yalnız 1 (baseline) ve 2 (seçilen) gitti.

## 5. Aşama 3: Veri ve lisans

### 5.1 Kümeler (`tools/nlp_research_5g/build_sets_5g.py`)

| küme | cümle | deyim | kaynak / kural | kullanım |
|---|---|---|---|---|
| `dev5g_magpie.tsv` | 1.919 deyimsel / 350 düz | 423 | 5F final dışı deyimler; MAGPIE uzlaşma ≥ 0,70 (1,0 dahil, görülmüş olabilir) | kurallar, teşhis, sınıflandırıcı eğitimi |
| `tune5g_magpie.tsv` | 873 / 211 | 197 | aynı havuz, başka deyimler | yöntem seçimi |
| `final5g_magpie.tsv` | **536 / 359** | **288** | **5F final deyimleri**, uzlaşma 0,70–0,99, **5F'nin almadığı** cümleler, deyim+etiket başına ≤ 3 | **tek ölçüm** |
| `test/data/idiom_5f_claude.tsv` (5F'den) | 70 | | Claude yazdı ve etiketledi (AI) | MAGPIE'de olmayan durumlar; istatistik iddiası yok |
| `seen5f_conf1.tsv` (5F'den) | 22.724 / 7.477 | | MAGPIE uzlaşma 1,0, görülmüş havuz | yalnız hata sıklığı; ayar yok |

- **Cümle bağımsızlığı:** final cümlelerinin hiçbiri 5A/5B/5E (yalnız uzlaşma 1,0 çekti) ya da 5F (dev/final, her
  iki küme yeniden üretildi ve 5F kilit hash'i doğrulandı) kümelerinde yok: kontrol 0.
- **Deyim bağımsızlığı:** final deyimleri geliştirme/ayar kümelerinde **yok** (0 ortak). Final deyimleri 5F'nin
  final deyimleri: 5F'de yalnız bir kez ölçüldüler, hiçbir şey onlarla tasarlanmadı. 5A/5B/5E'nin deyim listeleri
  yerelde tutulduğu için birebir dışlanamadı: **tür düzeyinde örtüşme olabilir** (kural ayarı finalde yapılmadığı
  için etkisi sınırlı).
- **Kilit:** final hash'i (`ce55c3bb…`) hiçbir sistem çalışmadan önce commit edildi (`e823e64`,
  `tools/nlp_research_5g/final5g_LOCKED.sha256`). Aday kod da finalden önce donduruldu (`16a1de6`). Baseline ve aday
  aynı satır sırasıyla **bir kez** çalıştı; sonrasında kural değişmedi (sonraki commit yalnız varsayılan bayrağı ve
  sürüm etiketini değiştirdi).
- **Etiket kalitesi:** uzlaşma 0,70–0,99 etiketleri çoğunluk oyudur ve gürültülüdür (§3.1'de okuduğum 70 hatanın
  ~10'u). İki sistemi aynı yönde etkiler. Deyim türü bazında ayrım: kategori (sözlük) ve MAGPIE varyant türü
  raporlandı (§7.3).
- Hash'ler: MAGPIE_unfiltered.jsonl `541ee535e93d…` (5F ile aynı), dict.db `ab4a7a53b9fc…`,
  dev5g `701e5df29c3a…`, tune5g `abf10f953864…`, final5g `ce55c3bb456d…`.

### 5.2 Lisans

- MAGPIE (Haagsma, Bos, Nissim 2020): etiketler CC BY 4.0; cümleler çoğunlukla BNC ve **yeniden dağıtılamaz**:
  depoya hiçbir MAGPIE/BNC cümlesi konmadı, bu belgede de alıntılanmadı (yalnız deyim adı ve MAGPIE id). Kümeler
  betikle yerelde yeniden üretilir.
- Üretime giren yalnız kendi kodumuz (GPL-3.0), yeni veri/model/bağımlılık yok. Testlerdeki cümleleri **Claude
  yazdı** (AI); insan etiketli altın veri değildir.
- Sınıflandırıcı ağırlıkları (BNC cümlelerinden türetilmiş özellikler) depoya konmadı ve kullanılmıyor.

## 6. Kalıp eşleştirme (ayrı ölçüldü; deneysel, kapalı)

`PhraseMatcher.match(variants: true)`: "someone's"/"one's" her iyelikle ("his", "Oliver's") eşleşir; üç ve daha
uzun kalıpta iki kelime arasına tek bir niteleyici (sıfat, zarf, -ing/-ed) girebilir ("runs the whole gamut").
Phrasal verb'ler ve iki kelimelik kalıplar hariç. Varsayılan `false`: uygulama davranışı değişmedi.

| | dev deyimsel | dev düz | tune deyimsel | tune düz |
|---|---|---|---|---|
| bulunan | 1.661 → 1.768 | 199 → 234 | 783 → 815 | 101 → 134 |
| deyim gösterilen | 1.467 → 1.564 (+%5,1 puan) | 144 → 172 (**+%8,0 puan**) | 674 → 702 (+%3,2) | 85 → 110 (**+%11,8**) |
| yeni eşleşmeler: iyelik | 87 | 19 | 20 | 15 |
| yeni eşleşmeler: ara sözcük | 23 | 16 | 12 | 19 |

Araya sözcük giren eşleşmeler deyimsel ile düz arasında yarı yarıya: sıfatla nitelenen deyim çoğunlukla düz
kullanımdır (deyimler nitelemeye kapalıdır). İyelik eşleşmesi daha iyi ama yine de düz hata oranını yükseltiyor
("open her eyes", "wipe her eyes"). Kabul koşulu ("eşleşme recall'u artarken yanlış pozitifler artmamalı")
sağlanmadığı için açılmadı; finalde de ölçülmedi.

## 7. Aşama 4: Kilitli final sonuçları (tek çalıştırma)

Komut (depo kökünden):

```
python3 -I tools/nlp_research_5f/build_sets_5f.py assets/dict.db MAGPIE_unfiltered.jsonl S5F seen
python3 -I tools/nlp_research_5g/build_sets_5g.py assets/dict.db MAGPIE_unfiltered.jsonl S5F S5G
NLP_5G_MODE=baseline|cues NLP_5G_SETS=final5g=S5G/final5g_magpie.tsv NLP_5G_OUT=OUT/<mode> \
  flutter test tools/nlp_research_5g/dump_5g_test.dart
python3 -I tools/nlp_research_5g/metrics_5g.py OUT/baseline/final5g.jsonl OUT/cues/final5g.jsonl
```

### 7.1 5G finali (895 cümle: 536 deyimsel, 359 düz, 288 deyim)

| ölçü | baseline (5F) | 5G | eşleştirilmiş |
|---|---|---|---|
| **düz → deyim gösterildi** | 134/359 = %37,3 [32,5–42,4] | **120/359 = %33,4 [28,7–38,5]** | 14 düzeldi, 0 bozuldu, **p = 0,00012** |
| kalıp eşleşme recall'u (deyimsel) | 444/536 = %82,8 | 444/536 = %82,8 | değişmedi |
| precision | 356/490 = %72,7 [68,5–76,4] | 354/474 = %74,7 [70,6–78,4] | |
| recall | 356/536 = %66,4 [62,3–70,3] | 354/536 = %66,0 [61,9–69,9] | 2 kayıp, 0 kazanç, p = 0,5 |
| F1 | 69,4 | 70,1 | |
| yanlış kesin (düz, deyim kesin) | 0/359 [0–1,1] | 0/359 [0–1,1] | 0 / 0 |
| kesin kapsamı | 0/895 | 0/895 | doğru kesin kaybı 0 |
| kart yanlış otomatik onay (düz) | 0/221 [0–1,7] | 0/221 | 0 / 0 |
| kart doğru otomatik onay (deyimsel) | 0/328 | 0/328 | |
| kart elle değerlendirme (deyimsel) | 328/328 = %100 | 328/328 = %100 | |

Köşeli parantez: Wilson %95 güven aralığı. Tek tek oranların aralıkları örtüşüyor; anlamlılık eşleştirilmiş
testten (aynı cümleler) gelir. Kesin ve kart sütunlarının 0 olması 5F'nin sonucudur: sıradan kelimeli deyimler
zaten hiç kesin değil ve deyim kartı otomatik puanlanmıyor; 5G bunu ne iyileştirdi ne bozdu.

Değişen 16 satır (MAGPIE id, deyim, işaret; cümle metni yok):

| yön | satırlar |
|---|---|
| düz, düzeldi (14) | 32812, 18843 across the board (sayı); 38387 down the drain (sayı); 40476 in a fog; 42425 in the saddle; 28534 in the soup; 10240, 47171 in the swim; 3288 on the horn; 37049, 20641 under a cloud (belirleyici); 52345 on the button; 13777 on the cuff; 10468 round the bend (sayı) |
| deyimsel, kayıp (2) | 22469 down the road (belirleyici); 69 on the ball (belirleyici) |

Düzelen 14 düz satırın 4'ünde sözcük sözcük okumanın Türkçesi sözlükte yok: orada artık yanlış deyim anlamı yerine
**hiçbir anlam** gösterilmiyor (kelimelerin kendi panelleri açık kalır). Kayıp 2 deyimden biri ("on the ball") de
aynı nedenle boş kalıyor.

### 7.2 Ek kanıt (bağımsız final değil)

| küme | düz → deyim | recall | eşleştirilmiş |
|---|---|---|---|
| 5F finali (1.244; 5F'de bir kez ölçülmüş, 5G'de ayar yok) | 169/416 = %40,6 → 158/416 = %38,0 | 560/828 = %67,6 → 554/828 = %66,9 | 11 düzeldi / 0 bozuldu (p = 0,001); 6 deyim kaybı (p = 0,03) |
| görülmüş havuz (30.201; ayar yok) | 2.835/7.477 = %37,9 → 2.457/7.477 = %32,9 | %76,5 → %76,3 | 378 düzeldi / 0 bozuldu; 25 deyim kaybı |
| Claude kümesi, final kısmı (48; AI etiketli) | 15/16 → 15/16 | 28/28 → 28/28 | değişiklik yok |

Baseline bu dalda 5F raporunun sayılarını birebir üretti (5F finali 169/416, 560/828): bayrak kapalıyken motor 5F.
Üç ölçümde de hata azalışı anlamlı ve yönü aynı; deyim kaybı her yerde küçük (%0,1–0,7 puan), 5F finalinde
istatistiksel olarak saptanabilir. Görülmüş havuzda 1 deyim kaybına 15 düz hata düzeliyor.

### 7.3 Kalan hatalar (5G finali, sayı)

- Kalan 120 düz hata: kategori `idioms` 65, `prepositional_phrases` 41, `binomials` 8, `collocations` 3,
  `phrasal_verbs` 3; MAGPIE varyantı "identical" 83. Yani çoğu **sözlükteki biçimiyle aynen geçen** düz kullanım:
  biçim işareti yok, ayırmak için cümlenin anlamı gerekir.
- Gösterilmeyen 182 deyimin 92'si bulunamıyor (çekim + başka değişiklik 42, araya sözcük 20, çeşitli 14), 90'ında
  sözcük sözcük okuma kazanıyor.

### 7.4 Phrasal verb, POS, sorgu sırası, panel/kart

- Phrasal verb'ler kurala hiç girmiyor (`literalCuesOf` onlar için boş döner); bölünmüş "look the word up" iki
  bayrakla aynı (test). 5F'nin phrasal verb testleri geçiyor.
- Kural sözlüğün sözcük türü bilgisini yalnız "bu kelime isim mi" diye okur; lemma (`Lemmatizer`) değişmedi.
- Önbellek anahtarı bayrağı içerir; aynı motorla sorgu sırası cevabı değiştirmiyor (test).
- Kart yolu aynı `resolve`'u çağırır: panel sözcük sözcük okuyorsa `fit` "literal" der, kart puanlanmaz (test).

### 7.5 Maliyet ve platformlar

- Yeni bağımlılık, varlık, model yok; `pubspec` değişmedi; ağ çağrısı yok. Uygulama boyutu: tek Dart dosyası
  (`lib/nlp/literal_cues.dart`, 129 satır) ve birkaç düzine satır; ölçülebilir fark beklenmez (derlenmiş boyut
  ölçülmedi).
- Gecikme (bu bulut makinesi, masaüstü Dart VM, 30.201 sorgu, birer kez): 2,30 ms → 2,44 ms / kalıp çözümü
  (+0,14 ms; tek ölçüm, gürültü içerir). Bellek: ek önbellek yok.
- Kod saf Dart, platforma özgü bir şey yok: Windows/Android/iOS'ta aynı çalışır. **Gerçek cihazda ölçüm
  yapılmadı**; telefonda birkaç kat yavaş olsa da kalıp başına milisaniye düzeyinde kalması beklenir (tahmin).

## 8. Aşama 5: Testler ve koruma

- Yeni: `test/idiom_literal_5g_test.dart`, 18 test (cümleler Claude'un, AI): varsayılan bayrak; üç edat deyimi için
  düz/deyimsel çift (bayrak kapalıyken düz cümlede deyim **gösteriliyor** = test ön koşulu, açıkken sözcük sözcük;
  kendi biçiminde deyim değişmiyor; kart onaylamıyor); olumsuzluk; fiil deyimi etkilenmiyor; cümle sınırı; tırnak
  ve "the idiom …" (kesin değil, kart yok); özel ad; bölünmüş phrasal verb; sorgu sırası; önbellek anahtarı;
  deneysel eşleştirme (iyelik, ara sözcük, iki niteleyici reddi, sıradan eşleşme aynı).
- `flutter test` (tümü): başta **529 geçti / 12 atlandı / 3 başarısız**, sonda **547 geçti / 12 atlandı / 3
  başarısız** (fark: 18 yeni test). 3 başarısız her ikisinde aynı ve önceden var: `text_repair_test`,
  `picture_book_test`, `import_completeness_test` bu ortamda PDFium kütüphanesi olmadığı için `setUpAll`'da
  düşüyor.
- MAGPIE ile odaklı testler (`idiom_confidence_5f`, `idiom_literal_5g`, `sense_confidence`, `context_sense`,
  `context_sense_ui`, `review_quiz`, `phrase_*`): 117/117 geçti. MAGPIE'li 5F testi CI'da veri olmadığı için
  atlanır; geçmiş sayılmamalı.
- `qa_test/` (görsel ve dil denetimleri): 39 geçti, 1 atlandı.
- `flutter analyze`: başta ve sonda 124 bulgu, hepsi önceden var olan `info`; hata/uyarı 0, yeni bulgu 0.
- Python: `tools/release/test_release_check.py` 23/23, `release_check.py check-workflows` geçti,
  `tools/lexicon_provenance/test_provenance.py` "unchanged: true".
- `assets/dict.db` ve `assets/tr_en.db` SHA-256 başta ve sonda aynı:
  `ab4a7a53b9fc5e1edbd682da5cb7193c0c109f93236655385bf6231d90221a9c`,
  `49a661b9c8951259ab13fd6a95aa77b68e16f1c4716669dacfb6c12521cfa818`.
- Kullanıcı kitapları, kartları, öğrenme kayıtları, yedekleri ve veritabanı şemaları okunmadı/değişmedi.
  `SenseEngine.version` 4 → 5 yalnız geri bildirim kayıtlarına yazılan motor sürümü alanını etkiler (hiçbir
  okuma bu alana göre süzmüyor).
- Arayüz değişmedi.

## 9. Üretim kararı ve ödünleşim

- Varsayılan: **açık** (`SenseEngine.defaultLiteralCues = true`). Gerekçe: kilitli bağımsız finalde anlamlı hata
  azalışı (p = 0,0001), anlamsız recall değişimi, güvenlik ölçülerinde sıfır değişim; iki ek kümede aynı yön.
- Bedel: edat öbeği deyimleri biçimi değişmiş geçtiğinde nadiren gerçekten deyimdir ("under a gun" gibi); o zaman
  okuyucu önce kelimelerin anlamını görür, deyim "diğer anlamlar"da kalır. Ölçülen sıklık: deyimsel cümlelerin
  %0,1–0,7'si. Sözcük sözcük okumanın Türkçesi olmayan birkaç durumda hiçbir anlam gösterilmez.
- Geri dönüş: `defaultLiteralCues = false` (tek satır) → motor 5F ile birebir aynı (testli: bayrak kapalı her
  karşılaştırmada 5F sonucu).
- Kabul edilmezse aynı PR yalnız araştırma + kapalı bayrak olarak da birleşebilir.

## 10. Riskler ve kalan işler

- Hedeflenen %40'lık düz kullanım hatasının yalnız **onda biri** çözüldü; kalanların çoğu yüzey işareti taşımıyor.
  Anlamlı daha büyük bir düşüş için cümle anlamını gören bir model gerekir; bu görevde denenenlerin hiçbiri bu
  veride kurallardan iyi değildi ve lisansı temiz bir aday yok.
- Final etiketleri kitle çoğunluk oyu (uzlaşma < 1,0); gürültülüdür. Okuduğum hataların ~%14'ü etiket gürültüsü
  gibi duruyor (Claude'un okuması, insan kontrolü yok).
- Final deyim türleri 5F finalininkiler; 5A/5B/5E deyim listeleriyle tür örtüşmesi dışlanamadı.
- Sözcük sözcük okumanın Türkçesi yokken boş panel: ayrı bir iyileştirme olabilir (geliştirme kümesinde
  tasarlanıp yeni bir finalde ölçülmeli).
- İyelikli ("someone's") kalıplar varsayılanda hâlâ bulunmuyor; açmak düz kullanım hatasını artırıyor. İyelikli
  eşleşmeye biçim işaretini (sayı) bağlamak bir sonraki adım olabilir; ayrı ölçüm ister.
- Mobil cihaz ölçümü yok.

## 11. Dosyalar

- `lib/nlp/literal_cues.dart` (yeni), `lib/nlp/context_sense.dart` (kural, bayrak, sürüm, önbellek anahtarı),
  `lib/nlp/text.dart` (deneysel `variants`, `Match.variant`), `lib/data/dict_db.dart` (eşleştiriciye sözcük türü).
- `test/idiom_literal_5g_test.dart` (yeni).
- `tools/nlp_research_5g/`: `build_sets_5g.py`, `dump_5g_test.dart`, `metrics_5g.py`, `final5g_LOCKED.sha256`,
  `research/` (sınıflandırıcı, WordNet ve GloVe uyumu, cümle modelleri, hipotez sayımları; yerel veriyle çalışır,
  veri yok).
