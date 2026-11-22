# Lisans denetimi (Görev 5C, Aşama 2)

Tarih: 22 Kasım 2026. **Bu bir hukuki görüş değildir.** Lisans uyumu hakkında kesin karar verilmedi; hukuki
yorum gerektiren her konu "açık risk" olarak yazıldı. Kanıt türleri: **D** = dosya bu çalışmada indirilip okundu
(git clone veya raw.githubusercontent.com); **W** = resmî web sayfası bu çalışmada okundu (kısa alıntı);
**5A** = Görev 5A raporundan (`f53da4d`, `docs/lexicon_research/LICENSE_MATRIX.md`), bu çalışmada yeniden okunmadı.

Uygulamanın kendi beyanı (Ayarlar > Gizlilik ve lisanslar, `lib/ui/settings_page.dart:528`): "Uygulamadaki sözlük
veritabanı bu kaynaklardan uyarlanmıştır ve aynı lisansla (CC BY-SA 4.0) paylaşılır." Denetim bu hedefe göre yapıldı.

## Özet tablo

| Kaynak | Lisans | Kanıt | Veritabanında | Kapı kararı | Neden |
|---|---|---|---|---|---|
| Princeton WordNet 3.0 | WordNet 3.0 License (izin verici, bildirim şartı) | D: `wordnet/LICENSE` | 373.546 kayıt (`syn` tanımları, `sense`, `exc`, `fam`) | **approved** | Lisans, sürüm, kayıt kimliği belli |
| Storilex katkıları | sahibinin beyanı | depo | 14.189 kayıt | **approved** (sahip beyanı) | Kopya olmadığına dair yazılı beyan önerilir |
| KeNet | CC BY-SA 4.0 (veri) | D: README "Licensing" | 19.682 `syn.tr` + 6.922 `tr_en` "wn" | needs_review | Kullanılan sürüm kaydedilmemiş; eşleme çıkarımla |
| CILI | CC BY 4.0 | D: `LICENSE` | eşleme (destek) | approved (kaynak olarak) | Sürüm kaydedilmemiş |
| English Wiktionary (kaikki) | CC BY-SA 4.0 + GFDL | W: Wiktionary:Copyrights | 27.985 `tr_en` anlamı, 401.588 biçim, `expr` | needs_review | Döküm tarihi yok |
| Kindle derlemesinin Wiktionary kısmı | derleme GPL-2.0+; alınan kısım CC BY-SA (miras) | D: README, `build.py` | 33.748 `ft` terimi + 7.247 `tr_en` | needs_review | Derlemeden alt küme alma; .mobi sürümü yok |
| Vikisözlük (TR) | CC BY-SA (doğrulanamadı) | – | `expr` kısmı | needs_review | Lisans sayfası okunamadı |
| Tatoeba | CC BY 2.0 FR varsayılan; cümle başına farklı | W: Terms of Use | 146.981 örnek cümle çifti (+ sayım tabloları) | needs_review | Cümle kimliği/yazarı/lisansı saklanmıyor |
| FrequencyWords | doğrulanamadı | 5A | 55.364 sıra değeri | needs_review | "CC BY-SA 4.0" beyanının dayanağı yok |
| **damdafayton** | **"MIT" iddiası, lisans dosyası yok** | D: clone | **83.381 `ft` + 20.680 `tr_en`** | **blocked** | Lisans kanıtı ve veri kökeni yok |
| FreeDict eng-tur 0.3 | GPL-2.0-or-later | D: TEI başlığı | 1 `expr` (çıkarım) | **blocked** (CC BY-SA paket için) | GPL içerik CC BY-SA altında dağıtılamaz |
| AI çıktıları | lisans yok, sağlayıcı şartları | 5A, iş akışı yorumları | 102.927 kayıt | unknown | İnsan incelemesi ve sağlayıcı şartı kaydı yok |

## 1. damdafayton/eng-tur-dictionary

