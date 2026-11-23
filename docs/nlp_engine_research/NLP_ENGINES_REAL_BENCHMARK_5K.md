# Görev 5K: spaCy, UDPipe, Stanza, AMALGrAM, DISC ve STREUSLE — gerçek kurulum, test ve karşılaştırma

Tarih: 2026-11-23. Dal: `claude/project-thread-mh324p`, **#120'nin (5J) HEAD'i `ddbab43` üzerine** kuruldu
(5J tamamlanmıştı: final çalıştırması ve rapor commit'leri dalda). Zincir: #116 → #117 → #118 → #119 → #120 → bu PR.

Bu bir **geliştirme laboratuvarıdır**. Uygulama davranışı, sözlük veritabanları ve yayın durumu değişmedi:

| dosya | önce (SHA-256) | sonra |
|---|---|---|
| `assets/dict.db` | `ab4a7a53b9fc5e1edbd682da5cb7193c0c109f93236655385bf6231d90221a9c` | aynı |
| `assets/tr_en.db` | `49a661b9c8951259ab13fd6a95aa77b68e16f1c4716669dacfb6c12521cfa818` | aynı |

`lib/`, `test/`, `assets/` altında tek satır değişmedi (`git diff origin/claude/project-thread-kw2q99 -- lib test assets` boş).
Python, PyTorch veya model ağırlığı Flutter paketine girmedi; uygulamaya ağ çağrısı eklenmedi; hiçbir bayrak açılmadı.

---

## 1. Kısa sonuç ve karar

* **"was on" bir veritabanı kaydıdır, matcher'ın uydurması değil**: `expr` tablosunda id 1064, `be on`, `phrasal_verbs`,
  Türkçesi "yayında olmak, gösterimde olmak". Lemmatizer `was → be` yaptığı için her "was/is/are + on" bu kayda uyar.
  "Blacky the Crow was on hand" cümlesinde `be on` (was, on) ile `on hand` (on, hand) aynı "on"u paylaşır; okuyucu eşit
  uzunlukta iki aday arasında **filtre sırasına** bakar (`phrasal_verbs` 2., `prepositional_phrases` 4. sırada), bu yüzden
  "on" `be on`'a gider ve panel **"kesin"** düzeyde "yayında veya gösterimde olmak" der. "The TV was on" için de "kesin".
* Altı adayın **hiçbiri** bağımsız setlerde üretimde kullanılmaya değecek, istatistiksel olarak anlamlı bir iyileşme
  sağlamadı. Parser tabanlı aynı kural seti STREUSLE testinde yanlış "kesin"leri 3'ten 0'a indirdi ama genel doğrulukta
  anlamlı fark yok (McNemar p ≥ 0,29); MAGPIE final5k'de ise **anlamlı biçimde kötüleştirdi** (spaCy sm: 12 düzeltti, 29 bozdu, p = 0,012).
* **GO/NO-GO**: spaCy, Stanza, UDPipe, AMALGrAM, DISC → uygulama için **NO-GO**. spaCy ve UDPipe → geliştirme aracı olarak
  **GO** (sözlük denetimi, aday analizi). STREUSLE → yalnız yerel geliştirme/değerlendirme **veri kümesi** (model değil).
  Mobil için gerçekçi tek yol, ölçülmüş küçük bir kuralın **Dart'ta** (parser'sız) yazılması: "be + edat" adayı asla
  "kesin" olmasın ve paylaştığı edatı edat+isim kalıbına bıraksın. Bu kural bu PR'da **uygulamaya bağlanmadı**; ayrı bir
  görevde kendi kilitli finaliyle ölçülmeli.

## 2. Yedi girdili tablo

