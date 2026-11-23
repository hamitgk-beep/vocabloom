# Görev 5L: Kalıp çakışma çözümleyicisi ("was on" / "on hand")

Tarih: 2026-11-23. Dal: `claude/project-thread-bnwdm3`, **#121'in (5K) HEAD'i `bfbdad5` üzerine** kuruldu.
Zincir: #116 → #117 → #118 → #119 → #120 → #121 → bu PR. Hiçbir PR birleştirilmedi, rebase edilmedi.

## 1. Kısa sonuç

* **Kabul edilen tek kural (varsayılan AÇIK): A = `OverlapRules.copulaObject`.** `be` + edat iki kelimelik phrasal
  verb ("be on"), edatın arkasında **kendi isim öbeği** varsa ("was on *the bridge*", "was on *hand*") ve sözlüğün
  **doğrulanmış** anlam örnekleri o edata hiç nesne vermiyorsa ("the match is on tonight", "the heating is on")
  kelime kelime okunur. Zaman öbekleri ("on *all night*", "on *tonight*") nesne sayılmaz.
* Kilitli bağımsız holdout'larda (DiMSUM 2016 test + PARSEME 1.1 EN, 5F–5K'nin hiçbirinde kullanılmadı): **22 karar
  düzeldi, 0 bozuldu**, yanlış "kesin" 320 → 313, doğru "kesin" ve kart onayları **hiç değişmedi**. Ön kayıtlı
  kabul ölçütlerinin hepsi tuttu (`tools/nlp_research_5l/ACCEPTANCE_5L.md`).
* **Ne düzelmedi:** kural yalnız `be on` kaydında devreye giriyor (sözlükte `be` + edat 2 kayıt; `be after`'ın
  doğrulanmış örneği yok, dokunulmuyor). Edat arkasında isim öbeği olmayan yanlış `be on`'lar (holdout'ta 13 aday,
  1'i hâlâ "kesin") kalıyor. Genel phrasal verb / edat öbeği çakışmasını çözen B kuralı geliştirme setinde karışık
  çıktı (+18/−10) ve **kapalı** kaldı. Bu genel bir "motor" değil, ölçülmüş dar bir düzeltme.
* 5G/5H açık, 5I/5J kapalı bayrakları değişmedi. `OverlapRules.none` ile 5K davranışı geri gelir (testle doğrulandı).

## 2. Kök neden (kod ve DB üzerinde yeniden doğrulandı)

```
expr 1064  be on    phrasal_verbs          "yayında olmak, gösterimde olmak"   (exd: 2 doğrulanmış anlam; own_expr: 6 AI taslak anlamı)
expr 14815 on hand  prepositional_phrases  "hazırda, elde, elinin altında, yakınında"
```

