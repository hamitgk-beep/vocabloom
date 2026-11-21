# Sözlük aday altyapısı (`tools/lexicon`)

Kitaplardan ve izinli kaynaklardan **kelime, anlam, phrasal verb, deyim ve örnek cümle adayları** çıkaran,
bunları mevcut iki sözlükle **salt okunur** karşılaştıran ve ayrı bir aday veritabanında saklayan geliştirici
aracı. Uygulamanın bir parçası değildir: Flutter kodu, `assets/` ve kullanıcı verisi değişmez, çevrimdışı
çalışma etkilenmez.

Lisans değerlendirmesi: [LICENSE_REPORT.md](LICENSE_REPORT.md).

## Güvenlik kuralları (kodla zorlanır)

| Kural | Nerede |
|---|---|
| `assets/dict.db` ve `assets/tr_en.db` yalnız `mode=ro` + `query_only` ile açılır, yazma denemesi hata verir | `safety.open_readonly` |
| Aday veritabanı ve dışa aktarım `assets/` içine ya da `dict.db`/`tr_en.db` adlı bir dosyaya yazılamaz | `safety.check_writable_target` |
| Her aday `unverified` başlar. Bir boru hattı `accepted`/`rejected` koyamaz | `store.add_candidate` |
| Kabul/ret yalnız isimli bir gözden geçirenle yapılır ve `review_log`'a yazılır (şema da zorlar) | `store.review` + `CHECK` |
| Kullanıcının kendi kitabı (`user_book`) her zaman `private_only`, adayları `private` | `licenses.classify` + `CHECK` |
| İzinsiz kaynaktan gelen aday SQL ile bile `shared` yapılamaz | tetikleyiciler |
| Dışa aktarım yalnız `accepted` + `shared` + izni `allowed` olan adayları alır | `store.export_reviewed_shared` |
| Dışa aktarım bir JSONL dosyasıdır, hiçbir sözlüğü değiştirmez | – |

## Veri yapısı (`build/lexicon/candidates.db`, git'e girmez)

**source**: her kaynak bir kez kaydedilir. Alanlar ayrı ayrı tutulur:
- `kind`: `public_domain_text`, `open_license_text`, `user_book`, `manual`
- `licence`: normalleştirilmiş lisans (`public-domain`, `cc-by-4.0`, `cc-by-sa-4.0`, `unknown` ...)
- `permission` (kullanım izni): `allowed` · `needs_approval` (SA/GPL/NC) · `unknown` · `private_only` (kullanıcı kitabı)
- `shareable`: 1 yalnız `permission = allowed` ise
- `licence_note`, `licence_url`, `lang` (`en`/`tr`)

**candidate**: bir aday
- `kind`: `word`, `sense`, `phrasal_verb`, `idiom`, `collocation`, `example`
- `direction`: `en-tr` (dict.db için) veya `tr-en` (tr_en.db için); kaynak dili ile uyuşmak zorunda
- `headword`, `lemma`, `pos`, `translation`, `definition`, `example`, `example_translation`
- kaynak: `source_id`, `locator` (dosya#cümle), adayın oluştuğu andaki `licence` ve `permission` kopyası
- `scope`: `shared` / `private`
- `engine` (ör. `builtin-en@1`, `spacy-en@3.8.20/en_core_web_sm-3.8.0`), `confidence` (0–1)
- `compare_result`: `new_headword`, `known_headword`, `known_form`, `known_sense`, `possible_new_sense`,
  `new_phrase`, `known_phrase`; `compare_detail` (JSON, ör. bulunan lemma)
- `status`: `unverified` → `needs_review` → `accepted` / `rejected`; `reviewer`, `review_note`
- `occurrences`: aynı aday aynı kaynakta kaç kez görüldü

**review_log**: her durum değişikliği (eski, yeni, kim, not, zaman).

## Adaptörler

İngilizce ve Türkçe birbirinden bağımsızdır. Her dilin kendi temel sınıfı vardır, biri diğerini içe aktarmaz.

| Dil | Adaptör | Bağımlılık | Not |
|---|---|---|---|
| İngilizce | `builtin` | yok | Düzensiz biçimler `dict.db/exc`, ekler kural + sözlük denetimi. Phrasal verb yalnız fiil + edat cümle sonundaysa ya da zaten biliniyorsa |
| İngilizce | `spacy` | spaCy + en_core_web_sm (MIT) | Ayrık phrasal verb'leri de bulur ("took it off"). Yanlış lemmada yerleşik kurallara düşer |
| Türkçe | `builtin` | yok | Çekimli biçim → lemma `tr_en.db/form` ile. Kesme işaretli ve cümle içi büyük harfli sözcükler özel ad sayılır |
| Türkçe | Zemberek | – | Planlandı (Apache-2.0, Java). Aynı `TurkishAnalyzer` arayüzünü uygulayacak |

## Kullanım (depo kökünden)

```bash
python3 tools/lexicon/run.py add-source --name gutenberg-11 --kind public_domain_text --licence "Public domain" --lang en
python3 tools/lexicon/run.py add-source --name benim-kitabim --kind user_book --lang en      # her zaman özel
python3 tools/lexicon/run.py extract --source gutenberg-11 --text alice.txt                 # --engine spacy
python3 tools/lexicon/run.py add-source --name elle --kind manual --licence Storilex --lang en
python3 tools/lexicon/run.py add-sense --source elle --headword run --translation "işletmek" --pos verb
python3 tools/lexicon/run.py summary
python3 tools/lexicon/run.py review --id 12 --status accepted --reviewer Hamit
python3 tools/lexicon/run.py export --out build/lexicon/reviewed.jsonl
```

`add-sense` mevcut bir kelimeye **yeni anlam adayı** ekler. Karşılaştırma, anlam sözlükte varsa `known_sense`,
yoksa `possible_new_sense` yazar. Çeviriler otomatik üretilmez.

## Testler

```bash
python3 -m unittest discover -s tools/lexicon/tests -t tools
```

Testler küçük, sentetik `dict.db`/`tr_en.db` kopyalarıyla çalışır. `RealAssetsTests` gerçek dosyalar varsa onları
salt okunur açar ve SHA-256 ile değişiklik zamanının aynı kaldığını denetler. spaCy kurulu değilse spaCy testi atlanır.

## Bilinen sınırlar

- Yerleşik İngilizce adaptör cümle başındaki özel adları (ör. "Dinah") yeni kelime sanabilir. spaCy bunları ayırır.
- Yerleşik Türkçe adaptör `tr_en.db`'de olmayan çekimli biçimleri lemmaya indiremez. Bunlar `lemma` boş ve düşük
  güvenle (`0.2`) kaydedilir.
- Deyim çıkarımı henüz yok. Deyim ve eşdizim adayları şimdilik `add-sense --kind idiom` ile elle eklenir.