| aday | görev türü | kurulum denendi mi | durum | gerçek çalıştırma kanıtı | somut katkı | lisans | nihai karar |
|---|---|---|---|---|---|---|---|
| Storilex/Dart (baseline) | tokenize, lemma (kural), sözlükle eşleştirme, deyim/düz kararı (kural), Türkçe anlam | — | REAL INFERENCE VERIFIED | `dart/baseline_trace_test.dart` 14 + 1.089 + 2.725 + 969 cümle | referans | GPL-3.0 (uygulama) | korunur |
| spaCy 3.8.7 + `en_core_web_sm`/`md` 3.8.0 | tokenize, POS, lemma, bağımlılık; Matcher/PhraseMatcher/DependencyMatcher mevcut | evet | REAL INFERENCE VERIFIED | tüm setlerde gerçek ağaçlar (`nlp_5k_results/mini_trace_5k.jsonl`) | mini'de 9 düzeltme/0 bozma; STREUSLE test +6/−3 (p 0,51); final5k +12/−29 (p 0,012) | kod MIT; model MIT (eğitim: OntoNotes 5, LDC) | uygulama NO-GO; geliştirme aracı GO |
| Stanza 1.10.1 (en default, combined) | tokenize, MWT, POS, lemma, bağımlılık | evet | REAL INFERENCE VERIFIED | mini, STREUSLE dev/test, final5k (STREUSLE train'de süre nedeniyle durduruldu) | STREUSLE test +9/−5 (p 0,42); final5k +11/−20 (p 0,15) | kod Apache-2.0; model kartı Apache-2.0 + SPECIALIST Lexicon koşulları; eğitim treebank'leri ayrı lisanslı | NO-GO (PyTorch, 327 MB, ~100–155 ms/cümle masaüstü) |
| UDPipe 1 (ufal.udpipe 1.3.1.1) | tokenize, POS, lemma, bağımlılık | evet | REAL INFERENCE VERIFIED | iki model: UD 2.5 EWT (**RESEARCH ONLY**, CC BY-NC-SA 4.0) ve UD 2.1 English (CC BY-SA 4.0) | STREUSLE test +8/−4 ve +8/−6 (anlamsız); final5k +11/−24 (p 0,041), +13/−31 (p 0,0096) | kütüphane MPL-2.0; model ayrı | NO-GO (kazanç yok); teknik olarak en mobil-uygun parser |
| AMALGrAM 2.0 | MWE span bulma (+ supersense) | evet | resmî model: ATTEMPTED FAILED; yeniden eğitilmiş: REAL INFERENCE VERIFIED | orijinal, değiştirilmemiş kod Python 2.7 Docker'da STREUSLE train ile eğitildi | STREUSLE test MWE span F1 0,548 (Storilex 0,35), ama STREUSLE ile eğitildi; MAGPIE'de deyim recall 0,108 | kod GPLv3; yeniden eğitilen model STREUSLE (CC BY-SA 4.0 + EWT metni izinli) türevi | NO-GO; yalnız araştırma |
| DISC | deyim span + deyimsel kullanım | evet | INSTALLED, gerçek çıkarım **doğrulanamadı** (ATTEMPTED FAILED) | bağımlılıklar kuruldu, BERT indi; checkpoint Google Drive'da, proxy 403 | yok (ölçüm üretilmedi) | README "MIT" der ama depoda LICENSE dosyası yok; checkpoint lisansı belirsiz | NO-GO |
| STREUSLE 4.x (veri kümesi) | insan etiketli MWE, lexcat, supersense; **model değil** | indirildi ve parse edildi | veri kümesi | train 2.725 / dev 554 / test 535 cümle gerçekten okundu | bağımsız, doğal dağılımlı span ve "birim mi" değerlendirmesi | anotasyon CC BY-SA 4.0; EWT metni Google/LDC izniyle | yerel değerlendirme verisi; repoya ve uygulamaya girmez |

## 3. Kurulum kanıtları

Ortam: Linux 6.18 x86_64, Intel Xeon 2,30 GHz, 4 çekirdek, 15 GB RAM; Python 3.12 (`uv`), sistem Python'u değişmedi.
Ayrıntılı loglar `nlp_5k_results/install_logs/`. Tam sürümler `tools/nlp_lab_5k/requirements-lock.txt` ve `requirements-disc-lock.txt`.

| bileşen | komut | sonuç |
|---|---|---|
| ana venv | `uv venv -p python3.12 .venv; uv pip install spacy==3.8.7 stanza==1.10.1 ufal.udpipe==1.3.1.1 …` | `EXIT_PIP=0`; ilk spaCy çağrısı `click` eksikliğiyle düştü, `click` eklendi |
| spaCy modelleri | GitHub release wheel'leri | sm `1932429d…`, md `5e6329fe…`, `EXIT_SPACY_MODELS=0` |
| Stanza | `stanza.download('en', processors='tokenize,mwt,pos,lemma,depparse')` | `EXIT_STANZA_DL=0`, resources 1.10.0, 327 MB |
| UDPipe resmî kaynak | `lindat.mff.cuni.cz` | bağlantı yok (000). Yerine: `jwijffels/udpipe.models.ud.2.5` (lindat UD 2.5 modellerinin birebir kopyası; EWT 2.5, `784bd0fa…`) ve `bnosac/udpipe.models.ud` (udpipe R paketi yazarının UD 2.1 English üzerinde ayrıca eğittiği CC BY-SA 4.0 model, `20432a6f…`) |
| UDPipe ilk çalıştırma | `python -m lab5k.engines udpipe_ewt25 …` | **segfault (139)**: SWIG `Pipeline` modeli canlı tutmuyor; model referansı saklanınca düzeldi |
| AMALGrAM resmî model | `curl http://www.cs.cmu.edu/~ark/LexSem/sst.model.pickle.gz` (konteyner) | `Could not resolve host`, `EXIT_ORIG_MODEL=6`; ana makineden de 000 |
| AMALGrAM ortamı | `dockerd` + `python:2.7`, `Cython==0.29.36`, `nltk==3.4.5` | `EXIT_PIP=0`; ilk eğitim `punkt` eksik diye düştü (`EXIT_TRAIN=1`), eklenince `EXIT_TRAIN=0` (57 s) |
| AMALGrAM eğitimi | `src/main.py --mwe --YY tagsets/bio2g --train train.tags --iters 3 --bio NO_SINGLETON_B` (sözlük ve küme özellikleri olmadan, çünkü `mwelex/` indirilemedi) | dev (gold POS) MWE P 0,803 R 0,552 F 0,654 |
| DISC | `.venv_disc` (torch 2.15, transformers 4.46.3, nltk) | `EXIT_PIP=0`; checkpoint `drive.google.com` ve `drive.usercontent.google.com` → `CONNECT tunnel failed, response 403` (politika engeli; tekrar denenmedi) |
| DISC çıkarım denemesi | `python inference.py` | checkpoint yokken **"No checkpoint found! Train from scratch!" yazıp rastgele ağırlıklarla çalışıyor** (Seq Acc 0,000). Ayrıca `load_init_model` checkpoint'i yalnız `CONTINUE_TRAIN=True` iken yüklüyor; varsayılan ayarla checkpoint olsa bile rastgele model çalışırdı. Çıktı atıldı, hiçbir ölçüme girmedi |
| STREUSLE | `git clone` @ `8ba61fe4`; `lab5k/streusle_io.py` JSON'dan token, `smwes`, `wmwes`, `lexcat`, `ss` alanlarını okur | 3.814 cümle; test 364 MWE (130 N, 80 zayıf, 24 V.VID, 19 ADJ, 18 PP, 17 V.IAV …) |

Üçüncü taraf kaynaklar: AMALGrAM `nschneid/pysupersensetagger` @ `4783c54a28d8e439beb9d115508abb2dc305fbf3` (2017-05-31),
DISC `zzeng13/DISC` @ `7542fcd67dfbea448c0cfa76ac34353ae6ab171d` (2021-09-26), STREUSLE `nert-nlp/streusle` @
`8ba61fe4f216e7967500a862554a4fff79d25f5d` (2025-11-15, EWT v2.17), MAGPIE `hslh/magpie-corpus` @ `7fa677b`.
Hiçbirinin kodu veya verisi commit edilmedi (`tools/nlp_lab_5k/.gitignore`).

## 4. Teşhis: kitapta altı çizilen kalıp nereden geliyor

Gerçek yol (kod izlenerek, `dart/baseline_trace_test.dart` aynısını çalıştırır):

1. `DictDb.load` (`lib/data/dict_db.dart:104`): `expr` tablosunun 18.209 satırı `Expr` olur; `own_expr` doğrulanmış satırları
   Türkçeyi değiştirir, taslaklar yalnız `trDraft` olur. Kalıp `patternOf(phrase)` ile kelimelere bölünür.
2. `Lemmatizer` (`lib/nlp/text.dart`): `exc` tablosu (düzensiz biçimler) + ek kuralları; `was → be`.
3. `PhraseMatcher.match` (`text.dart`): ilk kelimeye göre dizinlenir; her kalıp kelimesi `lem.lemmas(token)` içinde
   aranır. "be on" için "was" (lemma be) + "on" yeter; nesne veya sözdizimi kontrolü yoktur.
4. `SenseEngine.isLiteral` (`context_sense.dart:710`) yalnız `phrasal_verbs` için düz kullanımı arar; burada "was on"u
   düz bulmuyor (`literal_hidden=false`).
5. `ParaAnalysis.expressionsAt` (`lib/ui/paragraph_view.dart:48`): her token için en uzun aday, eşitse **filtre sırası**.

SQL kanıtı (salt okunur):

```
SELECT id, phrase, cat, tr FROM expr WHERE phrase IN ('be on','on hand','on the run','on duty');
1064  be on       phrasal_verbs          yayında olmak, gösterimde olmak
14815 on hand     prepositional_phrases  hazırda, elde, elinin altında, yakınında
15070 on the run  prepositional_phrases  firarda, kaçmakta, koşturmaca içinde
194   on duty     prepositional_phrases  görevde, nöbette
own_expr('be on','phrasal_verbs') = ai_draft_unreviewed, reviewed=0
```

Eşleşme izi (token indeksleri 0 tabanlı, karakter aralığı [başlangıç, bitiş)):

| cümle | aday | token | karakter | gizli mi | panel güveni | gösterilen Türkçe | kazandığı tokenlar |
|---|---|---|---|---|---|---|---|
| Blacky the Crow was on hand promptly that afternoon. | be on | 3,4 | [16,19) [20,22) | hayır | **sure** | yayında veya gösterimde olmak | was, **on** |
| | on hand | 4,5 | [20,22) [23,27) | hayır | likely | hazırda, elde … | yalnız hand |
| He was on the bridge. | be on | 1,2 | [3,6) [7,9) | hayır | likely | ilaç kullanmak, diyette olmak (AI taslağı) | was, on |
| The TV was on all night. | be on | 2,3 | [7,10) [11,13) | hayır | **sure** | yayında veya gösterimde olmak | was, on |
| He was on the run for three weeks. | on the run | 2,3,4 | [7,17) | hayır | none (Türkçe yok: wn:8190) | — | on, the, run |

Sonuç: hata sözlükte gerçekten var olan, çok genel bir kayıttan (`be on`) + lemma eşleşmesinden + eşit uzunlukta
adaylarda sözdizimine değil filtre sırasına bakan kuraldan doğuyor. Kara liste eklenmedi.

## 5. Ayrım: dört ayrı soru

Her aday için ayrı alanlar tutuldu (`<set>.decisions.jsonl`): **kütüphanede var** (aday Storilex sözlüğünden geldi),
**cümlede dizi eşleşti** (Dart matcher'ın ham eşleşmesi), **gramer bakımından geçerli kalıp** (parser kuralının etiketi:
`R2-particle-of-verb`, `R5-pp-constituent` …), **bu cümlede deyimsel kullanıldı** (`dec`: EXPR / UNDECIDED / LIT / MENTION).
Ayrıca Türkçe: `var` (sözlük), `taslak-yeterli-kaynak-yok` (yalnız AI taslağı), `yok`.

## 6. Prototip: aynı kural, her parser

`tools/nlp_lab_5k/lab5k/rules.py` (`5K-rules-v2`). **Parser'lar deyim sınıflandırıcısı değildir**; yalnız token, POS,
lemma ve bağımlılık verir. Aşağıdaki kurallar bu görevde (Claude tarafından) yazıldı ve her parser'ın ağacına aynen
uygulandı. Adaylar her sistemde aynı: Storilex matcher'ının çıktısı. Kurallar güveni yalnız düşürebilir.

| kural | parser gerekir mi | ne yapar |
|---|---|---|
| R0 | hayır | aday tırnak içindeyse MENTION ("She said the words 'on the run'") |
| R1 | kısmen | `be` + edat iki kelimelik kalıp asla "kesin" değil; edatın kendi nesnesi varsa ("was on the bridge") LIT |
| R2 | evet | edat fiilin `compound:prt`/`prt`'si ise okuma korunur ("turned the radio on") |
| R3/R4 | evet | edatın kendi nesnesi var ya da fiile bağlı değil: gösterilir ama asla "kesin" değil |
| R5 | evet | edat+isim kalıbı, isim gerçekten o edatın nesnesiyse korunur; değilse UNDECIDED |
| R6 | evet | kalıbın son ismi sonraki bir ismin `compound`'ı ise LIT ("hot air balloon") |
| R7 | evet | bir edatı nesnesi olmadan tutan aday, edatı nesnesiyle tutan adaya kaybeder ("was on" ↔ "on hand") |

UD (Stanza, UDPipe) ve ClearNLP (spaCy) etiket şemaları normalize edilir (`case` ↔ `prep`/`pobj`, `compound:prt` ↔ `prt`);
iki şema için aynı sonucu veren test `tests/test_lab5k.py`.

Tasarım yalnız mini suite, STREUSLE train ve dev üzerinde yapıldı; `947bcad` commit'iyle **STREUSLE test ve final5k
çalışmadan önce donduruldu**. Sonradan yalnız final5k okuyucusu düzeltildi (iki MAGPIE cümlesi satır sonu içeriyor ve TSV
satırını bölüyor; bu iki satır her sistemden aynı biçimde çıkarıldı, n = 969).

## 7. Test kümeleri ve sızıntı denetimi

| küme | kaynak | etiket | rolü |
|---|---|---|---|
| (A) mini suite, 14 cümle / 19 aday | görev metni + "look the word up", "hot air" karşıt çifti | **Claude yazdı: proxy**, insan doğrulaması değil | şeffaf demo ve tasarım seti; genelleme kanıtı değil |
| (B) STREUSLE resmî test, 535 cümle | EWT reviews | insan (CC BY-SA 4.0) | span ve "birim mi" ölçümü; hash `f8144e62…` kilitlendi |
| (C) final5k, 969 satır (760 deyimsel / 209 düz) | MAGPIE random-split **test** parçası | insan (kalabalık, CC BY 4.0) | deyim/düz kararı; hash `6bafef46…` kilitlendi (commit `2280fd1`, `tools/nlp_lab_5k/sets/final5k_LOCKED.sha256`) |
| (D) sözlük denetimi | `assets/dict.db` `expr`, 18.209 satır | — | `EXPRESSION_MATCH_AUDIT_5K.tsv` |

Sızıntı: 5F, 5G, 5H, 5I, 5J setlerinin hepsi kendi script'leriyle yeniden üretildi ve **kilitli hash'lerin tamamı tuttu**
(5F final `6874e650…`, 5G final `ce55c3bb…`, 5H dev/tune/final `5e81b1be…`/`197f7faf…`/`d479d256…`, 5I final `a50d77ca…`,
5J final/hold `27034bd8…`/`1cd67546…`). final5k bu setlerin hiçbirindeki cümleyi içermez.

Kısıtlar, dürüstçe:
* **Deyim türü ayrık final mümkün olmadı.** 5F–5J, sözlükteki MAGPIE deyimlerinin neredeyse hepsini kullanmış;
  tür-ayrık filtreyle random-split testinde 0 satır kaldı. final5k, önceki **finallerin** deyimlerini (ölçülmüş, hiç
  ayarlanmamış) yeni cümlelerle kullanır; 5H dev/tune ve 5J hold deyimleri dışarıda.
* 0,70–0,99 uyumlu satırlar bitmiş olduğundan **1,0 uyumlu satırlar da** alındı; 5A/5B/5E'nin bunlardan bazılarına
  bakmış olma riski var (listeleri yerelde kaldı, kayboldu).
* DISC'in dağıttığı MAGPIE random split'iyle karşılaştırma: final5k'nin 954 satırı yalnız DISC test'inde, 7 satırın
  cümlesi+deyimi DISC train/valid'de de var (MAGPIE'de tekrar eden cümle), 8'i hiç yok. DISC çalışmadığı için etkisiz,
  ama çalışsaydı bu 7 satır bağımsız sayılamazdı.
