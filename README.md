# Kelime Okur

İngilizce kitapları okurken bilmediğin kelimeleri öğrenmen için çevrimdışı çalışan okuyucu.
Windows, macOS, Linux, Android ve iOS için tek kod tabanı (Flutter).

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
- **İsteğe bağlı çevrimiçi analiz:** Ayarlar'a Anthropic API anahtarı girilirse kitap eklenirken (internet varsa)
  her cümlenin Türkçe çevirisi ve her bölümün özeti çıkarılıp cihaza kaydedilir; sonra internetsiz görünür.

## Geliştirme

```bash
python3 tools/build_dict.py <ham_veri_klasörü> assets/dict.db   # sözlüğü yeniden üret
flutter test
flutter run -d windows   # veya linux, macos, android cihaz
```

Ham veri dosyaları: `eng-tur.tei` (FreeDict), `wordnet/` (WordNet 3.0, nltk_data), `kenet.xml` (KeNet),
`ili-map-pwn30.tab` (CILI). `.github/workflows/build.yml` GitHub'da Windows, Android, Linux ve macOS
sürümlerini otomatik derler.

## Lisanslar

- FreeDict English–Turkish: GPL-2.0-or-later
- Princeton WordNet 3.0: WordNet License
- KeNet Turkish WordNet (Starlang Software / Özyeğin Üniversitesi): CC BY-SA 4.0
- Collaborative Interlingual Index: CC BY 4.0
- `tools/categories.py` kalıp listeleri bu proje için yazıldı: CC BY-SA 4.0

FreeDict GPL olduğu için uygulama dağıtılacaksa GPL uyumlu (ör. GPL-3.0) açık kaynak lisansla dağıtılmalıdır.
