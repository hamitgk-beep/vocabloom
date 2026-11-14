# VocaBloom

İngilizce kitapları okurken bilmediğin kelimeleri öğrenmen için çevrimdışı çalışan okuyucu.
Windows, macOS, Linux, Android ve iOS için tek kod tabanı (Flutter).

Geliştiren: Hamit Gök

## Neler yapar

- **Kitap ekleme:** EPUB, PDF (metinli), TXT, Markdown, HTML, DOCX, ODT, FB2, RTF. Kitap uygulamanın kendi
  formatına (bölüm → paragraf) dönüştürülüp cihazdaki SQLite veritabanına kaydedilir.
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
- **Doğal sesli okuma (çevrimdışı):** kelimenin telaffuzu (hoparlör düğmesi), cümleyi normal veya yavaş dinleme,
  kitabı baştan sona sesli okuma (okunan cümle vurgulanır, sayfa kendiliğinden kayar). İngilizce: Kokoro-82M
  (11 ses, Amerikan/İngiliz, kadın/erkek). Türkçe anlam ve çeviriler: Piper Fahrettin / Fettah. Ses paketleri
  ilk kullanımda bir kez indirilir (İngilizce ~120 MB, her Türkçe ses ~55 MB), sonra internetsiz çalışır.
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
flutter test                              # birim testleri + kaynakta sabit metin denetimi (test/l10n_test.dart)
flutter test qa_test/language_test.dart   # her ekranı Türkçe ve İngilizce açar, yanlış dilde metin arar, ekran görüntüsü alır
flutter run -d windows   # veya linux, macos, android cihaz
```

Ham veri dosyaları: `eng-tur.tei` (FreeDict), `wordnet/` (WordNet 3.0, nltk_data), `kenet.xml` (KeNet),
`ili-map-pwn30.tab` (CILI), `wiktionary_phrases.json.gz` (`data-wiktionary` sürümünden; GitHub'da
"wiktionary-data" iş akışı ile yeniden üretilir). `.github/workflows/build.yml` GitHub'da Windows, Android, Linux ve macOS
sürümlerini otomatik derler.

## Lisanslar

- FreeDict English–Turkish: GPL-2.0-or-later
- Princeton WordNet 3.0: WordNet License
- KeNet Turkish WordNet (Starlang Software / Özyeğin Üniversitesi): CC BY-SA 4.0
- Collaborative Interlingual Index: CC BY 4.0
- Wiktionary (deyim, phrasal verb, atasözü vb. kalıplar; kaikki.org/wiktextract üzerinden): CC BY-SA 4.0
- Kokoro-82M v1.0 ses modeli: Apache 2.0
- Piper Türkçe sesler (Fahrettin, Fettah): NabuCasa voice-datasets kayıtları, CC0
- sherpa-onnx: Apache 2.0 · eSpeak NG (telaffuz verisi): GPL-3.0
- `tools/categories.py` kalıp listeleri bu proje için yazıldı: CC BY-SA 4.0

FreeDict GPL olduğu için uygulama dağıtılacaksa GPL uyumlu (ör. GPL-3.0) açık kaynak lisansla dağıtılmalıdır.
