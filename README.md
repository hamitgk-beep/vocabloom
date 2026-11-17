# VocaBloom

İngilizce kitapları okurken bilmediğin kelimeleri öğrenmen için çevrimdışı çalışan okuyucu.
Windows, macOS, Linux, Android ve iOS için tek kod tabanı (Flutter).

Geliştiren: Hamit Gök

## Neler yapar

- **Kitap ekleme:** EPUB, PDF (metinli), TXT, Markdown, HTML, DOCX, ODT, FB2, RTF. Kitap uygulamanın kendi
  formatına (bölüm → paragraf) dönüştürülüp cihazdaki SQLite veritabanına kaydedilir. PDF'lerde sayfa üst/alt
  bilgileri ve sayfa numaraları atılır, resim altı yazıları paragrafı bölmeden ayrı (italik) gösterilir, bölümler
  içindekiler sayfasından bulunur. `test/import_completeness_test.dart` her biçimde metnin eksiksiz ve sırasıyla
  geldiğini denetler. Kitaplık menüsündeki "Metni kaydet (.txt)" / "Metni kopyala" ve okuyucudaki kopyala düğmesi
  kitabın uygulamadaki halini dışarı verir.
- **Kelimeye dokun:** Türkçe karşılıklar, İngilizce tanımlar (WordNet), eş anlamlılar, örnek cümleler,
  kitabın başka yerlerinden örnekler ve "bu cümlede büyük olasılıkla şu anlamda" tahmini. Kelime bir kalıbın
  parçasıysa (give up, break the ice …) kalıp en üstte gösterilir. Türkçe/English düğmeleriyle tek dile geçilebilir.
- **Uzun bas (cümle analizi):** cümledeki zamanlar ve fiil yapıları (Present Perfect, edilgen, koşul …),
  bağlaçlar, phrasal verb'ler, deyimler ve diğer kalıplar, kelime kelime anlamlar.
- **Öğrenme listesi:** "Öğreneceğim" → kitabın her yerinde turuncu; "Öğrendim" → yeşil. Çekimli biçimler de
  işaretlenir (run → ran, running).
- **Filtreler:** Conjunctions, Phrasal Verbs, Collocations, Prepositional Phrases, Proverbs & Sayings,
  Discourse Markers / Fillers, Idioms, Chunks, Binomials, False Friends, Modal Verbs, Irregular Verbs.
  Seçilen her tür kitapta kendi rengiyle altı çizili görünür.
- **Gramer filtreleri:** Zamanlar (her fiil zamanına göre renklenir: yeşil şimdiki/geniş, kahverengi geçmiş, mavi gelecek),
  Koşul cümleleri (0, 1, 2, 3. tip, karışık, devrik), Relative clauses, Gerund / Infinitive, Comparative / Superlative,
  Reported speech, Edilgen (passive), Geçmiş modallar (should have done …), Used to / be used to, Causative
  (have something done, make someone do), Vurgu (devrik "Never have I …", "It was … who", "What I need is …"),
  Tag questions, Ortaçlar (Walking home, I …; Having finished, …; the man standing there; bored / boring). Renkli kelimeye dokununca yapının adı, bu cümledeki hali, kuralı ve ilgili Gramer konusuna bağlantı
  çıkar. Tespit çevrimdışı ve kurallarla yapılır (`lib/nlp/grammar_marks.dart`); emin olunmayan yer işaretlenmez
  (ör. "was tired" edilgen sayılmaz, "asked if" koşul sayılmaz). `test/grammar_marks_test.dart` doğru ve yanlış örnekleri denetler.
  Filtreler menüsü üç açılır gruptan oluşur: Kalıplar ve deyimler, Gramer yapıları, Kelime türleri.
- **Sözlük sekmesi:** yalnızca kelimeler. Yazdıkça eşleşen kelimeler Türkçe anlamlarıyla listelenir, dokununca
  okuyucudaki kelime paneli açılır; son bakılan kelimeler saklanır.
- **Gramer:** 68 konu, A1–C2. Filtrelerdeki 12 ifade türünün (phrasal verb, deyim, eşdizim, bağlaç …) her biri
  bir gramer konusudur: anlatım, yapı, örnekler, 28 alıştırma, sık geçen ifadeler ve sözlükteki tam liste.
  Bu konular `tools/grammar/phrases/` altında yazılır, `python3 tools/grammar/add_phrase_lessons.py` ile
  `assets/grammar/lessons*.json`'a eklenir.
- **Doğal sesli okuma (çevrimdışı):** kelimenin telaffuzu (hoparlör düğmesi), cümleyi normal veya yavaş dinleme,
  kitabı baştan sona sesli okuma (okunan cümle/parça vurgulanır, sayfa kendiliğinden kayar). İngilizce: Kokoro-82M
  (12 doğal ses, kadın/erkek, ABD/İngiliz aksanı) ve yavaş telefonlar için hafif Piper LibriTTS-R sesi; uygulama
  telefonun hızını ölçüp hangisini kullanacağını kendisi seçer, dinlenen kelimeleri saklar).
  Türkçe anlam ve çeviriler: EMA Lightning (doğal kadın sesi), isteyene Piper Fahrettin (erkek). Tüm ses paketleri uygulama kurulunca
  veya güncellenince kendiliğinden bir kez indirilir (toplam ~530 MB: önce hafif İngilizce ve Türkçe sesler, en son doğal
  İngilizce ses), sonra internetsiz çalışır. Ayarlar'dan silinen paket bir daha kendiliğinden inmez.
  Paketler `tools/build_voice_packs.sh` ile hazırlanır ve "voice-models" iş akışı ile yayınlanır.
