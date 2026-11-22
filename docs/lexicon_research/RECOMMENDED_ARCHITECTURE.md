# Önerilen profesyonel güvenilirlik mimarisi (Görev 5A, Aşama 5 ve 6)

İlke: **mevcut çalışan sistemi yeniden yazmadan**, hatalı bilginin kullanıcıya ulaşmasını engelleyen katmanları
uygulamanın **dışında** (geliştirici hattında, PR #99'un `candidates.db` modeli üzerinde) kurmak; uygulamaya yalnız
sonuç (doğrulanmış/olası/çelişkili etiketiyle) girsin. Uygulamadaki `SourceTier`, `sourcePolicy`, `SenseEngine.fit`
ve kimlik biçimleri korunur.

```
 A Kaynak ─► B Dil analizi ─► C Anlam doğrulama ─► D Bağlam ─► E Güven ─► F İnsan incelemesi ─► G Yayın
 (sources,    (spaCy/Zemberek,  (tanık grupları,     (SenseEngine   (verified/ (karar, gerekçe,  (lisans+kalite
  sürüm,       UD ölçümü)        kopya tespiti)       + kalibrasyon) probable/  kanıt)            kapısı, sürüm)
  lisans)                                                            conflict/
                                                                     rejected)
```

## A. Kaynak katmanı (izlenebilirlik)

PR #99'un `source` ve `source_approval` tabloları temel alınır; eklenecek alanlar:

| Tablo | Alanlar |
|---|---|
| `source` | `id`, `name`, `version` (ör. `oewn-2025`, `kaikki-2026-11-01`), `url`, `sha256`, `license_spdx`, `license_evidence` (dosya/URL + okuma tarihi), `commercial_ok`, `share_alike`, `attribution`, **`lineage`** (hangi kaynaktan türedi: `wiktionary`, `princeton-wn`, `kenet`, `human:hamit`, `ai:<model>`) |
| `item` | `id`, `kind` (word/sense/expr/example/form), `lang`, `headword`, `pos`, `payload` (JSON), `source_id`, `source_key` (kaynaktaki kimlik: synset id, sayfa adı, Tatoeba cümle no), `item_license` (Tatoeba gibi satır başına lisans) |
| `link` | `item_id`, `target` (`wn:<id>`, `ex:<phrase>|<cat>#i`, `ow:<word>#i`, `ft:<word>#i`) — **uygulamanın kimlik biçimleriyle aynı** |

`lineage` alanı C katmanının temelidir. Bugünkü `ft` kaynak etiketi taşımadığı için ilk iş, `tools/main_meanings.py`
çıktısının hangi satırının Wiktionary, hangisinin damdafayton olduğunu `item.source_id` ile ayırmaktır (dict.db'ye
dokunmadan, yeniden üretimle).

## B. Dil analizi katmanı

- İngilizce: uygulamadaki `baseForms` + geliştirici hattında spaCy (PR #104). Yeni kural önerisi (ölçülmüş hata):
  "-er/-or" isimleri (customer, owner, buffer, opener) sözlükte kendi maddesi varsa asla köke indirilmez; ortaç sıfatlar
  (worried, interested, willing) sıfat girdisi varsa önce sıfat okunur.
- Türkçe: `TrEnDict.lemmas` + geliştirici hattında Zemberek (PR #104). Zemberek ile uygulama arasındaki farklar
  (`%10,6` köksüz, `%22` ilk kök yanlış/ikinci) aday listesi olarak `candidates.db`'ye yazılır; uygulamaya form tablosu
  satırı olarak ancak F katmanından geçerek girer.
- Çok kelimeli ifade: `PhraseMatcher` + `isLiteral`; PARSEME EN (CC BY 4.0) ve MAGPIE ile ölçülür.
- Bu katman **veri üretmez, önerir**; her önerinin `source_id`'si "analyzer:spacy-3.8.18" gibi bir kaynaktır.

## C. Anlam doğrulama katmanı (bağımsız tanıklar)

Her (kelime, tür, Türkçe karşılık) üçlüsü için tanıklar toplanır. **Tanıklar `lineage` grubuna göre sayılır**:

| Tanık grubu | Örnek kaynaklar | Bağımsız mı? |
|---|---|---|
| `wiktionary` | Wiktionary EN çevirileri, TR Vikisözlük, kaikki, DBnary, ConceptNet-TR, OMW-wikt, Kindle derlemesinin Wiktionary kısmı | Hepsi **tek tanık** |
| `kenet` | KeNet synset Türkçesi | Ayrı tanık |
| `princeton-wn` | OEWN/PWN tanım + eş anlamlılar (Türkçe vermez; tür ve anlam ayrımı tanığı) | Ayrı tanık (tür/anlam için) |
| `freedict` | FreeDict eng-tur, Kindle derlemesinin FreeDict kısmı | Ayrı tanık, düşük ağırlık |
| `tatoeba` | Hizalı insan çevirisi cümlede kelimenin karşılığı | Ayrı tanık (kullanım kanıtı) |
| `human` | Hamit'in katkısı, inceleme kararı | En yüksek |
| `ai:*` | own_word taslakları, exd, gömme benzerliği, OPUS-MT | **Asla tek başına tanık değil**; yalnız aday üretir |

Kurallar:
1. İki kaynak aynı `lineage` grubundaysa uyuşmaları **bir** tanık sayılır (ör. kaikki + DBnary).
2. AI taslağı ile `ft` aynı Türkçeyi veriyorsa bu bir doğrulama sayılmaz, çünkü taslaklar `ft`'yi gördükten sonra
   üretilmiş olabilir (kopya riski). Bugün `SenseEngine._decide` taslağı `ft` ile "doğrulanmış" sayıyor; ölçümde
   isim "stop" için fiil Türkçesi "durmak" bu yoldan "kesin" oldu. Öneri: doğrulayan kaynak **aynı sözcük türünü**
   taşımalı ve AI dışı bir grupta olmalı.
3. Uyuşmazlık tespiti: aynı (kelime, tür) için iki bağımsız grubun Türkçeleri ortak kelime ve KeNet eş anlam
   kümesiyle (`DictDb.sameTr` mantığı) eşleşmiyorsa `conflict` adayı. Ölçülen ölçek: ft↔taslak 19.189 kelime,
   ft↔KeNet ≈3.480 kelime; önce sık kelimelerden (wordfreq Zipf ≥ 4) başlanır.
4. Tür tutarlılığı: Türkçe karşılığın biçimi (fiil "-mak/-mek") ile anlamın türü (`DictDb.isTrVerb`) çelişiyorsa
   otomatik `conflict`.

## D. Bağlam katmanı (SenseEngine ile uyumlu)

SenseEngine yeniden yazılmaz. Üç küçük değişiklik önerilir, her biri hold-out kümelerle ölçülüp kabul edilir:

1. **Taban kuralı**: Bağlam kanıtı zayıfken ilk WordNet anlamından ayrılma. Ölçüm: WordNet anlamı gösterilen
   "kesin" satırlarda seçici %54,9, ilk anlam %73,9. Kabul ölçütü: SemCor hold-out'ta İngilizce anlam doğruluğu
   tabanın altına düşmez ve Türkçe katı doğruluk düşmez.
2. **"Kesin" kalibrasyonu**: `sure` yalnız (a) bağımsız bir tanıkla doğrulanmış Türkçe ve (b) bağlam farkı ≥ eşik
   olduğunda. Eşik, SemCor *dev* kümesinde "kesin" iken yanlış oranı ≤ %5 olacak şekilde seçilir; hold-out'ta bir kez
   ölçülür. Bugün: İngilizce anlamda kesin-yanlış %30,3 (tüm satırlar), Türkçede %11,2 (kesinler), türde %14,8.
3. **Özel ad koruması**: Cümle ortasında büyük harfle başlayan ve sözlükte "name" ya da OEWN Namenet'te olan
   kelimeler için kelime anlamı en fazla `likely` (EWT'de özel adların %49,9'u "kesin").
4. **İfadeler**: deyim kararı `sure` değilse altı çizili gösterim korunur ama anlam kartı "deyim olabilir" der (MAGPIE:
   düz cümlelerin %56,7'si deyim sanılıyor).

## E. Güven katmanı (sınıflar)

| Sınıf | Koşul | Uygulamada |
|---|---|---|
| `verified` | İnsan kararı (F) **veya** ≥ 2 bağımsız grup + tür tutarlı + lisans uygun | Normal gösterim; tekrar kartı notlar |
| `probable` | 1 güvenilir grup (wiktionary/kenet/freedict), çelişki yok | Normal gösterim, "kesin" etiketi yalnız D-2 ile |
| `conflict` | Bağımsız gruplar uyuşmuyor veya tür çelişkisi | "Anlamlar farklı kaynaklarda farklı" notu; kart notlamaz |
| `draft` | Yalnız AI | Bugünkü gibi kapalı, etiketli bölüm |
| `rejected` | İnsan reddi veya lisans uygun değil | Gösterilmez, silinmez (kayıt kalır) |

Uygulama tarafı eşlemesi: `verified`→`SourceTier.verified`, `probable`→`trusted`, `draft`→`draft`. `conflict` için
`SourceTier`'a yeni değer eklemek yerine `trusted` + bir `conflict` bayrağı (ayrı tablo `qa_flag(word, pos, kind)`)
önerilir; böylece mevcut sıralama ve önbellek anahtarı (`policyVersion` artırılarak) bozulmaz.

## F. İnsan inceleme katmanı

- Kuyruk önceliği: `etki = kelime sıklığı (Zipf) × gösterilme yeri (ana anlam > diğer) × sınıf (conflict > draft)`.
  Bugünkü 41.177 taslak satırının tamamı yerine en sık ≈3.000 kelimenin çelişkili olanları önce gelir.
- Karar kaydı (yalnız eklenebilir, PR #99 günlük modeli): `review(id, item_id, reviewer, decision
  [accept|edit|reject|split], new_payload, reason, evidence_sources[], created_at)`. Mevcut Excel katkı akışı
  (`tools/contrib/*.xlsx` → `verified_senses.py` → `contrib_verified.dart`) bu tablonun ilk üreticisi olur.
- Claude veya başka bir model "inceleyen" olamaz; yalnız öneri ve gerekçe taslağı yazar (`reviewer` alanı insan adı).

## G. Yayın katmanı

`export` (PR #99'da var) şu kapıları sırayla uygular; biri başarısızsa yayın paketi oluşmaz:
1. Lisans kapısı: her satırın `source.commercial_ok = 1`, NC/ND yok; SA kaynaklar için çıktı CC BY-SA 4.0; GPL
   kaynaklı satırlar ayrı dosya (LICENSE_MATRIX §5 kararı verilene kadar).
2. Kalite kapısı: `tools/qa/audit_dict.py` taban çizgisi + yeni kontroller (tür–Türkçe biçim çelişkisi, bozuk
   belirteç, özel ad, yinelenen anlam) artmamalı.
3. Ölçüm kapısı: hold-out kümelerinde (QUALITY_BENCHMARK §1) "kesin-yanlış" oranları artmamalı.
4. Sürüm: `dict.db` yeniden üretilir, `DictDb.version` artırılır, değişen kayıt sayıları ve SHA-256 sürüm notuna
   yazılır; `main`'e birleşme yayın çıkarmaz (#109), yayın ayrı onaydır.

## Aşama 6: üç seviye teknoloji seçimi

### Seviye 1 — Temel ve güvenilir (ücretsiz, hafif, çevrimdışı)
| Teknoloji | Neden | Neden alternatifinden iyi | Ölçülen/beklenen kazanım |
|---|---|---|---|
| **Open English WordNet 2025** | WN 3.0'ın bakımı süren, CC BY 4.0 hâli | PWN 2006'dan beri durgun; BabelNet NC | 4.211 yeni lemma; düzeltilmiş anlamlar (sayı ölçülmedi) |
| **Wiktionary/kaikki, anlam bağlantılı yeniden çıkarım** | Çeviri tablosunun anlam başlığını (`sense`) tutar | damdafayton kökeni belirsiz; DBnary aynı içerik | damdafayton'a bağımlılık biter; anlam–çeviri eşleşmesi |
| **KeNet** (bağımsız tanık olarak) | Elle yapılmış, Wiktionary'den bağımsız | OMW'de Türkçe yok | C katmanının ikinci tanığı |
| **wordfreq** | Tutarlı EN/TR Zipf | `wfreq` Tatoeba'dan ("tom" 1.) | Sıralama ve inceleme önceliği |
| **Tatoeba + satır lisansı** | İnsan çevirisi örnekler | OpenSubtitles lisanssız | Örnek cümlede lisans izlenebilirliği |
| **Yerleşik kurallar** (+ ölçülen hata düzeltmeleri) | Uygulama içinde, 0 MB ek | — | EN kök %95,6 → hedef ≥ %96,5 |

### Seviye 2 — Gelişmiş doğrulama (yalnız geliştirici hattı)
| Teknoloji | Neden | Kazanım |
|---|---|---|
| spaCy 3.8 + en_core_web_sm (MIT) | Kök, tür, özel ad, ayrık phrasal verb | #104: özel ad sızıntısı 0,059 → 0 (Claude etiketi) |
| Zemberek 0.18 (Apache-2.0) | Türkçe çözümleme | Türkçe köksüz %10,6'yı azaltma adayı |
| Tanık grupları + çelişki raporu (C) | Yanlış anlamı yayından önce yakalar | 19.189 ft↔taslak, ≈3.480 ft↔KeNet aday |
| Sentence Transformers (MiniLM, Apache-2.0) | Örnek cümle ↔ anlam eşleştirme önerisi | #106: 0,596 → 0,636 (Claude etiketi) |
| Hold-out kümeleri (SemCor, EWT, UD-TR, MAGPIE, PARSEME EN) | Bağımsız kalite ölçümü | Her değişikliğin kanıtı |

### Seviye 3 — Profesyonel sözlük üretimi
| Bileşen | İçerik |
|---|---|
| İnsan inceleme kuyruğu (F) | Etki sıralı, karar + gerekçe + kanıt kaydı |
| Kaynak izlenebilirliği (A) | Her satırda kaynak, sürüm, lisans, köken |
| Otomatik kalite raporu | `audit_dict.py` + hold-out ölçümleri CI'da, eğilim tablosu |
| Sürümlenmiş sözlük | Kaynak sürümleri sabit (SHA-256), yeniden üretilebilir derleme |
| Kontrollü yayın (G) | Lisans/kalite/ölçüm kapıları + ayrı yayın onayı |

Bilerek önerilmeyenler: BabelNet (NC), PanLex (lisans çelişkisi), UDPipe modelleri (NC), Stanza/TurkicNLP (NC eğitim
verisi, ek katkı küçük), LanguageTool (Türkçe yok), ConceptNet/DBnary/OMW-wikt (Wiktionary kopyası), OpenSubtitles
ve NLLB örnek cümleleri (lisans belirsiz), büyük gömme modellerini uygulamaya paketlemek (ölçülmüş fayda yok).
