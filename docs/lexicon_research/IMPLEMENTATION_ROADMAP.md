# Uygulama planı (Görev 5A, Aşama 7)

Öncelik: **kullanıcıya verilen yanlış bilgiyi azaltmak** > lisans riskini kapatmak > kapsamı artırmak.
Hiçbir aşama onaysız başlamaz. Ana sözlüklere yazan her adım ayrı onay ister (CLAUDE.md §4) ve önce kopyada çalışır.

## Aşama 0 — Ölçüm temeli (yaklaşık 1 iş günü)
- **İş:** Bu çalışmadaki hold-out kümelerini sabitle: `docs/lexicon_research/scripts/` → `tools/eval/` altına taşı;
  EWT metin kümesi için `build_text_eval.py`'ye `--treebank ewt` seçeneği; SemCor hold-out'u `test/data/`'ya (SemCor
  dağıtılabilir) ekle. MAGPIE/BNC yerel kalır.
- **Kaynak:** SemCor, UD EWT/BOUN/Kenet/Penn, MAGPIE, (yeni) PARSEME 1.3 EN.
- **Kazanım:** Her sonraki değişiklik bağımsız sayıyla kabul edilir.
- **Bağımlılık:** yok (Flutter test + Python standart kütüphane; nltk yalnız küme üretirken).
- **Lisans riski:** düşük (EWT, BOUN… CC BY-SA yalnız test verisi; PARSEME TR NC → yalnız yerel).
- **Performans:** yok (uygulama değişmez).
- **Kabul:** Kümeler sabit tohumla yeniden üretilir ve SHA-256 eşleşir; testler sayı basar, eşik koymaz.
- **PR ilişkisi:** #99/#104/#106'nın `eval/` klasörüyle birleştirilebilir; onların Claude etiketli kümeleri "dev",
  bu kümeler "hold-out" olarak ayrılır.

## Aşama 1 — Yanlış "kesin" bilgiyi azalt (uygulama, küçük değişiklikler; 2–3 iş günü)
- **İş:**
  1. Taslak + ft "doğrulamasında" aynı sözcük türü şartı (isim "stop" → "durmak" olmamalı).
  2. "Kesin" eşiğini dev kümesinde kalibre et (hedef: kesin-yanlış ≤ %5, Türkçe düzeyinde).
  3. Zayıf bağlamda ilk WordNet anlamına dön (taban kuralı).
  4. Özel ad koruması (cümle ortası büyük harf + "name"/Namenet → en fazla `likely`).
  5. Kök kuralları: "-er/-or" isimleri ve ortaç sıfatlar (customer, owner, willing, interested).
- **Kaynak:** mevcut dict.db (değişmez), SemCor dev/hold-out, EWT.
- **Kazanım (hedef, ölçülecek):** SemCor İngilizce anlam doğruluğu ≥ %70 (bugün WordNet satırlarında %45,7);
  Türkçe "kesin" yanlış %11,2 → ≤ %5; EWT "kesin" tür yanlışı %14,8 → ≤ %7; özel adların "kesin" oranı %49,9 → < %10.
  Kapsamanın düşmesi beklenir; kapsama ve doğruluk birlikte raporlanır.
- **Bağımlılık:** yok.
- **Lisans riski:** yok.
- **Performans:** önemsiz (aynı sorgular).
- **Test/kabul:** `context_sense_test`, `source_priority_test`, `review_quiz_test`, `sense_eval_test` yeşil; hold-out bir
  kez ölçülür; `SenseEngine.version` ve gerekirse `policyVersion` artırılır.
- **PR ilişkisi:** bağımsız; #99/#104/#106 araç dalları, bu ise `lib/nlp/` değişikliği. Ayrı PR.

## Aşama 2 — Kaynak izlenebilirliği ve lisans temizliği (3–5 iş günü)
- **İş:**
  1. `ft`'nin her anlamına kaynak etiketi: `tools/main_meanings.py`'yi Wiktionary ve damdafayton satırlarını ayırarak
     yeniden çalıştır; **ayrı bir kopyada** kaç anlamın yalnız damdafayton'dan geldiğini say (sayı raporlanır,
     dict.db değişmez).
  2. `tr_en.db` `meta.sources`'a FreeDict ve WordNet tersini ekleme önerisi; "fd" anlamlarının lisans kararı.
  3. Tatoeba cümle lisansı alanı (içe alımda).
  4. PR #99 `source` tablosuna `lineage`, `license_evidence`, `item_license` alanları.
