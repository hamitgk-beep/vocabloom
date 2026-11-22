# Lisans matrisi: ticari kullanım ve dağıtım (Görev 5A)

Tarih: 22 Kasım 2026. **Bu bir hukuki görüş değildir.** Her satır, aşağıdaki "Kanıt" sütunundaki belgenin
bu tarihte okunan metnine dayanır. Yazılım, model ve veri lisansı ayrı ayrı yazıldı. "Ücretsiz indirilebilir"
bilgisi yeniden dağıtım izni olarak yorumlanmadı.

Kanıt türleri: **D** = lisans dosyası bu ortamdan indirilip okundu (raw.githubusercontent.com, PyPI, Hugging Face API,
veri dosyasının kendi başlığı). **W** = resmî web sayfası web üzerinden okundu (alıntılar kısa). **R** = önceki
proje raporundan (PR #104/#106 `tools/lexicon/LICENSE_REPORT.md`) alındı, bu çalışmada yeniden okunmadı.
**?** = doğrulanamadı.

Storilex'in durumu: kaynak kodu GPL-3.0; `assets/dict.db` CC BY-SA 4.0 ile paylaşılıyor; uygulama reklamlı/ücretli
dağıtılabilir. Bu yüzden **NC (ticari olmayan)** ve **ND (türetilemez)** koşulları kabul edilemez; **SA (share-alike)**
koşulu sözlük için CC BY-SA 4.0 ile uyumluysa kabul edilebilir.

Sütunlar: Tic. = ticari kullanım; Dağ. = uygulamayla yeniden dağıtım; Atıf; SA = share-alike etkisi; Çevr. = çevrimdışı.

## 1. Sözlük ve anlamsal kaynaklar

| Kaynak | Bileşen | Lisans | Tic. | Dağ. | Atıf | SA | Çevr. | Kanıt | Not |
|---|---|---|---|---|---|---|---|---|---|
| Open English WordNet 2025 | veri | CC BY 4.0 (+ Princeton WordNet License atfı) | ✅ | ✅ | ✅ PWN + OEWN | – | ✅ | D: `LICENSE.md`; XML başlığı `license="https://creativecommons.org/licenses/by/4.0"` | 31 Ara 2025 sürümü; GitHub release'ten indi |
| Princeton WordNet 3.0 | veri+yazılım | WordNet License | ✅ | ✅ (bildirim her kopyada) | ✅ | – | ✅ | D: nltk_data `wordnet/LICENSE` | Projede kullanılıyor |
| Wiktionary (EN/TR) | veri | CC BY-SA 4.0 ve GFDL (ikili) | ✅ | ✅ | ✅ | **SA** | ✅ (döküm) | W: Wiktionary:Copyrights ("dual-licensed … CC-BY-SA … and the GNU Free Documentation License"; sayfa kendini "draft proposal" olarak tanımlıyor) | Alıntı/dış kaynaklı kısımlar kendi şartlarını korur |
| Kaikki / wiktextract | kod | MIT | ✅ | ✅ | ✅ | – | ✅ | D: `tatuylonen/wiktextract/LICENSE` | kaikki.org bu ortamdan **erişilemedi** (403) |
| Kaikki | veri | Wiktionary'den türetilmiş → CC BY-SA 4.0/GFDL | ✅ | ✅ | ✅ | SA | ✅ | W: HF aynası `DataDock/wiktextract` kartı `cc-by-sa-4.0` (resmî site değil) | Resmî sayfa doğrulanamadı ? |
| Open Multilingual Wordnet | veri | her wordnet ayrı lisans | değişir | değişir | ✅ | değişir | ✅ | D: `omwn/omw-data/README.md`, `index.toml` | **Türkçe wordnet yok** (index'te `tr` paketi bulunmadı) |
| KeNet (Türkçe WordNet) | veri | CC BY-SA 4.0 | ✅ | ✅ | ✅ | SA | ✅ | D: README "Licensing" bölümü | Repo kökündeki `LICENSE` GPL-3.0'dır ve **yalnız koda** uygulanır |
| CILI | veri | CC BY 4.0 | ✅ | ✅ | ✅ | – | ✅ | D: `globalwordnet/cili/LICENSE` | |
| BabelNet | veri+API | BabelNet Non-Commercial (BY-NC-SA öğeleri) | ❌ | ❌ (yalnız araştırma kurumlarına) | ✅ | SA | ⚠️ | W: babelnet.org/full-license ("made accessible only to research institutions") | Ticari lisans Babelscape'ten ayrıca alınır; **önerilmez** |
| ConceptNet 5 | veri | CC BY-SA 4.0 (bazı parçalar CC BY-SA 3.0, CC BY 3.0) | ✅ | ✅ | ✅ (DATA-CREDITS) | SA | ✅ | D: `LICENSE.txt` + wiki "Copying and sharing" | Kod ve veri ayrı; Türkçe kapsamı zayıf (Wiktionary'den) |
| PanLex | veri | **Çelişkili**: panlex.org/license → CC BY-NC-SA 4.0, db.panlex.org/README → CC0 1.0 | ? | ? | ? | ? | ✅ | W: iki sayfa | Çelişki çözülmeden **kullanılmamalı** |
| FreeDict eng-tur 0.3 | veri | GPL-2.0-or-later | ✅ | ✅ (GPL şartlarıyla) | ✅ | **copyleft** | ✅ | D: `eng-tur.tei` başlığı (36.589 madde, 2017) | CC BY-SA veritabanına konunca uyum belirsiz (bkz. §5) |
| DBnary | veri | CC BY-SA 4.0 (Wiktionary'den) | ✅ | ✅ | ✅ | SA | ✅ (Turtle, Zenodo) | W: kaiko.getalp.org about sayfası alt bilgisi; D: kod README | Wiktionary ile aynı içerik: **bağımsız kanıt değildir** |
| OpenThesaurus | veri | (Almanca eş anlamlılar) | – | – | – | – | – | D: README | İngilizce/Türkçe kapsamı yok, kapsam dışı |
| ECDICT | veri | MIT | ✅ | ✅ | ✅ | – | ✅ | D: `LICENSE` | İngilizce–Çince; Türkçe yok |
| damdafayton/eng-tur-dictionary | veri | README "MIT" diyor, `MIT.md` bağlantısı **404**, lisans dosyası yok, veri kökeni yok | ? | ? | ? | ? | ✅ | D: README + 404 denemesi | **Şu an `ft` içinde ve Ayarlar'da "(MIT)" yazıyor** |
| Kindle EN–TR (mybottles) | veri | Build kodu MIT; sözlük içeriği **GPL v2.0+** | ✅ | GPL şartlarıyla | ✅ | copyleft | ✅ | D: README "Lisans" | Storilex "yalnız Wiktionary kısmını" aldığını söylüyor |
| TDK, Oxford, Cambridge, Longman | veri | ticari / tüm hakları saklı | ❌ | ❌ | – | – | – | genel bilgi | Yalnız **yöntem** örneği olarak incelenir, içerik alınmaz |

## 2. Dil işleme ve dilbilgisi araçları

| Araç | Bileşen | Lisans | Tic. | Dağ. | Kanıt | Not |
|---|---|---|---|---|---|---|
| spaCy 3.8.x | kod | MIT | ✅ | ✅ | D: `LICENSE` | |
| en_core_web_sm 3.8.0 | model | MIT (OntoNotes 5 eğitimli, Explosion lisanslı) | ✅ | ✅ | R + HF API `license:mit` | |
| Stanza | kod | Apache-2.0 | ✅ | ✅ | D | |
| Stanza TR/EN modelleri | model | HF kartı Apache-2.0; ama varsayılan TR paketi IMST (**CC BY-NC-SA 4.0**), EN içinde GUM (kısmen **NC**) | ⚠️ | ⚠️ | D: UD `LICENSE.txt` dosyaları; HF API | Kart ile eğitim verisi çelişiyor |
| Zemberek-NLP 0.18.0 | kod+jar | Apache-2.0 | ✅ | ✅ | D: `LICENSE`, README | Kök sözlüğünün kökeni (TDK örtüşmesi) belirsiz; yalnız çözümleme için |
| TRmorph | kod+FST | MIT | ✅ | ✅ | D: `LICENSE`, README "New license … MIT" | Foma gerektirir |
| Universal Dependencies | veri | treebank'e göre: EWT CC BY-SA 4.0; GUM CC BY-NC-SA 4.0 (wikiHow, kurmaca NC); TR-IMST **CC BY-NC-SA 4.0**; TR-BOUN, TR-Kenet, TR-Penn CC BY-SA 4.0 | değişir | değişir | D: her treebank'in `LICENSE.txt` | Değerlendirme için kullanıldı, uygulamaya girmez |
| Trankit | kod | Apache-2.0 | ✅ | ✅ | D: `LICENSE` | Modeller UD + XLM-R; model lisansı ? (doğrulanamadı) |
| UDPipe | kod | MPL-2.0 | ✅ | ✅ | D: `LICENSE`, README | |
| UDPipe modelleri | model | **CC BY-NC-SA 4.0** | ❌ | ❌ | W: b2find kaydı (UD 2.15 modelleri), ÚFAL model sayfası (UD 2.17) | Önerilmez |
| LanguageTool | kod | LGPL-2.1 | ✅ | ✅ | D: `COPYING.txt` | **Türkçe desteklenmiyor** (W: dev.languagetool.org/languages) |
| Morfessor 2.0 | kod | BSD-2-Clause | ✅ | ✅ | D: `LICENSE` | Denetimsiz biçimbirim bölme |
| google-research/turkish-morphology | kod+veri | Apache-2.0 | ✅ | ✅ | D: `LICENSE` | Alternatif Türkçe çözümleyici, ölçülmedi |
| TurkicNLP | kod | Apache-2.0; Apertium FST GPL-3.0, TR Stanza IMST NC | ⚠️ | ⚠️ | R | Önerilmez |

## 3. Cümle, deyim ve kullanım örnekleri

| Kaynak | Lisans | Tic. | Dağ. | Atıf | SA | Kanıt | Not |
|---|---|---|---|---|---|---|---|
| Tatoeba | Varsayılan CC BY 2.0 FR; cümle başına farklı (CC0, SA, ND, "non-marketing" olabilir) | ✅ (çoğu) | ✅ | ✅ yazar adı | bazı cümleler | W: tatoeba.org Terms of Use §6.2–6.5 | **Cümle başına lisans izlenmeli** |
| OPUS (genel) | Genel lisans yok; her derlem ayrı | ? | ? | ✅ atıf | ? | W: GitHub README, OPUS sayfaları ("We do not own any of the text") | |
| OPUS OpenSubtitles | Lisans adı yok, yalnız atıf isteği | ? | ? | ✅ | ? | W | Örnek cümle olarak dağıtılmamalı |
| OPUS NLLB / CCMatrix | Lisans adı yok (Meta meta-verisinden) | ? | ? | ✅ | ? | W | Önerilmez |
| WikiMatrix | CC BY-SA | ✅ | ✅ | ✅ | SA | D: LASER `tasks/WikiMatrix/README.md` | Otomatik hizalı, gürültülü |
| PARSEME 1.3 | Dile göre: **EN** VMWE CC BY 4.0, morfosözdizim CC BY-SA 4.0; **TR** VMWE ve morfosözdizim **CC BY-NC-SA 4.0** | EN ✅ / TR ❌ | EN ✅ / TR ❌ | ✅ | EN SA | W: LINDAT lisans sayfası | Türkçe kısmı yalnız iç değerlendirme |
| MAGPIE | Etiketler CC BY 4.0; cümleler çoğunlukla BNC (dağıtılamaz) | etiket ✅ | metin ❌ | ✅ | – | D: `LICENSE`; mevcut `build_sense_eval.py` notu | Yalnız yerel ölçüm |
| Project Gutenberg | ABD'de kamu malı (ülke/baskıya göre değişir) | ✅ | ✅ (marka şartı) | – | – | R | |
| Wikisource TR (N. Hoca, Ö. Seyfettin) | kamu malı | ✅ | ✅ | – | – | R | |
| SemCor 3.0 | WordNet 1.6 tipi Princeton lisansı | ✅ | ✅ (bildirimle) | ✅ | – | D: nltk_data `semcor/LICENSE` | Değerlendirme |

## 4. Sıklık, anlam benzerliği ve modeller

| Kaynak | Bileşen | Lisans | Tic. | Dağ. | Kanıt | Not |
|---|---|---|---|---|---|---|
| wordfreq 3.1.1 | kod | Apache-2.0 | ✅ | ✅ | D: README + PyPI | |
| wordfreq | veri | CC BY-SA 4.0; içinde SUBTLEX (yazarın e-posta izniyle "any purpose", atıf şartlı), OpenSubtitles (atıf), Google Books Ngrams | ✅ | ✅ (atıf+SA) | ✅ | D: README "License" | **Veri artık güncellenmiyor** (README, SUNSET.md) |
| SUBTLEX-US (doğrudan) | veri | CC BY-NC-ND 3.0 | ❌ | ❌ | W: LexOPS lisans dosyası (resmî UGent sayfasında şart yok) | Doğrudan değil, yalnız wordfreq üzerinden |
| FrequencyWords (hermitdave) | kod MIT; veri OpenSubtitles'tan | ⚠️ | ⚠️ | D: `LICENSE` (MIT) | tr_en.db `meta` "CC BY-SA 4.0" diyor; OpenSubtitles kökeni lisanssız |
| paraphrase-multilingual-MiniLM-L12-v2 | model | Apache-2.0 | ✅ | ✅ | D: HF API | PR #106'da isteğe bağlı |
| LaBSE | model | Apache-2.0 | ✅ | ✅ | D: HF API | 1,8 GB, cümle hizalama için güçlü |
| multilingual-e5-small | model | MIT | ✅ | ✅ | D: HF API | |
| BGE-M3 | model | MIT | ✅ | ✅ | D: HF API | 2,2 GB |
| XLM-RoBERTa base | model | MIT | ✅ | ✅ | D: HF API | |
| BERTurk (dbmdz) | model | MIT | ✅ | ✅ | D: HF API | |
| OPUS-MT tc-big-en-tr | model | CC BY 4.0 | ✅ | ✅ (atıf) | D: HF API + `tools/mt_eval/README.md` | #107/#108'de isteğe bağlı |
| OPUS-MT tr-en | model | Apache-2.0 | ✅ | ✅ | D: HF API | Ters yön için aday |

Not: Modellerin eğitim verilerinin (paralel derlemler) lisansı ayrıca incelenmedi. Model çıktısı sözlüğe yalnız
**puan/öneri** olarak girer, metin olarak kopyalanmaz (PR #106 kuralı).

## 5. Açık hukuki belirsizlikler (öncelik sırasıyla)

1. **damdafayton verisi** `ft` içinde: lisans dosyası yok, kökeni bilinmiyor; Ayarlar "MIT" yazıyor. Yayın öncesi
   ya yazardan yazılı izin + köken bilgisi alınmalı ya da bu satırlar `ft`'den ayrıştırılıp (kaynak etiketiyle)
   gösterimden çıkarılmalı. Önce kaç anlamın yalnız bu kaynaktan geldiği ölçülmeli (bugün `ft`'de kaynak etiketi yok).
2. **GPL içerik CC BY-SA 4.0 veritabanında:** FreeDict (GPL-2.0+) `tr_en.db`'de 23.952 anlam ("fd") ve `expr`
   yedeğinde. CC BY-SA 4.0 → GPLv3 yönünde tek yönlü uyumluluk vardır; tersi (GPL içeriği CC BY-SA altında dağıtmak)
   için böyle bir izin yoktur. Seçenekler: (a) bu kısımları GPL-3.0 ile ayrı bir dosyada dağıtmak, (b) veritabanının
   tamamını GPL-3.0+CC BY-SA birlikte işaretlemek, (c) çıkarmak. Uzman görüşü gerekir.
3. **Kindle derlemesi:** içerik GPL v2+ (FreeDict mirası). "Yalnız Wiktionary kısmı" ayrımı, derlemenin kaynak
   alanlarıyla yeniden doğrulanmalı.
4. **`tr_en.db` meta bilgisi eksik:** `meta.sources` FreeDict ve WordNet tersini listelemiyor. Atıf ekranı bu yüzden
   eksik kalabilir.
5. **FrequencyWords/OpenSubtitles:** sıklık sayısı (sıra) olarak kullanılıyor; OpenSubtitles'ın açık bir lisansı yok.
   Sıra bilgisi düşük risklidir ama `meta` "CC BY-SA 4.0" yazıyor; dayanağı belgelenmeli.
6. **Tatoeba cümle başına lisans:** varsayılan CC BY 2.0 FR, ama ND/"non-marketing" cümle olabilir; içe alım sırasında
   cümle lisans alanı saklanmıyor.
7. **AI çıktıları:** servis şartları çıktıyı kullanıcıya bırakıyor (README), ama bu bir kalite onayı değildir.
   NVIDIA denemesi gibi "yalnız test" şartlı çıktının veriye girmediği kayıtla kanıtlanmalı.
8. **Zemberek kök sözlüğü:** TDK ile örtüşme şüphesi (R); yalnız çözümleme için kullanılmalı, liste kopyalanmamalı.
9. **PanLex:** iki resmî sayfa çelişiyor; kullanılmamalı.

## 6. Atıf yükümlülükleri (yayına girerse)

OEWN ("Open English Wordnet, CC BY 4.0" + Princeton WordNet bildirimi), Wiktionary/kaikki (CC BY-SA 4.0, sayfa
geçmişine bağlantı yerine proje bağlantısı), KeNet (CC BY-SA 4.0), CILI (CC BY 4.0), Tatoeba (cümle yazarları,
CC BY 2.0 FR), wordfreq (Robyn Speer + SUBTLEX yazarları, CC BY-SA 4.0), OPUS-MT (Helsinki-NLP, CC BY 4.0).