- **İsteğe bağlı çevrimiçi analiz:** Ayarlar'a bir yapay zekâ servisinin (Anthropic, OpenAI, Gemini vb.) API anahtarı girilirse kitap eklenirken (internet varsa)
  her cümlenin Türkçe çevirisi ve her bölümün özeti çıkarılıp cihaza kaydedilir; sonra internetsiz görünür.
  Sözlükte yalnızca İngilizce açıklaması olan kalıplar da (önce kitaplarında geçenler) Türkçeye çevrilip kaydedilir.

## Arayüz dili

Ayarlar > Uygulama dili ile tüm menüler, düğmeler, açıklamalar, hata mesajları ve Flutter'ın kendi metinleri
(geri, kopyala/yapıştır …) Türkçe ya da İngilizce olur. Her metin `L('Türkçe', 'English')` ile yazılır.
Gramer konularının İngilizce açıklamaları `assets/grammar/lessons_en.json` dosyasındadır. Öğrenme içeriği
(İngilizce örnek cümleler, kitap metni, Türkçe çeviri alıştırmaları) her iki dilde de olduğu gibi kalır.

## Geliştirme

```bash
python3 tools/build_dict.py <ham_veri_klasörü> assets/dict.db   # sözlüğü yeniden üret
python3 tools/main_meanings.py apply assets/dict.db             # yalnızca kelime anlamlarını yeniden uygula
flutter test                              # birim testleri + kaynakta sabit metin denetimi (test/l10n_test.dart)
                                          # PDF testleri için PDFIUM_PATH=/yol/libpdfium.so gerekir
python3 tools/make_import_fixtures.py     # içe aktarma test kitaplarını (test/fixtures/import) yeniden üret
flutter test qa_test/language_test.dart   # her ekranı Türkçe ve İngilizce açar, yanlış dilde metin arar, ekran görüntüsü alır
flutter run -d windows   # veya linux, macos, android cihaz
```

Ham veri dosyaları: `eng-tur.tei` (FreeDict), `wordnet/` (WordNet 3.0, nltk_data), `kenet.xml` (KeNet),
`ili-map-pwn30.tab` (CILI), `wiktionary_phrases.json.gz` (`data-wiktionary` sürümünden; GitHub'da
"wiktionary-data" iş akışı ile yeniden üretilir). `.github/workflows/build.yml` GitHub'da Windows, Android, Linux ve macOS
sürümlerini otomatik derler.

## Lisanslar

VocaBloom'un kaynak kodu GPL-3.0 lisanslıdır (`LICENSE`). eSpeak NG (GPL-3.0) uygulamayla birlikte dağıtıldığı için
bu gereklidir; uygulama Play Store'da reklamlı/ücretli olsa da kaynak kodu bu depoda açık kalmalıdır.
Sözlük veritabanı (`assets/dict.db`) aşağıdaki CC BY-SA kaynaklardan uyarlandığı için CC BY-SA 4.0 ile paylaşılır.
Uygulamada Ayarlar > Gizlilik ve lisanslar bütün kaynakları ve kütüphane lisanslarını gösterir.

- Kelime anlamları (`tools/data/main_meanings.jsonl.gz`, `tools/main_meanings.py`): Wiktionary çevirileri
  (kaikki.org üzerinden, Murat Uysal'ın Kindle İngilizce–Türkçe sözlüğü derlemesinin yalnızca Wiktionary kısmı:
  github.com/mybottles/kindle-en-tr-dictionary): CC BY-SA 4.0 / GFDL. Yardımcı kaynak:
  damdafayton/eng-tur-dictionary (README'ye göre MIT, ama lisans dosyası yok ve verinin kaynağı belirtilmemiş;
  yayından önce yazarından izin ve kaynağı sorulmalı)
- FreeDict English–Turkish (kelime anlamı olarak gösterilmiyor; yalnızca kalıplarda yedek): GPL-2.0-or-later
- Princeton WordNet 3.0: WordNet License
- KeNet Turkish WordNet (Starlang Software / Özyeğin Üniversitesi): veri CC BY-SA 4.0
- Collaborative Interlingual Index: CC BY 4.0
- Wiktionary (deyim, phrasal verb, atasözü vb. kalıplar; İngilizce ve Türkçe Vikisözlük, kaikki.org/wiktextract üzerinden): CC BY-SA 4.0
- Tatoeba (İngilizce–Türkçe çevirili örnek cümleler): CC BY 2.0 FR
- Yapay zekâyla yazılmış Türkçe açıklamalar (`dictionary-data` iş akışı): Gemini, Groq, Mistral, Cerebras ve OpenRouter
  API'leri; bu servislerin şartları çıktının kullanıcıya ait olduğunu söyler. NVIDIA API denemesi (yalnızca test
  amaçlı, çıktısı dağıtılamaz) ve kapanan GitHub Models kullanılmıyor.
- Kokoro-82M ses modeli (hexgrad): Apache 2.0
- Piper LibriTTS-R İngilizce ses: CC BY 4.0
- EMA Lightning Türkçe ses modeli (canberk7): Apache 2.0 (kod ve ağırlıklar); ONNX'e `tools/ema_export.py` ile çevrilir
- Piper Türkçe ses (Fahrettin): NabuCasa voice-datasets kayıtları, CC0
- ONNX Runtime: MIT
- sherpa-onnx: Apache 2.0 · eSpeak NG (telaffuz verisi): GPL-3.0
- Yazı tipleri Inter ve Literata: SIL Open Font License 1.1
- `tools/categories.py` kalıp listeleri bu proje için yazıldı: CC BY-SA 4.0
