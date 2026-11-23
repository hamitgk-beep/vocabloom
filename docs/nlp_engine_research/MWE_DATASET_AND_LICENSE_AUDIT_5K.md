# Görev 5K: MWE veri kümeleri, model ağırlıkları ve lisans denetimi

Kural: kod kütüphanesinin lisansı, model ağırlığının lisansı, eğitim verisinin lisansı ve ticari/kapalı dağıtım hakkı
**ayrı ayrı** değerlendirilir. "Kütüphane açık kaynak" bir modelin dağıtılabileceğini kanıtlamaz. Lisansı belirsiz
olan hiçbir şey araştırma ortamı dışında kullanılmaz. Bu tablo hukuki görüş değildir; üretime almadan önce insan
incelemesi gerekir. Storilex kodu GPL-3.0'dır; uygulama mağaza dağıtımıyla yayımlanır.

Bu görevde hiçbir model ağırlığı, üçüncü taraf kaynak kodu, lisanslı cümle metni veya türetilmiş anotasyon repoya
ya da uygulama paketine girmedi (`tools/nlp_lab_5k/.gitignore`). Commit edilenler: kendi kodumuz, Claude yazımı mini
suite, hash'ler, toplu metrikler ve STREUSLE/MAGPIE'den metin taşımayan sayımlar.

## 1. Kod kütüphaneleri

| bileşen | sürüm / commit | kod lisansı | kaynak | not |
|---|---|---|---|---|
| spaCy | 3.8.7 | MIT | pypi, github.com/explosion/spaCy | thinc, torch kuruluysa onu da yükler |
| Stanza | 1.10.1 | Apache-2.0 | pypi, github.com/stanfordnlp/stanza | PyTorch gerekir |
| UDPipe 1 (ufal.udpipe) | 1.3.1.1 | MPL-2.0 | pypi, github.com/ufal/udpipe | UDPipe 2 ayrı bir sistemdir (Python + TensorFlow/PyTorch, modelleri yalnız lindat'ta ve çevrimiçi serviste); bu görevde UDPipe 2 **çalıştırılmadı** |
| AMALGrAM 2.0 (pysupersensetagger) | `4783c54a28d8…` (2017-05-31) | GPLv3 (LICENSE dosyası) | github.com/nschneid/pysupersensetagger | Python 2.7 + Cython; kapalı kaynaklı bir uygulamaya otomatik paketlenemez |
| DISC | `7542fcd67dfb…` (2021-09-26) | README "MIT" diyor, **depoda LICENSE dosyası yok** → belirsiz | github.com/zzeng13/DISC | README'deki `requirements.txt` de depoda yok |
| udpipe R modelleri (bnosac) | `1fe82357…` | eğitim betikleri MPL-2.0 | github.com/bnosac/udpipe.models.ud | yalnız modeli kullandık |

## 2. Model ağırlıkları

| model | sha256 | ağırlık lisansı | eğitim verisi / provenance | ticari dağıtım | statü |
|---|---|---|---|---|---|
| `en_core_web_sm` 3.8.0 | wheel `1932429d…` | MIT (model meta) | OntoNotes 5 (LDC), ClearNLP dönüşümü, WordNet 3.0 | Explosion MIT olarak dağıtıyor; OntoNotes metni modelde yok | araştırma; üretim gerekirse ayrıca hukuki kontrol |
| `en_core_web_md` 3.8.0 | wheel `5e6329fe…` | MIT | yukarıdaki + Explosion Vectors (OSCAR 2109, Wikipedia, OpenSubtitles, WMT News Crawl) | aynı | araştırma |
| Stanza `en` default (combined; tokenize/mwt/pos/lemma/depparse + charlm + conll17 pretrain) | resources 1.10.0, HF `stanfordnlp/stanza-en` sha `03960e98…` | model kartı **Apache-2.0** | combined UD İngilizce treebank'leri (EWT CC BY-SA 4.0, GUM vb. kendi lisanslarıyla); lemmatizer sözlüğünde **SPECIALIST Lexicon** girdileri (NLM, kendi Terms & Conditions'ı) | Apache beyanı + ek SPECIALIST koşulları + share-alike eğitim verisi: **belirsiz** | yalnız araştırma |
| UDPipe 1 `english-ewt-ud-2.5-191206` | `784bd0fa…` | **CC BY-NC-SA 4.0** | UD 2.5 EWT; lindat 11234/1-3131 (biz jwijffels/udpipe.models.ud.2.5 @ `17d6bbfb…` kopyasını indirdik) | **hayır (ticari olmayan)** | **RESEARCH ONLY**; üretime ve dağıtılabilir artefakta girmez |
| UDPipe 1 `english-ud-2.1-20180111` (bnosac) | `20432a6f…` | CC BY-SA 4.0 (src/english/LICENSE) | UD_English 2.1 (CC BY-SA 4.0) + fastText vektörleri (CC BY-SA 3.0) | atıf + share-alike ile izinli; GPL-3.0 uygulamayla birlikte dağıtım için share-alike etkisi incelenmeli | ticari izinli alternatif; bu görevde yararı ölçülmedi → üretime alınmadı |
| UDPipe 1 `english-gum-ud-2.5-191206` | `8023726e…` | CC BY-NC-SA 4.0 | UD 2.5 GUM | hayır | indirildi, kullanılmadı |
| AMALGrAM resmî `sst.model` + `mwelex/` | — | bilinmiyor | cs.cmu.edu/~ark/LexSem (erişilemedi) | — | **indirilemedi** |
| AMALGrAM yeniden eğitilmiş MWE modeli (bizim) | 10,8 MB, yerel | türev: STREUSLE anotasyonları CC BY-SA 4.0 + EWT metni (Google/LDC izniyle STREUSLE içinde) | STREUSLE train (2.725 cümle), gold PTB POS | **hayır**: EWT metninin yeniden dağıtım izni bize geçmez | yerel, commit edilmedi, araştırma |
| DISC MAGPIE random-split checkpoint | — | belirtilmemiş | Google Drive (proxy 403) | belirsiz | **indirilemedi** |
| bert-base-uncased (DISC bağımlılığı) | HF snapshot `86b5e093…` | Apache-2.0 | BookCorpus + Wikipedia | Apache-2.0 | yalnız DISC denemesi için indirildi |
| DISC deposundaki GloVe gömmeleri (`*_glove_embed.npy`) | — | GloVe: PDDL | Common Crawl/Wikipedia | — | kullanılmadı |

