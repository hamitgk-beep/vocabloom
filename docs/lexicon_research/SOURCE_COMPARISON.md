# Kaynak karşılaştırması (Görev 5A, Aşama 2)

Tarih: 22 Kasım 2026. Lisans ayrıntıları ve kanıtları için LICENSE_MATRIX.md'ye bakın; burada lisans yalnız
karar için özetlenir. "Ölçüldü" yazan sayılar bu çalışmada indirilen dosyalardan sayıldı; "≈" yazanlar belgelerden
veya genel bilgiden alındı ve bu ortamda doğrulanmadı.

Ortam sınırı: bu ortamdan kaikki.org, en-word.net, opus.nlpl.eu, tatoeba.org indirmeleri, universaldependencies.org ve
panlex.org **erişilemedi** (vekil sunucu 403). GitHub (raw + release), PyPI ve Hugging Face erişilebildi. Erişilemeyen
sitelerin lisans sayfaları web üzerinden okundu, verileri indirilemedi.

## Karar ölçütü

Bir kaynak ancak şu üçü birlikte sağlanırsa önerildi: (1) ticari dağıtıma uygun, açık lisans; (2) çevrimdışı
çalışır; (3) Storilex'te **ölçülebilir** bir yanlışı azaltır veya ölçülebilir bir eksiği kapatır. Popülerlik ölçüt
değildir. Aynı içeriğin kopyası (ör. DBnary = Wiktionary) "bağımsız kaynak" sayılmaz.

## 1. Sözlük ve anlamsal kaynaklar