- **Kaynak:** kaikki (yeniden indirme, sabit tarih + SHA-256), FreeDict, Tatoeba dökümü.
- **Kazanım:** Lisans riskleri (LICENSE_MATRIX §5 madde 1–6) ölçülür ve karara bağlanır.
- **Bağımlılık:** yok (Python standart kütüphane).
- **Lisans riski:** Bu aşamanın amacı riski azaltmak; damdafayton çıkarılırsa kapsam kaybı ölçülüp raporlanır.
- **Performans:** yok.
- **Kabul:** Her `ft` anlamının kaynağı bilinir; damdafayton'a bağlı anlam sayısı raporlanır; Hamit karar verir.
- **PR ilişkisi:** #99'un şemasını genişletir → #99'un üstüne kurulmalı (ya da #99 birleştikten sonra).

## Aşama 3 — Bağımsız tanıklarla anlam doğrulama ve çelişki raporu (4–6 iş günü)
- **İş:** RECOMMENDED_ARCHITECTURE C ve E: tanık grupları, uyuşmazlık ve tür–biçim çelişki raporu
  (`candidates.db`'de; uygulamaya girmez). OEWN 2025 tür ve anlam tanığı olarak eklenir. Çıktı: sık kelimelerden
  başlayan `conflict` listesi (TSV + Excel, mevcut katkı akışına uygun).
- **Kaynak:** OEWN 2025, KeNet, Wiktionary (anlam bağlantılı), FreeDict, Tatoeba, wordfreq (sıra).
- **Kazanım:** Ölçülen aday havuzu: 19.189 ft↔taslak, ≈3.480 ft↔KeNet; tür çelişkileri (sayı ölçülecek).
- **Bağımlılık:** isteğe bağlı wordfreq (#106'da sabitlenmiş sürüm).
- **Lisans riski:** düşük (yalnız karşılaştırma; çıktı inceleme listesi).
- **Performans:** geliştirici makinesinde dakikalar.
- **Kabul:** Rastgele 100 `conflict` satırının en az %70'inin gerçekten incelemeye değer olduğu **insan** (Hamit)
  tarafından onaylanır; aksi hâlde kurallar gevşetilmez, değiştirilir.
- **PR ilişkisi:** #99 (depo), #104 (spaCy/Zemberek kök ve tür kanıtı), #106 (sıklık ve gömme önerisi) burada birleşir.

## Aşama 4 — İnsan inceleme döngüsü (sürekli)
- **İş:** `review` tablosu (yalnız eklenebilir), etki sıralı kuyruk, mevcut Excel katkı akışının bu tabloya yazması;
  kararların `contrib_verified.dart`'a dönüşmesi (bugünkü yol korunur).
- **Kazanım:** Doğrulanmış anlam sayısı (bugün 92 kelime + 689 ifade) artar; taslakların yerine geçen anlamlar
  izlenebilir olur.
- **Kabul:** Her kararın inceleyeni, gerekçesi ve kaynakları kayıtlı; AI "inceleyen" olarak geçmez.
- **PR ilişkisi:** #99 `source_approval` deseni.

## Aşama 5 — Yayın kapısı ve sürümlü sözlük (2–3 iş günü)
- **İş:** RECOMMENDED_ARCHITECTURE G: lisans + kalite + ölçüm kapıları `quality.yml`'ye; sürüm notuna kayıt sayısı
  farkları ve SHA-256.
- **Bağımlılık:** CI iş akışı değişikliği (ayrı onay; #109 yayın ayrımı korunur).
- **Kabul:** Kapılardan biri kırılınca yayın paketi oluşmaz; `main`'e birleşme yayın çıkarmaz.

## Aşama 6 — Kapsam (ikinci öncelik)
- **İş:** OEWN 2025'teki 4.211 yeni lemmadan sık olanlar, 14 eksik tür, 14 eksik sık phrasal verb, MAGPIE'de olup
  sözlükte olmayan 568 deyim, Türkçe köksüz biçimler (Zemberek önerisi + insan onayı). Hepsi önce `candidates.db`.
- **Kabul:** Yeni her kayıt en az `probable` sınıfında ve kaynak/lisans alanları dolu; hold-out ölçümleri kötüleşmez.
- **PR ilişkisi:** #104 `gaps` komutu bu listeyi üretir.

## Mevcut PR'larla ilişki özeti
| PR | Bu plandaki yeri | Öneri |
|---|---|---|
| #99 aday altyapısı | A, F, G katmanlarının temeli | Önce incelensin; şemaya `lineage`/`license_evidence` eklenerek |
| #104 spaCy + Zemberek | B katmanı, Aşama 3 ve 6 | #99'dan sonra; uygulamaya paket girmez |
| #106 wordfreq + gömmeler | C/D önerileri, inceleme önceliği | Ölçümü bu hold-out kümelerle tekrarlanmalı (Claude etiketli 99 cümle yerine) |

## Ne yapılmayacak
Ana sözlüklere otomatik yeni kelime/anlam yazmak, AI taslağını onaylı saymak, NC/ND veya lisansı belirsiz veri
almak, büyük modelleri uygulamaya paketlemek, PR'ları onaysız birleştirmek veya sürüm yayımlamak.