* STREUSLE: AMALGrAM bu çalışmada STREUSLE **train** ile eğitildi; testi ancak dondurmadan sonra bir kez çalıştı.
  UD parser'larının eğitim verisi EWT train'i içerir (STREUSLE train cümleleri); test cümleleri EWT test'tir.
  STREUSLE'nin bir MWE'yi işaretlememesi "yanlış" demek değildir; gramer kategorilerinde (bağlaç, modal) farklı gelenek.

## 8. Sonuçlar

Tanımlar: pozitif = EXPR (deyim/kalıp olarak gösterilir). UNDECIDED (gösterilir ama "emin değilim") pozitif sayılmaz.
"Yanlış kesin" = gold EXPR değilken EXPR + `sure`. "Yanlış kart onayı" = bu durumda doğrulanmış Türkçeyle kartın
notlanabilmesi (kesin + doğrulanmış Türkçe + taslak değil). "Engellenen doğru kart" = gold EXPR, baseline kartı onaylarken
sistem onaylamıyor. Bu kart ölçüsü bir **vekil** göstergedir; deney motorları gerçek kart puanlama yoluna bağlanmadı ve
5J'nin `WordCardGuard`'ı (varsayılan kapalı) hiç değiştirilmedi.

### 8.1 Mini suite (proxy etiket, tasarım seti)