| Kaynak | Resmî adres | Boyut / kapsam | EN / TR | Bakım | Bilinen sorunlar | Storilex'e somut katkı | Karar |
|---|---|---|---|---|---|---|---|
| **Open English WordNet 2025** | github.com/globalwordnet/english-wordnet (release `2025-edition`) | XML.gz 11,4 MB; **127.311 lemma** (ölçüldü) | EN ✅ / TR – | Yıllık sürüm (2024, 2025) | 2025'ten beri özel adların çoğu ayrı "Open English Namenet"e taşındı | WN 3.0'daki hataların düzeltilmiş hâli; dict.db'de olmayan 4.211 lemma (ölçüldü), yeni anlamlar, düzeltilmiş tanımlar. CC BY 4.0, WN 3.0'dan daha temiz lisans | **Seviye 1** – WN 3.0'ın yerine kademeli |
| Princeton WordNet 3.0 | wordnet.princeton.edu | 147.306 lemma (dict.db'de) | EN ✅ | 2006'dan beri güncellenmiyor | Eskimiş anlamlar, bilinen hatalar OEWN'de düzeltildi | Zaten kullanılıyor | Kalsın, OEWN'e geçiş |
| **Wiktionary (kaikki/wiktextract)** | kaikki.org, github.com/tatuylonen/wiktextract | EN Wiktionary tam dökümü ≈ 20 GB JSONL (≈); TR çevirileri onbinlerce | EN ✅ / TR ✅ | Haftalık döküm | Çeviriler gönüllü, anlam bağı zayıf; etiket/biçim gürültüsü | Zaten ft, expr ve tr_en'in ana kaynağı. Yeni katkı: **anlam başına çeviri** (çeviri tablosunun hangi anlama ait olduğu) ve örnek cümleler; damdafayton'un yerini alabilecek açık lisanslı ana kaynak | **Seviye 1** – yeniden çıkarım, anlam bağlantılı |
| Türkçe Vikisözlük | tr.wiktionary.org (kaikki üzerinden) | ≈ (doğrulanmadı) | TR ✅ | Döküm | Az madde, düzensiz şablon | TR→EN tarafında bağımsız ikinci tanık | Seviye 2 |
| **KeNet** | github.com/StarlangSoftware/TurkishWordNet | ≈ 80.000 synset (≈) | TR ✅ | Ara sıra | CILI eşlemesi kısmi; dict.db'de synset'lerin %12'sinde Türkçe | Zaten syn.tr. Elle yapılmış, **Wiktionary'den bağımsız** Türkçe: anlam doğrulamada en değerli ikinci tanık | **Seviye 1** – tanık olarak güçlendir |
| Open Multilingual Wordnet | github.com/omwn/omw-data | 150+ dil | TR **yok** (çekirdekte) | Etkin | Türkçe yalnız Wiktionary'den otomatik ("wikt") | Yeni katkı yok | Önerilmez |
| BabelNet | babelnet.org | Çok büyük | EN/TR ✅ | Etkin | Lisans: ticari değil, yalnız araştırma kurumlarına | Ticari dağıtım yasak | **Önerilmez** |
| ConceptNet 5.7 | github.com/commonsense/conceptnet5 | ≈ 34 M kenar (≈) | EN ✅ / TR zayıf | 2019'dan beri durgun (≈) | Türkçe kısmı Wiktionary kopyası | Eş anlam/ilişki sinyali; ama Wiktionary ile aynı köken | Önerilmez (bağımsız değil) |
| PanLex | panlex.org | Çok dilli, büyük | EN/TR ✅ | Belirsiz | **Lisans sayfaları çelişkili** (CC0 / CC BY-NC-SA) | – | **Önerilmez** (lisans) |
| FreeDict eng-tur 0.3 | github.com/freedict/fd-dictionaries | 36.589 madde (ölçüldü, dosya başlığı) | EN→TR | Son düzenleme 2017 | Eski, gtksozluk2 dönüşümü; GPL | Zaten kullanılıyor (yedek, tr_en "fd") | Yeni kullanım yok; lisans düzeltmesi |
| DBnary | kaiko.getalp.org | 26 Vikisözlük dili, RDF | EN/TR ✅ | Döküm başına | Wiktionary ile **aynı içerik** | Bağımsız tanık değil; RDF yapısı kolaylık sağlar | Önerilmez (kopya) |
| OpenThesaurus | openthesaurus.de | Almanca | – | | | Kapsam dışı | Önerilmez |
| ECDICT | github.com/skywind3000/ECDICT | EN–ZH | TR yok | | | Kapsam dışı | Önerilmez |
| damdafayton/eng-tur-dictionary | github.com/damdafayton/eng-tur-dictionary | ≈ | EN→TR | | Lisans dosyası yok, köken yok | Bugün ft'de; risk | **Çıkış planı** |
| Oxford / Cambridge / Longman | – | – | – | – | Lisanslı içerik | Yalnız **yöntem**: kontrollü tanım sözcüğü (Longman ≈2.000), sıklık bantları (Oxford 3000/5000 fikri), CEFR etiketleri, gerçek derlem örnekleri, editör onayı | İçerik alınmaz |

## 2. Dil işleme ve dilbilgisi

| Araç | Lisans (kod / model) | Boyut | EN / TR | Ölçülen katkı | Karar |
|---|---|---|---|---|---|
| **Yerleşik kurallar** (`baseForms`, `grammar_marks`) | GPL-3.0 (Storilex) | 0 | EN ✅ / TR kısmi | EWT'de kök %95,6 (ölçüldü) | Uygulamada kalır |
| **spaCy 3.8 + en_core_web_sm** | MIT / MIT | ≈ 300 MB ortam | EN ✅ | #104: kök 0,983, özel ad 1,000 (30 cümle, Claude etiketi) | **Seviye 2** – yalnız geliştirici hattı |
| **Zemberek 0.18.0** | Apache-2.0 | 9,3 MB jar | TR ✅ | #104: gürültülü aday 10.328 → 2.287 | **Seviye 2** – yalnız çözümleme |
| TRmorph | MIT | küçük FST | TR ✅ | Ölçülmedi | Zemberek'e ikinci tanık olarak Seviye 2 adayı |
| Stanza | Apache-2.0 / modeller NC verisiyle eğitilmiş | PyTorch | EN/TR | Ek katkı küçük (#106) | Önerilmez (lisans belirsiz) |
| Trankit | Apache-2.0 / model lisansı doğrulanamadı | XLM-R, GB'lar | EN/TR | Ölçülmedi | Önerilmez |
| UDPipe 2 | MPL-2.0 / modeller CC BY-NC-SA | | EN/TR | – | **Önerilmez** (NC) |
| Universal Dependencies | treebank'e göre | | EN/TR | Değerlendirme verisi | **Değerlendirme** için (EWT, BOUN, Kenet, Penn) |
| LanguageTool | LGPL-2.1 | | EN ✅ / **TR yok** | – | Türkçe için işe yaramaz; İngilizce gramer işaretlerine ikinci görüş olabilir (Seviye 3, ölçülmeden önerilmez) |
| Morfessor 2.0 | BSD-2 | küçük | dil bağımsız | – | Kural tabanlı çözümleyici varken gereksiz |
| google-research/turkish-morphology | Apache-2.0 | | TR | Ölçülmedi | İzlenecek alternatif |

## 3. Cümle, deyim ve kullanım örnekleri

| Kaynak | Kapsam | Kalite | Katkı | Karar |
|---|---|---|---|---|
| **Tatoeba** | EN–TR yüz binlerce çift; tr_en'de 639.686 cümle bağlamı (ölçüldü, `meta.ctx`) | İnsan çevirisi, ama kısa ve tekrarlı; isim yanlılığı ("Tom") | Zaten kullanılıyor; cümle başına lisans alanı eklenmeli | **Seviye 1** (lisans alanıyla) |
| OPUS OpenSubtitles | çok büyük | gürültülü, lisanssız | – | Önerilmez (dağıtım) |
| WikiMatrix | EN–TR ≈ yüz binlerce (≈) | otomatik hizalı, gürültülü | Yalnız aday | Seviye 3 adayı, ölçülmeden önerilmez |
| Wiktionary örnekleri | anlam başına | iyi, ama az | Anlam başına örnek | **Seviye 1** (kaikki yeniden çıkarımıyla) |
| **PARSEME 1.3 EN** | Fiil MWE, elle etiket | yüksek | Phrasal verb/deyim tespitini ölçmek | **Değerlendirme** (EN; TR NC olduğu için yalnız iç ölçüm) |
| **MAGPIE** | 1.727 deyim türü (uzlaşma 1,0) | kalabalık + uzman etiketi | Deyim/düz kullanım ölçümü | **Değerlendirme** (yerel, BNC metni dağıtılmaz) |
| Project Gutenberg, Wikisource TR | kamu malı | edebî, eski dil | Örnek cümle havuzu (zaten kütüphanede) | **Seviye 1** (örnek kaynağı) |
| Açık öğrenici derlemleri | — | — | Açık lisanslı, ticari kullanıma uygun bir EN öğrenici derlemi doğrulanamadı (EFCAMDAT, ICNALE vb. araştırma şartlı ≈) | Doğrulanmadan önerilmez |

## 4. Sıklık ve bağlamsal anlam

| Kaynak | Kapsam | Ölçülen | Karar |
|---|---|---|---|
| **wordfreq 3.1.1** | 40+ dil, EN/TR ✅ | EN ilk 30.000 kelimenin 3.706'sı dict.db'de hiçbir biçimde yok (çoğu özel ad; QUALITY_BENCHMARK §3) | **Seviye 1** – `wfreq`'in (Tatoeba sayımı, "tom" 1.) yerine sıralama; atıf + SA |
| SUBTLEX-US/UK | EN | – | Doğrudan değil (NC-ND); wordfreq içinden gelir |
| Sentence Transformers (`paraphrase-multilingual-MiniLM-L12-v2`) | 50+ dil | #106: 0,596 → 0,636 (99 cümle, Claude etiketi, ayar aynı kümede) | **Seviye 2** – geliştirici hattında öneri |
| LaBSE / multilingual-e5 / BGE-M3 | çok dilli | Ölçülmedi | Seviye 2 alternatifleri; boyut ve fayda ölçülmeden eklenmez |
| SemCor 3.0 | EN, insan etiketli WordNet anlamı | Bu çalışmada yeni bağımsız küme (340 satır) | **Değerlendirme** |
| WSD Unified Framework (Senseval/SemEval) | EN | Erişilemedi | Seviye 2 değerlendirme adayı |

## 5. Neden bu kombinasyon (kısa)

- **OEWN 2025 + KeNet + Wiktionary (anlam bağlantılı)**: üç farklı köken (Princeton/OEWN editörleri, Türk
  akademik ekip, Wiktionary gönüllüleri). Doğrulama katmanı için gereken "birbirinden bağımsız tanık" ilkesini
  ücretsiz ve ticari uyumlu biçimde yalnız bu üçlü sağlıyor. BabelNet daha geniş ama lisansı uygun değil;
  ConceptNet/DBnary/OMW-wikt ise Wiktionary'nin kopyası.
- **wordfreq**: tek komutla EN ve TR için tutarlı Zipf ölçeği; Tatoeba sayımından kaynaklanan isim yanlılığını
  ortadan kaldırır. Veri donmuş olsa da sıralama için yeterli.
- **spaCy + Zemberek (yalnız geliştirici hattı)**: kök ve özel ad hataları ölçüldü; uygulamaya paketlenmeleri
  gerekmiyor çünkü üretilen sonuç (lemma, tür) sözlüğe doğrulanmış veri olarak girer.
- **UD (EWT, BOUN, Kenet, Penn), SemCor, MAGPIE, PARSEME EN**: insan etiketli, bağımsız ölçüm; uygulamaya girmez.