- **Ne bulundu (D, 22 Kasım 2026, `git clone`, son commit `f8f1a3d`, 2022-02-17):** depo `README.md`, `dict_base.py`,
  `dict_logic.py`, `start.py`, `english_turkish.sqlite`, `backup.sqlite`, `animation.gif` içeriyor. README'nin sonu:
  "This project is [MIT](./MIT.md) licensed." **`MIT.md` yok** (main ve master dallarında 404); `LICENSE`, `LICENSE.md`,
  `COPYING` da yok. README bir şablon (ilk sürümde yazar "Author1").
- **Verinin kökeni:** `dict_base.py`, veritabanını kullanıcıdan istenen bir dosyadan kurar; varsayılan adı
  `lugat1.xls`. Bu dosyanın nereden geldiği depoda, README'de veya commit mesajlarında yazmıyor.
- **Ayarlar'daki "(MIT)" ifadesinin dayanağı:** yalnız README cümlesi. Bir MIT lisansı (a) telif sahibini ve
  (b) izin metnini içerir; ikisi de yok. Ayrıca README'nin "project" kelimesi kodu mu veriyi mi kapsıyor belli değil
  ve yazar veriyi üretmediyse veriye lisans veremez.
- **Karar:** Kaynak `registry.json`'da `license_status: claimed_unverified`, `data_origin: unknown` → kapı **blocked**.
  Bu içerik MIT kabul edilmedi.
- **Etkisi:** `ft`'deki Türkçe terimlerin %71,2'si (83.381), ana anlamların %57,7'si (24.314 kelime) ve `tr_en`'deki
  "fd" başvurularının %74'ü (20.680) bu kaynaktan.
- **Çıkış yolları (öneri, karar sahibinin):** yazara (GitHub: damdafayton / backtofayton) yazılı olarak verinin kökenini
  ve lisansını sormak; yanıt gelmezse bu terimleri yeni yayından çıkarmak (silmeden, ayrı katmanda tutarak).

## 2. FreeDict English–Turkish

- **Sürüm ve lisans (D):** `freedict/fd-dictionaries/eng-tur/eng-tur.tei` başlığı: edition **0.3**, 2017-12-03,
  36.589 madde; "Copyright (C) 1999-2017 by various authors"; "GNU General Public License ver. 2.0 and any later version".
  Kaynak: gtksozluk2 (linuxprogramlama.com). Debian telif dosyası (sources.debian.org) bot korumasından dolayı okunamadı.
- **GPL yükümlülükleri:** GPL kapsamındaki bir eseri dağıtan, onu aynı lisansla ve "tercih edilen değişiklik biçimi"yle
  (kaynak) birlikte sunmalı, lisans metnini eklemeli.
- **CC BY-SA ile birlikte (W):** Creative Commons, CC BY-SA 4.0'dan **GPLv3'e** tek yönlü uyumluluk ilan etti
  ("one-way compatibility from CC BY-SA 4.0 to GPLv3"); CC wiki: "People may *not* adapt a GPLv3-licensed work and use
  BY-SA to license their contributions." Yani GPL içeriği CC BY-SA 4.0 altında yeniden lisanslamak için bir izin yok.