| id | aday (karakter) | gold | Storilex | kural (parser'sız) | spaCy sm | spaCy md | Stanza | UDPipe EWT2.5 | UDPipe 2.1 BY-SA | AMALGrAM* |
|---|---|---|---|---|---|---|---|---|---|---|
| A01 | on hand [20,27) | EXPR | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | UNDECIDED | EXPR/likely |
| A01 | be on [16,22) | LIT | **EXPR/sure** | UNDECIDED | LIT | LIT | LIT | LIT | LIT | LIT |
| A02 | be on [3,9) | LIT | EXPR/likely | UNDECIDED | LIT | LIT | LIT | LIT | LIT | LIT |
| A03 | on the run [7,17) | EXPR | UNDECIDED | UNDECIDED | UNDECIDED | UNDECIDED | UNDECIDED | UNDECIDED | UNDECIDED | EXPR/none |
| A03 | be on [3,9) | LIT | EXPR/likely | UNDECIDED | LIT | LIT | LIT | LIT | LIT | LIT |
| A04 | hot air [0,7) | LIT | EXPR/likely | EXPR/likely | LIT† | LIT† | LIT† | LIT† | LIT† | EXPR/likely |
| A05 | on duty [8,15) | EXPR | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely |
| A05 | be on [4,10) | LIT | EXPR/likely | UNDECIDED | LIT | LIT | LIT | LIT | LIT | LIT |
| A06 | be on [7,13) | LIT | **EXPR/sure** | UNDECIDED | LIT | LIT | LIT | LIT | LIT | LIT |
| A07 | turn on [3,9)+[20,22) | EXPR | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely |
| A08 | give up [3,10) | EXPR | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely |
| A09 | hot air [12,19) | LIT | EXPR/likely | EXPR/likely | LIT | LIT | LIT | LIT | LIT | EXPR/likely |
| A10 | on the run [17,27) | EXPR | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely |
| A10 | be on [13,19) | LIT | EXPR/likely | UNDECIDED | LIT | LIT | LIT | LIT | LIT | LIT |
| A11 | on the run [20,30) | MENTION | EXPR/likely | MENTION | MENTION | MENTION | MENTION | MENTION | MENTION | LIT |
| A11 | say the word | LIT | UNDECIDED | UNDECIDED | UNDECIDED | UNDECIDED | UNDECIDED | UNDECIDED | UNDECIDED | LIT |
| A12 | look up [3,9)+[19,21) | EXPR | EXPR/sure | EXPR/sure | EXPR/sure | EXPR/sure | EXPR/sure | EXPR/sure | EXPR/sure | LIT |
| A13 | hot air [26,33) | EXPR | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely |
| A14 | give up [6,13) | EXPR | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely | EXPR/likely |

† **Doğru sonuç, yanlış sebep**: beş parser'ın beşi de "Hot air rises and cold air sinks" cümlesinde "rises"ı ve
"sinks"i İSİM yaptı (gerçek çıktı: `air/NOUN/compound>rises`, `rises/NOUN/root`); R6 "air"ı bir sonraki ismin
compound'ı sandığı için LIT dedi. Bu, kuralın değil parser hatasının sonucudur; genelleme sayılmamalı.
"A08 walked away" AMBIG sayılıp skordan çıkarıldı. Her motorun ham token/POS/lemma/bağımlılık çıktısı ve karakter
aralıkları `nlp_5k_results/mini_trace_5k.jsonl`'de.

| sistem (mini, n=19) | P | R | F1 | FPR | yanlış kesin | +düzeltti | −bozdu | McNemar p |
|---|---|---|---|---|---|---|---|---|
| Storilex | 0,471 | 0,889 | 0,615 | 0,90 | 2 | — | — | — |
| kural, parser'sız | 0,800 | 0,889 | 0,842 | 0,20 | 0 | 7 | 0 | 0,016 |
| spaCy sm / md, Stanza, UDPipe EWT | 1,000 | 0,889 | 0,941 | 0,00 | 0 | 9 | 0 | 0,004 |
| UDPipe 2.1 BY-SA | 1,000 | 0,778 | 0,875 | 0,00 | 0 | 9 | 1 | 0,022 |
| AMALGrAM (yeniden eğitilmiş) | 0,800 | 0,889 | 0,842 | 0,20 | 0 | 8 | 1 | 0,039 |

Ablation: mini'deki 9 düzeltmenin 7'si parser'sız kuraldan (R0, R1) gelir; parser 2'sini ekler (A04 ve A09'daki R6;
A04'ünki yukarıdaki parser hatasıyla). "was on hand"daki `be on`'un LIT olması R1'in parser'lı kolundan gelir
(edatın nesnesi var).
Mini, kuralların yazıldığı settir; buradaki başarı genelleme kanıtı **değildir**.

### 8.2 STREUSLE resmî test (insan etiketi, doğal dağılım; 180 çok kelimeli Storilex adayı: 113 birim, 67 serbest)

Gold: aday tokenlarının hepsi tek bir STREUSLE MWE'sinin (güçlü veya zayıf) içindeyse EXPR, değilse LIT.
Bu "deyim" değil "**sözcüksel birim mi**" sorusudur.

| sistem | P | R | F1 | FPR (%95 GA) | kararsız | yanlış kesin | yanlış kart | eski yanlış→yeni doğru | eski doğru→yeni yanlış | ikisi doğru | ikisi yanlış | McNemar p | doğruluk farkı %95 GA | engellenen doğru kart |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Storilex | 0,639 | 0,938 | 0,760 | 0,896 [0,80–0,95] | 1 | 3 | 3 | — | — | 113 | 67 | — | — | — |
| kural, parser'sız | 0,636 | 0,929 | 0,755 | 0,896 | 1 | 3 | 3 | 0 | 1 | 112 | 67 | 1,00 | [−0,016, 0,005] | 0 |
| spaCy sm | 0,656 | 0,912 | 0,763 | 0,806 [0,70–0,88] | 8 | 0 | 0 | 6 | 3 | 110 | 61 | 0,51 | [−0,016, 0,049] | 3 |
| spaCy md | 0,658 | 0,920 | 0,768 | 0,806 | 7 | 0 | 0 | 6 | 2 | 111 | 61 | 0,29 | [−0,008, 0,053] | 3 |
| Stanza | 0,664 | 0,894 | 0,762 | 0,761 [0,65–0,85] | 11 | 0 | 0 | 9 | 5 | 108 | 58 | 0,42 | [−0,018, 0,063] | 4 |
| UDPipe EWT 2.5 | 0,662 | 0,903 | 0,764 | 0,776 | 10 | 0 | 0 | 8 | 4 | 109 | 59 | 0,39 | [−0,015, 0,060] | 4 |
| UDPipe 2.1 BY-SA | 0,658 | 0,885 | 0,755 | 0,776 | 11 | 0 | 0 | 8 | 6 | 107 | 59 | 0,79 | [−0,030, 0,052] | 4 |
| spaCy sm + UDPipe 2.1 (uzlaşma) | 0,658 | 0,885 | 0,755 | 0,776 | 13 | 0 | 0 | 8 | 6 | 107 | 59 | 0,79 | [−0,030, 0,052] | 3 |
| AMALGrAM (filtre olarak) | 0,867 | 0,637 | 0,735 | 0,164 [0,09–0,27] | 0 | 2 | 2 | 58 | 43 | 70 | 9 | 0,16 | [−0,025, 0,192] | 4 |

Span düzeyi (STREUSLE test, 364 gold MWE; sistemin gösterdiği çok kelimeli birimler):

| sistem | exact P | exact R | exact F1 | kısmi P | token F1 | sözlükte olan 93 gold MWE için exact R |
|---|---|---|---|---|---|---|
| Storilex | 0,583 | 0,250 | 0,350 | 0,718 | 0,401 | 0,860 |
| spaCy sm kuralı | 0,584 | 0,247 | 0,347 | 0,714 | 0,399 | 0,849 |
| Stanza kuralı | 0,586 | 0,245 | 0,345 | 0,717 | 0,397 | 0,839 |
| UDPipe EWT kuralı | 0,588 | 0,247 | 0,348 | 0,719 | 0,400 | 0,849 |
| AMALGrAM kendi MWE'leri | 0,648 | 0,475 | **0,548** | 0,798 | 0,636 | 0,656 |

AMALGrAM'ın span üstünlüğü büyük ölçüde STREUSLE'nin kendi geleneğinden (özel adlar, "a lot", isim tamlamaları) ve
aynı kaynaktan eğitilmiş olmasından gelir; Storilex sözlüğündeki kalıplarda (son sütun) Storilex daha iyi.

### 8.3 final5k (MAGPIE, insan etiketi; 969 satır, 760 deyimsel / 209 düz; deyim türleri yeni değil)

| sistem | P | R | F1 | FPR (%95 GA) | kararsız | yanlış kesin | +düzeltti | −bozdu | ikisi doğru | ikisi yanlış | McNemar p | doğruluk farkı %95 GA |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Storilex | 0,870 | 0,888 | 0,879 | 0,483 [0,42–0,55] | 32 | 0 | — | — | 783 | 186 | — | — |
| kural, parser'sız | 0,870 | 0,888 | 0,879 | 0,483 | 32 | 0 | 0 | 0 | 783 | 186 | 1,00 | [0, 0] |
| spaCy sm | 0,879 | 0,850 | 0,864 | 0,426 | 64 | 0 | 12 | 29 | 754 | 174 | **0,012** | [−0,030, −0,005] |
| spaCy md | 0,878 | 0,846 | 0,862 | 0,426 | 66 | 0 | 12 | 32 | 751 | 174 | **0,004** | [−0,034, −0,007] |
| Stanza | 0,879 | 0,862 | 0,870 | 0,431 | 51 | 0 | 11 | 20 | 763 | 175 | 0,15 | [−0,021, 0,002] |
| UDPipe EWT 2.5 | 0,879 | 0,857 | 0,867 | 0,431 | 54 | 0 | 11 | 24 | 759 | 175 | **0,041** | [−0,025, −0,001] |
| UDPipe 2.1 BY-SA | 0,880 | 0,847 | 0,863 | 0,421 | 57 | 0 | 13 | 31 | 752 | 173 | **0,010** | [−0,032, −0,005] |
| spaCy sm + UDPipe 2.1 | 0,880 | 0,830 | 0,854 | 0,411 | 82 | 0 | 15 | 44 | 739 | 171 | **0,0002** | [−0,045, −0,015] |
| AMALGrAM (filtre) | 0,882 | 0,108 | 0,192 | 0,053 | 0 | 0 | 93 | 596 | 187 | 93 | <0,0001 | [−0,561, −0,477] |

* 161 satırda (%16,6) Storilex matcher deyimi hiç aday olarak bulmuyor (varyant/çekim); hiçbir parser kuralı aday
  üretmediği için bunları düzeltemez.
* Bozulmanın ana kaynağı `prepositional_phrases` dilimi: R5 kuralı MAGPIE'deki edat deyimlerinde (ör. "in the running"
  türü) ismi edatın nesnesi olarak bulamayınca "kararsız"a düşürüyor (recall 0,94 → 0,77 spaCy sm ile).
* 5F–5J sonrası baseline'da final5k'de yanlış "kesin" zaten 0; kart onayı da 0 (deyim satırlarında "kesin" yok).
* Uzunluk dilimi (spaCy sm): 2 kelime F1 0,907→0,903; 3 kelime 0,839→0,821; 4+ kelime 0,928→0,910.

### 8.4 Türkçe sorusu (3. soru)

EXPR kararlarının Türkçesi (final5k, Storilex): 453 "var" (sözlük), 323 "yalnız AI taslağı: yeterli kaynak yok".
STREUSLE test: 148 var, 18 yalnız taslak. Hiçbir NLP motoru Türkçe sağlamaz; hiçbir yeni Türkçe yazılmadı.

## 9. Sözlük şüpheli kayıt raporu (salt okunur)

`EXPRESSION_MATCH_AUDIT_5K.tsv`: `expr` tablosunun 18.209 satırı tarandı, **5.837 satır en az bir şüphe sınıfına
girdi** (yüksek 228, orta 1.975, düşük 3.634). Sınıflar: `FUNCTION_WORDS_ONLY` 159, `BE_PLUS_PARTICLE` 2,
`LIGHT_VERB_PLUS_PARTICLE` 121, `TWO_CONTENT_WORD_IDIOM_LITERAL_RISK` 1.954, `SINGLE_WORD_IN_MULTIWORD_CATEGORY` 41,
`PARTICLE_ALSO_STARTS_PREP_PHRASES` 3.700 (yalnız phrasal verb'ler), `OBSERVED_MOSTLY_FALSE_IN_STREUSLE` 86,
`STREUSLE_CONVENTION_DIFFERS` 38 (gramer kategorileri: kanıt sayılmaz). STREUSLE kanıtı yalnız train+dev'den sayıldı.
Örnek: `be on` — STREUSLE train+dev'de 20 eşleşme, 0'ı birim, 17'si baseline'da yanlış gösterim, 4'ü yanlış "kesin";
"on" ile başlayan 426 `prepositional_phrases` kaydıyla çakışabilir. Hiçbir kayıt silinmedi veya düzeltilmedi; dosyada
lisanslı cümle metni yoktur.

## 10. Performans (masaüstü, mobil değil)

| motor | yükleme | ms/cümle (STREUSLE test) | peak RSS | disk (model) | mobil Flutter | tam offline |
|---|---|---|---|---|---|---|
| Storilex Dart | 0,47–0,75 s sözlük yükleme | ~1,9 | ölçülmedi | dict.db içinde | zaten uygulamada | evet |
| spaCy sm | 0,85 s | 4,7 | 148 MB (torch'suz) | 15 MB | Python gerekir; resmî mobil yol yok | evet (geliştiricide) |
| spaCy md | 1,75 s | 4,4 | 358 MB (torch'suz) | 55 MB | aynı | evet |
| Stanza | 3,7–5,0 s | 100–156 | 1,41 GB | 327 MB + PyTorch (venv 5,7 GB, CUDA tekerlekleri dahil) | çok zor | evet |
| UDPipe 1 | 1,0 s | 4,2 | 113 MB | 16 MB | C++ kütüphanesi; FFI ile mümkün ama yapılmadı | evet |
| AMALGrAM | Cython derleme + yükleme | ~8 (konteynerde) | ölçülmedi | 10,8 MB yeniden eğitilmiş model | Python 2.7: hayır | evet |
| DISC | — | ölçülmedi (checkpoint yok) | — | BERT-base 420 MB + checkpoint | hayır | — |

Gerçek Android/iOS cihazında hiçbir ölçüm yapılmadı. spaCy'nin ilk ölçümleri (648/859 MB) aynı venv'deki torch'un
thinc tarafından yüklenmesini içeriyordu; torch engellenerek yeniden ölçüldü (tablodaki değerler).

## 11. Lisans özeti

Ayrıntı: `MWE_DATASET_AND_LICENSE_AUDIT_5K.md`. "Kütüphane açık kaynak" ≠ "model dağıtılabilir".
UDPipe UD 2.5 modelleri **RESEARCH ONLY** (CC BY-NC-SA 4.0). #114'teki yayın kapısı (damdafayton lisansı belirsiz,
FreeDict GPL) bu çalışmadan etkilenmedi ve atlanmadı.

## 12. Doğrulama

* `flutter analyze`: 0 hata, 0 uyarı, 126 info; #120 HEAD'de de 126 info (aynı).
* `flutter test`: 601 geçti, 12 atlandı, 3 başarısız: `import_completeness_test`, `picture_book_test`, `text_repair_test`
  (`setUpAll`, "Failed to load PDFium module"), bilinen PDFium ortam sorunu; `lib/` ve `test/` değişmedi.
* `python -m pytest tools/nlp_lab_5k/tests`: lab venv'inde 9/9; modelsiz temiz venv'de 7 geçti, 2 atlandı.
* Yeni CI: `.github/workflows/nlp-lab-5k.yml`, yalnız `tools/nlp_lab_5k/**` değişince, modelsiz offline testler +
  veritabanı hash kontrolü. Varsayılan Flutter build'e yeni bağımlılık girmedi.

## 13. Riskler ve sonraki adım

* Mini suite etiketleri Claude yazımı (proxy). STREUSLE ve MAGPIE etiketleri insan etiketidir ama "deyim" ile "MWE"
  aynı şey değildir; MAGPIE seti deyim türü bakımından yeni değildir.
* Önerilen sonraki görev: Dart'ta parser'sız iki kural — (1) `be` + edat iki kelimelik kalıp asla "kesin" değil,
  (2) eşit uzunlukta çakışmada edat, kendisinden sonra isim gelen edat+isim kalıbına (on hand, on duty, on the run)
  bırakılır. Bunun için yeni bir kilitli final ve STREUSLE testi yeniden kullanılmamalı (burada açıldı).
* `be on` gibi yüksek riskli kayıtların insan incelemesi: TSV'deki `risk=high` satırları (228).