## 3. Veri kümeleri

| veri | sürüm | etiket lisansı | metin lisansı | bu görevde | eğitim sızıntısı |
|---|---|---|---|---|---|
| STREUSLE | `8ba61fe4…` (EWT v2.17) | MWE + supersense anotasyonları CC BY-SA 4.0; UD anotasyonları aynı lisansla | EWT reviews cümleleri ve PTB POS: Google ve LDC izniyle yeniden dağıtılıyor (bize geçmez) | yerel değerlendirme (train ile AMALGrAM eğitimi; dev ayar; test bir kez, dondurmadan sonra) | AMALGrAM STREUSLE train ile eğitildi; UD parser'lar EWT train ile (STREUSLE train cümleleri); STREUSLE test = EWT test, parser'ların eğitimi dışında |
| MAGPIE | `7fa677b` | CC BY 4.0 (kalabalık etiket) | çoğu BNC: yeniden dağıtılamaz | final5k yalnız yerel; hash commit edildi | DISC checkpoint'i MAGPIE random-split train ile eğitildi; final5k'nin 954/969 satırı yalnız DISC test'inde, 7 satır train/valid'de de var |
| mini suite (14 cümle) | bu PR | Claude yazımı (proxy) | Claude yazımı | commit edildi | tasarım seti |
| Storilex `assets/dict.db` | `ab4a7a53…` | #114 kapısı: damdafayton lisansı belirsiz, FreeDict GPL | — | salt okunur | — |

STREUSLE kendisi **bir model değildir** ve tespit motoru gibi raporlanmadı. STREUSLE README'sinde bağlantısı olan
lexical semantic recognition tagger'ı (nelson-liu/lexical-semantic-recognition) bonus aday olarak **denenmedi**
(AllenNLP 0.x + BERT/ELMo bağımlılıkları ve süre); üçüncü taraf kodu kopyalanmadı.

## 4. Araştırma ve üretim statüsü

| aday | araştırma | üretim (Flutter APK/IPA) |
|---|---|---|
| spaCy + sm/md | evet (geliştirici makinesi) | hayır: Python çalışma zamanı; ölçülen kazanç yok |
| Stanza | evet | hayır: PyTorch, lisans belirsizliği |
| UDPipe 1 EWT 2.5 | evet, **RESEARCH ONLY** | **asla** (NC) |
| UDPipe 1 UD 2.1 (CC BY-SA) | evet | şu an hayır; ileride kazanç kanıtlanırsa share-alike ve atıf yükümlülükleriyle değerlendirilebilir |
| AMALGrAM | evet (Docker, Python 2.7) | hayır: GPLv3 Python 2.7, model kaynağı yok |
| DISC | kurulum evet, çıkarım hayır | hayır |
| STREUSLE | yerel değerlendirme verisi | hayır (metin ve türetilmiş anotasyon uygulamaya girmez) |
| MAGPIE | yerel değerlendirme verisi | hayır |

Yeni Türkçe anlam veya çeviri yazılmadı; hiçbir AI taslağı doğrulanmış sayılmadı.
