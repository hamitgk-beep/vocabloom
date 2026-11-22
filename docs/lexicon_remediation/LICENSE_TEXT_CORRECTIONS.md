# Lisans metni düzeltmeleri ve "fd" etiketi (Görev 5D, Aşama 1)

**Önemli:** Metni düzeltmek hukuki sorunu çözmez. Bu değişiklik yalnızca uygulamanın kullanıcıya **yanlış bir
lisans beyanı** göstermesini durdurur. Lisansı belirsiz içerik sözlükte durdukça (bugünkü yayın) yayın kapısı
kırmızı kalır (`RELEASE_GATE_INTEGRATION.md`).

## Değişen dosyalar

| Dosya | Değişiklik |
|---|---|
| `lib/data/dictionary_sources.dart` (yeni) | "Sözlük kaynakları" satırlarının tek kaynağı (`dictionarySourceLines()`), Türkçe→İngilizce kaynak etiketi (`trSenseSourceLabel`), WordNet 3.0 tam lisans metni, veri lisans bildirimleri ve `registerDataLicences()` |
| `lib/ui/settings_page.dart` | Gizlilik ve lisanslar sayfası bu satırları gösterir; "Kullanılan kütüphanelerin lisansları" düğmesi önce veri bildirimlerini kaydeder; Hakkında'daki "Tüm hakları saklıdır" yerine kod/veri ayrımı |
| `lib/ui/tr_word_sheet.dart` | Türkçe kelime panelindeki kaynak satırı `trSenseSourceLabel` ile; "Kaynak: FreeDict" artık yok |
| `lib/data/tr_en_dict.dart` | `TrSense.source` belgesi düzeltildi |
| `tools/tr_en/add_reverse.py` | Ters çevrilen anlamlar artık `"rv"` etiketiyle yazılır; belge ve `meta.reverse` metni düzeltildi |
| `tools/lexicon_provenance/inventory.py` | `"rv"` etiketini de tanır |
| `test/dictionary_sources_test.dart` (yeni) | Regresyon testleri (aşağıda) |

## Önce / sonra

| Konu | Önce (8.3) | Sonra |
|---|---|---|
| damdafayton | "Yardımcı kelime anlamları: damdafayton/eng-tur-dictionary **(MIT)**" | "Ek kelime anlamları: damdafayton/eng-tur-dictionary. Bu kaynağın lisansı ve verinin kökeni doğrulanamadı; bu anlamlar için bir lisans beyan edilmez ve kaynak sahibine soruluyor." |
| Kindle derlemesi | "… Kindle … derlemesi (CC BY-SA 4.0)" | "Wiktionary çevirileri (CC BY-SA 4.0, yazarlar: Wiktionary katkıcıları), … Kindle derlemesindeki Wiktionary bölümünden. Derlemenin tamamı GPL-2.0+ ile dağıtılıyor; bu bölümün lisans durumu inceleniyor." |
| Veritabanının tamamı | "… bu kaynaklardan uyarlanmıştır ve **aynı lisansla (CC BY-SA 4.0)** paylaşılır." | "… Açık lisanslı bölümler kendi lisanslarıyla paylaşılır (çoğunlukla CC BY-SA 4.0); lisansı doğrulanamadı denen bölümler için bir lisans beyan edilmez." |
| FreeDict | "FreeDict English–Turkish (GPL-2.0+)" | "… yalnızca birkaç ifade anlamında kalmış olabilir; bu içerik CC BY-SA altında değildir ve ayıklanması planlanıyor." |
| FrequencyWords | "(CC BY-SA 4.0)" | "kelime sıklığı sırası: FrequencyWords (Hermit Dave), OpenSubtitles 2018 verisinden (lisansı doğrulanamadı)" |
| Tatoeba | "(CC BY 2.0 FR)" | "Varsayılan lisans CC BY 2.0 FR; bazı cümlelerin lisansı farklı olabilir. Cümle yazarları henüz gösterilmiyor." |
| Yapay zekâ taslakları | (yoktu) | Yeni satır: AI ile hazırlandı, insan kontrolü yok, "doğrulanmamış" etiketi |
| WordNet bildirimi | Yalnız ad | Tam WordNet 3.0 lisans metni, "Kullanılan kütüphanelerin lisansları" sayfasında "Princeton WordNet 3.0" girdisi olarak; KeNet, CILI, Wiktionary, Tatoeba bildirimleri de orada. damdafayton için bildirim **yok** (lisansı bilinmiyor) |
| Kategori listeleri | "bu uygulama için hazırlandı (CC BY-SA 4.0)" | "… yapay zekâ yardımıyla hazırlandı (CC BY-SA 4.0)" |
| Hakkında | "© 2026 Hamit Gök. Tüm hakları saklıdır." | "© 2026 Hamit Gök. Uygulama kodu GPL-3.0; sözlük verisinin kaynakları ve lisansları: Ayarlar > Gizlilik ve lisanslar." |