- **Bugünkü durum (yeni bulgu):** 5A, `tr_en.db`'deki 23.952 "fd" anlamını FreeDict sanıyordu. Yeniden üretim gösterdi ki
  bu anlamlar FreeDict'ten değil, `ft`'den (Wiktionary + damdafayton) geliyor. `dict.db`'de FreeDict'e çıkarımla
  bağlanan yalnız 1 ifade anlamı var (`expr`, WordNet'ten türetilen ifadeler). Yani **FreeDict sorunu büyük ölçüde
  bir etiket ve atıf sorunu**: Ayarlar FreeDict'i listeliyor ama içerik pratikte yok.
- **Açık risk:** O 1 kayıt ve eski sürümlerde dağıtılmış FreeDict içeriği. Kapı, GPL lisanslı kaydı CC BY-SA paket için
  **blocked** sayar; paket GPL-3.0 ile işaretlenirse durum değişebilir (hukuki görüş gerekir).

## 3. Kindle EN–TR derlemesi (Murat Uysal, mybottles/kindle-en-tr-dictionary)

- **Lisans (D, README ve `build.py`, son commit `a6c0644`, 2026-05-23):** "Build kodu (build.py): MIT"; "Dictionary
  içeriği (english-turkish-dictionary.mobi): GPL v2.0+ (kaynak verilerden miras)". Kaynaklar: kaikki.org English
  Wiktionary (Mayıs 2026, CC BY-SA 4.0 + GFDL) ve FreeDict eng-tur 0.3 (GPL-2.0+).
- **Storilex hangi kısmı aldı:** `build.py` FreeDict bloklarına `pos: "freedict"` verir ve bunları sözcük türü etiketi
  olmadan (`<p>…</p>`) yazar; Wiktionary blokları `<p><i>n.</i> …</p>` biçimindedir. `tools/main_meanings.py extract`
  yalnız `<p><i>[a-z]+\.</i>` ile başlayan paragrafları alır. **Yani FreeDict kısmı yapı gereği dışarıda kalıyor**
  (kod incelemesiyle doğrulandı; .mobi dosyasının kendisi bu çalışmada yoktu).
- **Açık risk:** (a) Hangi .mobi sürümünün kullanıldığı kayıtlı değil. (b) Derleme bir bütün olarak GPL-2.0+ ile
  dağıtılıyor; ondan çıkarılan Wiktionary alt kümesinin CC BY-SA 4.0 olarak kalıp kalmadığı, derleyicinin seçim/düzen
  emeği açısından hukuki yorum ister. Temiz yol: aynı içeriği doğrudan kaikki.org dökümünden, sürümü kaydederek üretmek.
- **Karar:** `inherited` → **needs_review** (engellenmedi, onaylanmadı).

## 4. Tatoeba

- **Lisans (W, Terms of Use, yürürlük 24 Nisan 2022):** cümleler için varsayılan "CC-BY 2.0 FR"; "Tatoeba allows
  licensing each text sentence"; CC0 cümleler var; "Certain phrases, in particular audio, may be contributed with a
  non-marketing condition"; ND ve SA koşullu içerik olabileceği yazıyor; atıf: "only allowed if the name of the author is
  cited". Bir cümleyi dağıtanın "it is your responsibility to circulate it with its license".
- **CC0 (W, wiki):** CC0 yalnız "original sentences" için, izinle açılan bir özellik. Ayrı bir CC0 dışa aktarım
  dosyasının varlığı bu çalışmada doğrulanamadı.
- **Storilex'te ne saklanıyor:** `dict.db.exs` (70.105): cümle kimliği **yok** (`tatoeba_extract.py` yalnız metni yazıyor).
  `tr_en.db.ex` (84.385): Türkçe cümle kimliği var (83.264), İngilizce cümle kimliği yok. Hiçbir yerde yazar adı veya
  cümle lisansı yok.
- **Sonuç:** CC0, CC BY ve diğer durumlar şu an **ayırt edilemiyor**. Kapı her Tatoeba kaydını `per_record_license_missing`
  ile **needs_review** sayar. Çözüm: dökümün tarihini, iki cümlenin kimliğini, yazarını ve lisansını içe alımda saklamak
  (Tatoeba'nın `sentences_detailed` dökümü kullanıcı adını verir; lisans alanının kaynağı ayrıca doğrulanmalı).

## 5. Wiktionary / kaikki

- **Lisans (W, Wiktionary:Copyrights):** metin "dual-licensed … under both the Creative Commons Attribution-ShareAlike
  4.0 International License (CC-BY-SA) and the GNU Free Documentation License (GFDL)", GFDL "Version 1.1 or any later".
  Sayfa kendini "a draft proposal. It is unofficial" olarak tanımlıyor; Wikimedia kullanım şartları ayrıca okunmadı.
- **Yeniden kullanım koşulları:** CC BY-SA yolunu seçen yeniden kullanıcı (a) atıf yapmalı (yazarlar = katkıcılar;
  sayfa bağlantısı veya proje bağlantısı), (b) değişiklik yapıldığını belirtmeli, (c) uyarlamayı CC BY-SA 4.0 (veya
  uyumlu lisans) ile paylaşmalı. GFDL yolu "transparent copy" ve GFDL ile lisanslama ister; Storilex CC BY-SA yolunu
  seçmeli ve bunu yazmalı.
- **kaikki / wiktextract:** kod MIT (D: `tatuylonen/wiktextract/LICENSE`); veri Wiktionary lisansını taşır. kaikki.org bu
  ortamdan erişilemedi (5A'da da). Döküm tarihi hiçbir iş akışında kaydedilmiyor.
- **Vikisözlük (tr.wiktionary.org):** lisans sayfası bu çalışmada okunamadı → `claimed_unverified`.

## 6. KeNet ve diğer kaynaklar

- **KeNet (D):** README "Licensing" bölümü: kod GPL-3.0, "All XML data files (kenet.xml, …) … licensed under the Creative
  Commons Attribution-ShareAlike 4.0". **Bu bölüm 2026-10-05'te eklendi** (commit `0a0ba22`); 2021'den beri depoda tek
  lisans dosyası GPL-3.0. Storilex `kenet.xml`'i commit belirtmeden `master`'dan indiriyor. Kasım 2026 derlemeleri
  bu tarihten sonra, ama hangi commit'in kullanıldığı kanıtlanamıyor → needs_review. Ticari kullanım CC BY-SA ile serbest.
- **CILI (D):** "licensed under CC BY 4.0 or any later version", Francis Bond.
- **WordNet 3.0 (D):** "Permission to use, copy, modify and distribute this software and database … for any purpose",
  bildirim her kopyada.
- **FrequencyWords / OpenSubtitles:** kod MIT (5A); kelime listesinin "CC BY-SA 4.0" beyanının dayanağı bulunamadı;
  OPUS, OpenSubtitles için lisans adı vermiyor (5A). Yalnız sıra numarası kullanılıyor; risk düşük ama belgesiz.
- **Yalnız araştırma/değerlendirme için kullanılabilenler (pakete girmez):** BabelNet (ticari değil, araştırma
  kurumları), UDPipe modelleri ve TR-IMST (CC BY-NC-SA), PARSEME TR (CC BY-NC-SA), MAGPIE cümleleri (BNC), NVIDIA API
  deneme çıktısı (yayımlama yasak). Kayıt defterinde bu tür kaynaklar `redistribution: evaluation_only/forbidden`
  ile işaretlenir ve kapı onları **blocked** yapar. Bugünkü veritabanlarında bunlardan kayıt bulunmadı.

## 7. AI çıktıları

- 102.927 kayıt (own_word 80.997, own_expr 13.110, expr.entr 4.184, exd 2.510, syn.tr 1.766, tr_en "wn" 360).
- Lisans değil hizmet şartları geçerli; model adı ve tarih satır düzeyinde saklanmıyor. NVIDIA deneme API'sinin
  (yayımlamayı yasaklayan şart) kullanılmadığı yalnız iş akışı yorumuyla belgeli; veri düzeyinde kanıt yok.
- Kapı: `license_unknown` → **unknown**, ayrıca `ai_needs_human_review`. AI taslağı hiçbir zaman bağımsız doğrulama
  sayılmaz (`evidence_value: none`).

## 8. Uygulama içindeki diğer lisans ifadeleri

- `settings_page.dart:475` "© 2026 Hamit Gök. Tüm hakları saklıdır." ile `:538` "Storilex açık kaynaklıdır (GPL-3.0)"
  yan yana. Kodun GPL-3.0, sözlüğün CC BY-SA 4.0 olduğu ayrı ayrı yazılmalı (bkz. ATTRIBUTION_PLAN.md).