Akış (5K'nın izi aynen tekrarlandı, `tools/nlp_research_5l/trace_5l_test.dart`):

1. `PhraseMatcher.match` (`lib/nlp/text.dart:442`): `was` → lemma `be`, `be on` eşleşir; nesne/sözdizimi kontrolü yok.
2. `ParaAnalysis.expressionsAt` (`lib/ui/paragraph_view.dart:48`): gizli (literal) olmayan adaylar, önce uzun olan,
   eşitse **filtre sırası** (`phrasal_verbs` < `prepositional_phrases`) → "on" `be on`'a gider.
3. `SenseEngine.isLiteral` → `resolve` → `_resolvePhrase` (`lib/nlp/context_sense.dart`): phrasal verb için düz
   okuma yalnız puanla; "was on hand"da `ex:be on#0` "clear" → **sure**.
4. `SenseEngine.fit` (kart): ifade kartı yalnız "sure" + doğrulanmış Türkçe ile notlanır; tek kelime kartları `resolve` ile.
5. `ExprCard._maybeNotHere` (`lib/ui/word_sheet.dart`) ve `resolveTap` (kelime paneli) aynı `resolve` sonucunu okur.
   Önbellek anahtarı: içerik, cümle hash'i, span, ifade, sözlük sürümü, motor sürümü, politika, dil, bayraklar.

Kural `_resolvePhrase`'in sonucunu değiştirdiği için **tek karar kaynağı** korunur: okuyucu alt çizgisi (`isLiteral`),
panel ve kart aynı okumayı görür. Bayrak önbellek anahtarına girer (`ovA`), motor sürümü 6 → 7.

### Gerçek iz (mini/regresyon cümleleri, Claude yazımı, insan etiketi değil)

| cümle | aday | 5K motoru | 5L (A açık) |
|---|---|---|---|
| Blacky the Crow was on hand promptly that afternoon. | be on | altı çizili, **sure**, "yayında veya gösterimde olmak" | gizli (düz okuma), "on" → **on hand** |
| | on hand | yalnız "hand"i kazanıyor | "on" ve "hand"i kazanıyor, "hazırda, elde …" |
| He was on the bridge. | be on | altı çizili, likely (AI taslağı "ilaç kullanmak") | gizli; "on"a dokununca "anlam seçilemedi" + sözlük anlamları (üstünde, üzerinde …) |
| The TV was on all night. | be on | sure | **aynı** (sure, "yayında …") |
| The prisoner was on the run for three weeks. | on the run | 5I okuması | **aynı** (güven, Türkçe, gerekçe birebir) |
| Hot air rises and cold air sinks. | hot air | 5I notu | **aynı** |
| The police are after the thief. | be after | likely | **aynı** (doğrulanmış örnek yok → kural uygulanmaz) |
| He was on medication for years. | be on | likely (AI taslağı) | gizli: taslak anlam artık "kalıp" olarak altı çizilmiyor, kartta "kalıp olarak kullanılmamış olabilir" notuyla duruyor |

Ekran görüntüleri (proje dosyaları `kalip-cakisma-5l/`): `tr_was_on_hand_5l.png`, `en_was_on_hand_320_dark_5l.png`,
`tr_was_on_the_bridge_5l.png`, `tr_tv_was_on_5l.png`, `en_tv_was_on_320_5l.png`.

## 3. Değerlendirilen adaylar (A/A2/B/C/D) ve ablation

Hepsi `lib/nlp/overlap_rules.dart`'ta, aynı bayrak altında; parser, model veya ağ yok.

| aday | ne yapar | geliştirme (STREUSLE train+dev, 2.033 aday) | sonuç |
|---|---|---|---|
| **A** copulaObject | `be`+edat, edatın isim öbeği var, doğrulanmış örnekler nesnesiz → düz okuma | **+13/−0**, yanlış kesin 92→88, kart değişmedi | **dondurulan tek aday** |
| A2 senseFrame | her phrasal verb için: örnekleri nesnesiz olan anlam, cümlede nesne varsa kaybeder | +20/−7, 3 doğru kart engellendi, doğru kesin 153→149 | kapalı |
| B prepPhraseTakesParticle | edat başka bir (phrasal verb olmayan) kalıbı başlatıyorsa phrasal verb düz okunur | +18/−10 ("go out of their way", "stand in line", "put in charge" bozuldu) | kapalı |
| C sharedNotSure | başka kalıpla kelime paylaşan kalıp asla "kesin" değil | yanlış kesin 92→85 ama doğru kesin 153→145, 3 doğru kart engellendi | kapalı (gereksiz belirsizlik) |
| D copulaNeverSure | `be`+edat asla "kesin" değil | yanlış kesin 92→88, karar değişmedi; "TV was on" kartı notlanamaz olur | kapalı (A zaten kapsıyor) |
| A+B | | +28/−10 | kapalı |

Denendikten sonra düzeltilen iki hata (holdout'tan **önce**): (1) A ilk hâliyle `be after the thief`'i de düz
okuyordu; doğrulanmış örnek koşulu eklendi. (2) Örnek çözümlemesinde "is the match on" (soru devriği) ve
"is currently on" (zarf) nesne sanılıyordu. Aday `9b700b0` commit'iyle donduruldu, holdout bir kez çalıştırıldı.

## 4. Değerlendirme setleri ve veri sızıntısı

| set | kaynak | etiket | rol |
|---|---|---|---|
| mini (5K, 14) + karşıt çiftler (5L, 20) | Claude yazdı | **proxy**, insan değil | yalnız regresyon/demo |
| dev_streusle | STREUSLE 4.x train+dev (3.279) | insan | tasarım; 5K'da görüldü |
| **hold_dimsum** | DiMSUM 2016 **test** (1.000; TrustPilot, Tweebank, TED) | insan, güçlü MWE | kilitli holdout |
| **hold_parseme** | PARSEME 1.1 EN train+test (6.844; STREUSLE'de veya mini'de geçen 592 cümle çıkarıldı) | insan, fiil MWE'leri | kilitli holdout, yalnız `phrasal_verbs` adayları puanlandı |
| MAGPIE (keşif) | 5F–5K'nin kullandığı korpus, "be + on/after" geçen 480 cümle | insan | yalnız yan etki kontrolü, başarı kanıtı değil |

Hash'ler **hiçbir kural yazılmadan önce** commit edildi (`39f56bc`, `holdout_5l_LOCKED.sha256`); holdout koşusundan
önce yeniden doğrulandı (6/6 OK). STREUSLE test (5K'da açıldı) ve 5F–5K MAGPIE finalleri tekrar final yapılmadı.

**Bağımsızlık: kısmen bağımsız.** Cümleler ve anotatörler yeni; ama DiMSUM, STREUSLE'nin anotasyon geleneğini izler,
PARSEME'nin bir kısmı EWT'den gelir (STREUSLE'de geçen cümleler metin eşleşmesiyle çıkarıldı, kaynak kimlikleri anonim
olduğundan EWT'nin geri kalanı ayırt edilemedi). Kalıp türleri yeni değil.

**Etiket birimi:** "aday tokenlarının hepsi tek bir insan MWE'sinin içinde" = EXPR. Bu "sözcüksel birim mi" sorusudur;
Türkçenin doğruluğu veya tek kelime kartının doğruluğu değildir. PARSEME yalnız fiil MWE'lerini etiketler ve
kılavuzu `be`+edat'ı neredeyse hiç birim saymaz; DiMSUM zayıf MWE'leri içermez. Bu yüzden `be on` için gold LIT kısmen
kılavuz tercihidir; yine de üç ayrı korpusta (STREUSLE 20, DiMSUM 7, PARSEME 42 aday) `be`+edat **bir kez bile** birim
işaretlenmedi.

## 5. Sonuçlar

Tanımlar: LIT = gizli ya da okuyucuda hiç token kazanmıyor; UND = gösteriliyor ama anlam yok; EXPR = anlamla gösteriliyor.
Yanlış kesin = gold LIT iken EXPR+sure. Kart = `SenseEngine.fit(ifade, cümle, ifadenin doğrulanmış Türkçesi)` gerçek
çağrısı. +/− = 5K motoruna göre eşleştirilmiş düzelen/bozulan karar; p = kesin McNemar.

### 5.1 Holdout (tek koşu, donmuş aday)

| set | sistem | P | R | F1 | FPR [%95] | kararsız % | yanlış kesin | doğru kesin | kart onayı | yanlış kart | engellenen doğru kart | + | − | p | span P / R / F1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DiMSUM (523 aday, 195 EXPR) | 5K | 0,363 | 0,790 | 0,498 | 0,823 [0,78–0,86] | 4,0 | 12 | 27 | 9 | 1 | — | — | — | — | 0,339 / 0,180 / 0,236 |
| | **A** | 0,365 | 0,790 | 0,499 | 0,817 [0,77–0,86] | 4,0 | 12 | 27 | 9 | 1 | 0 | 2 | 0 | 0,50 | 0,341 / 0,180 / 0,236 |
| PARSEME (1.342 PV adayı, 352 EXPR) | 5K | 0,276 | 0,759 | 0,405 | 0,706 [0,68–0,73] | 0,1 | 308 | 113 | 118 | 86 | — | — | — | — | — |
| | **A** | 0,282 | 0,759 | 0,411 | 0,686 [0,66–0,71] | 0,1 | 301 | 113 | 118 | 86 | 0 | 20 | 0 | 1,9e-6 | — |
| **toplam** | **A** | | | | | | **320 → 313** | 140 → 140 | değişmedi | değişmedi | **0** | **22** | **0** | | |

Bilgi için (holdout'ta karar verilemez, aday değillerdi): B DiMSUM +5/−2, PARSEME +57/−4 (2 doğru kart engellendi);
A2 PARSEME +52/−7 (3 kart); C yanlış kesin 308→267 ama doğru kesin 113→111 ve kart onayı 118→104. B'nin PARSEME'deki
güçlü sonucu ile geliştirme setindeki zayıf sonucu çelişiyor; ayrı bir görevde yeni kilitli setle ölçülmeli.

Kırılım (A): tüm değişiklikler `be`+edat sınıfında (DiMSUM 7 adayın 2'si, PARSEME 42'nin 20'si); diğer kategorilerde 0
değişiklik. Kalan yanlış `be on` gösterimleri: dev 4, DiMSUM 5 (1'i sure), PARSEME 8 (edat arkasında isim öbeği yok;
kural bunlara dokunmuyor).

### 5.2 Geliştirme (STREUSLE train+dev) — tam tablo

| sistem | P | R | F1 | FPR | yanlış kesin | doğru kesin | kart | yanlış kart | engellenen doğru kart | + | − | p | span F1 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 5K | 0,567 | 0,792 | 0,661 | 0,818 | 92 | 153 | 52 | 14 | — | — | — | — | 0,348 |
| A | 0,572 | 0,792 | 0,664 | 0,803 | 88 | 153 | 52 | 14 | 0 | 13 | 0 | 0,0002 | 0,349 |
| A2 | 0,572 | 0,786 | 0,662 | 0,795 | 83 | 149 | 47 | 12 | 3 | 20 | 7 | 0,019 | 0,347 |
| B | 0,571 | 0,784 | 0,660 | 0,797 | 88 | 149 | 50 | 13 | 1 | 18 | 10 | 0,19 | 0,348 |
| C | 0,567 | 0,792 | 0,661 | 0,818 | 85 | 145 | 47 | 12 | 3 | 0 | 0 | 1 | 0,348 |
| D | 0,567 | 0,792 | 0,661 | 0,818 | 88 | 153 | 52 | 14 | 0 | 0 | 0 | 1 | 0,348 |

### 5.3 MAGPIE yan etki kontrolü (keşif, daha önce görülmüş veri)

"be + on/after" geçen 480 MAGPIE cümlesi (332 hedef deyim adayı: 276 deyimsel, 56 düz): **hiçbir hedef deyimin kararı
değişmedi**; 341 `be on` adayı gizlendi (MAGPIE'nin bunlar için etiketi yok), 1 `on show` adayı tokenını geri aldı.
5K'daki parser kurallarının MAGPIE'de 12 düzeltme/29 bozma ile kötüleştirdiği `prepositional_phrases` dilimine
A dokunmuyor.

### 5.4 Panel / okuyucu / kart tutarlılığı

Tek karar `_resolvePhrase` içinde verildiği için okuyucu (`isLiteral`), ifade kartı ("kalıp olarak kullanılmamış
olabilir" notu) ve `fit` aynı sonucu görür (`test/expression_overlap_5l_test.dart`). Holdout dışında, donmadan sonra
eklenen tek UX düzeltmesi: kelime panelinde "was on the bridge"de **"on"a** dokununca artık "be"nin anlamı ("olmak")
gösterilmiyor; "on"un kendisi değerlendiriliyor ("anlam seçilemedi" + sözlük anlamları). Bu yalnız `resolveTap`'te,
yalnız 5L'in düz okuduğu kalıp için; "was"a dokunmak eskisi gibi. Ölçülen kararları değiştirmez (iz `resolve` ve `fit`
kullanır).

## 6. Sözlük denetimi (salt okunur)

`EXPRESSION_OVERLAP_AUDIT_5L.tsv`: 18.209 `expr` satırı tarandı (yalnız sözlük metni; korpus cümlesi yok).

| sınıf | satır | 5K yüksek risk (228) içinde |
|---|---|---|
| BE_PLUS_PARTICLE | 2 | 2 |
| PV_PARTICLE_STARTS_EXPR (edat başka kalıbı başlatıyor) | 3.746 | 116 |
| PV_TAKES_OBJECT (doğrulanmış örnekler nesne veriyor) | 1.000 | 69 |
| PV_STRANDED_ONLY (örnekler hep nesnesiz) | 387 | 29 |
| PV_FRAME_UNKNOWN (doğrulanmış örnek yok) | 2.452 | 18 |
| ARTICLE_NOUN | 4 | 0 |
| OVERLAPS_OTHER_EXPR (son kelimesi başka kalıbı başlatıyor; çok geniş, yalnız olası çakışma) | 15.837 | 218 |
| NAME_OR_QUOTE | 1 | 0 |
| SENTENCE_PUNCT | 0 | 0 |

A'nın uygulanabildiği tek satır: `1064 be on`. 5K'nın 228 yüksek risk sayısı aynen okundu (değişmedi). "Şüpheli"
kanıtlanmış hata değildir; hiçbir kayıt değiştirilmedi.

## 7. Reddedilen yaklaşımlar

* "was on" yasak listesi, cümleye özel istisna, "en uzun kazanır" / "kategori X hep kazanır": istenmedi ve B/C
  ölçümleri bu tür genel önceliklerin doğru kalıpları da bozduğunu gösterdi.
* Parser (spaCy/UDPipe/Stanza) entegrasyonu: 5K'da MAGPIE'de anlamlı biçimde kötüleştirdi; yeniden denenmedi.
* A2/B/C/D: bölüm 3.

## 8. Sınırlamalar

* Kural dar: pratikte tek sözlük kaydı. "Genel bir çözümleyici" iddiası yok; mekanizma (doğrulanmış örneklerden
  nesne alma çerçevesi) geneldir ama genel hâli (A2) geliştirme setinde net fayda göstermedi.
* Zaman öbeği listesi (night, day, week …) dilin kapalı bir sınıfı; eksik kalırsa ("was on *the weekend*" gibi bir
  yayın cümlesi) `be on` gizlenebilir.
* `be on`'un AI taslağı anlamı "ilaç kullanmak" ("was on medication") artık kalıp olarak altı çizilmiyor; panelde not
  ile görünmeye devam ediyor. Taslak doğrulanmadığı için bilinçli.
* PARSEME/DiMSUM gold'u Storilex'in "kalıp" kavramıyla birebir aynı değil (bölüm 4).
* Mobil cihazda ölçüm yapılmadı. Masaüstü iz süresi (tek iş parçacığı): 5K ve A arasında ölçülebilir fark yok
  (~1,4–1,9 ms/cümle, tüm aday çözümlemesi dahil). Yeni önbellek: cümle başına matcher sonucu (en çok 200).

## 9. Lisans

Kodda yeni bağımlılık yok. DiMSUM (TrustPilot/Tweebank/TED metinleri, kendi lisansları), PARSEME EN (VMWE
anotasyonu CC BY 4.0, UD metinleri CC BY-SA), STREUSLE (CC BY-SA 4.0 + EWT), MAGPIE (CC BY 4.0, BNC metni):
**hiçbir cümle commit edilmedi**; yalnız hash, sayı ve toplu metrik. #114'teki sözlük kaynak/lisans engeli çözülmüş
sayılmadı.

## 10. Yeniden üretme

```bash
python3 -I tools/nlp_research_5l/build_sets_5l.py EXT OUT        # EXT: dimsum-data, sharedtask-data, streusle (commit'ler LOCKED dosyasında)
sha256sum -c <(grep -v '^#' tools/nlp_research_5l/holdout_5l_LOCKED.sha256)   # OUT içinde
NLP_5L_IN=OUT/hold_dimsum.tsv NLP_5L_OUT=W/d.jsonl NLP_5L_SYSTEMS="base,A" flutter test tools/nlp_research_5l/trace_5l_test.dart
python3 -I tools/nlp_research_5l/metrics_5l.py W/d.jsonl OUT/hold_dimsum.gold.jsonl dimsum     # --show: yalnız yerel
NLP_5L_AUDIT=docs/nlp_engine_research/EXPRESSION_OVERLAP_AUDIT_5L.tsv flutter test tools/nlp_research_5l/audit_5l_test.dart
```