Bütün metinler `L('Türkçe', 'English')` düzeninde; İngilizce yarılar `test/l10n_test.dart` kurallarından geçiyor.

## "fd" etiketi

5C kanıtı: `tr_en.db` içinde `"s": "fd"` taşıyan 27.927 İngilizce kelimenin **hepsi** `dict.db ft`'nin tersinden yeniden
üretiliyor: 20.680'i damdafayton, 7.247'si Kindle-Wiktionary kökenli; FreeDict kökenli **hiçbiri** yok. `add_reverse.py`
bu etiketi FreeDict'in `ft`'de olduğu döneme göre yazıyordu; `ft` 17.11.2026'dan beri FreeDict içermiyor.

Arama, anahtarlar ve kullanıcının gördüğü anlamlar bozulmasın diye:

* Var olan veritabanı **değiştirilmedi**: `"fd"` etiketi bugünkü `tr_en.db`'de duruyor. Uygulama `"fd"` ve yeni `"rv"`
  etiketlerini aynı biçimde okur ve "Kaynak: İngilizce → Türkçe anlamların tersi" yazar (FreeDict demez).
* `add_reverse.py` bundan sonra `"rv"` yazar. Aday sözlükte `"fd"` kalmadı (7.005 grup `"rv"`).
* Tanımayan bir etiket için uygulama kaynak uydurmaz: "Kaynak: belirtilmemiş".
* `trFreeDict` adlı iç alan (dict_db.dart) yalnız kod içi addır; kullanıcıya gösterilmez ve geniş çaplı yeniden
  adlandırma gerektirdiği için bu görevde değiştirilmedi (ilgisiz kodu yeniden düzenlememe kuralı).

## Tek GPL ifade kaydı

`expr` içinde kökü FreeDict'e (GPL-2.0+) çıkan 1 Türkçe anlam var: `break through` (phrasal_verbs) → "hamle, cepheyi
yarıp geçme" (build_dict yeniden üretimiyle, güven: inferred).
Bugünkü veritabanında duruyor ve kullanıcı metni bunu söylüyor; aday sözlükte `tr` alanı boşaltıldı ve değer
karantinaya alındı (`freedict_gpl`).

## Regresyon testleri (`test/dictionary_sources_test.dart`, iki dilde)

* damdafayton satırı tek, MIT veya başka bir lisans adı içermiyor, "doğrulanamadı" diyor.
* Veritabanının tamamı için "aynı lisansla" beyanı yok; son satır "bir lisans beyan edilmez" diyor.
* Kindle satırı GPL-2.0+ ve "Wiktionary bölümü" diyor; FrequencyWords için lisans adı yok.
* FreeDict satırı GPL-2.0+ ve "CC BY-SA altında değildir" diyor; AI taslakları ve Tatoeba yazarları açıklanıyor.
* `fd` ve `rv` etiketleri FreeDict demiyor; bilinmeyen etiket "belirtilmemiş".
* `registerDataLicences()` iki kez çağrılınca da bir kez kaydediyor; WordNet girdisi telif satırını, sorumluluk
  reddini ve isim kullanımı yasağını içeriyor; damdafayton için girdi yok.
* Ayarlar ve Türkçe kelime paneli ortak metinleri kullanıyor; eski "(MIT)" ve "Kaynak: FreeDict" metinleri kaynak
  kodda yok.

Yerel çalıştırma (Flutter 3.50.0): `flutter test test/dictionary_sources_test.dart test/l10n_test.dart
test/tr_en_dict_test.dart` → 28/28 geçti. `flutter analyze lib test`: yalnız `info` düzeyi, main ile aynı sayı (105).
