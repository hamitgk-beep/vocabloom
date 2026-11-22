# Düzeltme planı (Görev 5C)

Öncelik: önce kullanıcıya yanlış lisans beyanı ve kanıtı olmayan içerik, sonra eksik atıf, sonra izlenebilirlik.
**Bu plandaki hiçbir adım bu PR'da uygulanmadı;** her biri ayrı onay ister. Hiçbir adım veriyi silmeyi
gerektirmez: içerik ayrı bir katmana alınır ve yeni yayında gösterilmez.

## Sözlük lisans güvenli değildir

Bugünkü `dict.db` ve `tr_en.db` yeni bir kamuya açık sürüm için kapıdan **geçmiyor** (`gate.py --mode release` → 1).
Kesin onaylanabilen içerik yalnız Princeton WordNet ve Storilex katkıları. Diğer her şey ya inceleme bekliyor ya
kökeni/lisansı belirsiz ya da engelli.

## Öncelik sırası

| # | Sorun | Etki | Ne yapılmalı | Kim | Hukuki görüş |
|---|---|---|---|---|---|
| 1 | **damdafayton**: lisans dosyası yok, veri kökeni (`lugat1.xls`) bilinmiyor; Ayarlar "MIT" diyor | `ft` 83.381 terim (%71), 24.314 kelimenin ana anlamı; `tr_en` 20.680 başvuru | (a) Ayarlar'dan "(MIT)" kaldırılsın. (b) Yazara kökeni ve lisansı sorun. (c) Yanıta kadar yeni sürümde bu terimler ayrı katmana (`ft_src` sütunu veya ayrı tablo) alınsın; yalnız damdafayton'dan anlamı olan 24.314 kelime için Wiktionary / KeNet / katkı ile yeniden doldurma planı. | Sahip + geliştirici | Gerekirse |
| 2 | **tr_en "fd" etiketi yanlış** | 27.927 başvuru FreeDict değil Wiktionary + damdafayton | `add_reverse.py` kaynağı terim düzeyinde yazsın (`s: "kw"` / `"dm"`); `meta.reverse` ve `meta.sources` düzeltilsin; damdafayton kökenliler #1 ile aynı muameleyi görsün. | Geliştirici | Hayır |
| 3 | **Sözlük lisans beyanı** ("aynı lisansla CC BY-SA 4.0") kanıtlanamayan içeriği kapsıyor | Uygulamanın tamamı | ATTRIBUTION_PLAN §1'deki metin düzeltmeleri; AI taslakları satırı; WordNet tam bildirimi. | Geliştirici (UI görevi) | Hayır |
| 4 | **Kindle derlemesinden alt küme** | `ft` 33.748 terim, `tr_en` 7.247 | Aynı Wiktionary çevirilerini doğrudan kaikki.org dökümünden, döküm tarihi ve SHA-256 ile üretmek; derleyiciye atıf korunur. Bu, GPL derlemeye bağımlılığı ve sürüm eksikliğini birlikte kaldırır. | Geliştirici | Doğrudan dökümle gerekmez |
| 5 | **Tatoeba cümle düzeyinde lisans/yazar yok** | 146.981 cümle çifti | İçe alımda iki cümlenin kimliği, yazarı, lisansı ve döküm tarihi saklansın (`exs` için ek tablo; `tr_en.ex` için İngilizce kimlik). CC0 / CC BY / diğer ayrı sayılsın; lisansı bilinmeyen veya ND/"non-marketing" cümle yayına girmesin. | Geliştirici | Hayır |
| 6 | **AI içerik insan incelemesiz** | 102.927 kayıt | PR #110 katmanı korunur. Yeni yayında AI taslakları "doğrulanmamış" etiketiyle kalabilir ama `approved` sayılmaz; model, sağlayıcı ve tarih satıra yazılsın; NVIDIA gibi yayımlamayı yasaklayan şartlı çıktıların girmediği veriyle kanıtlansın. | Geliştirici + sahip | Sağlayıcı şartları için gerekebilir |
| 7 | **`syn.tr` içinde AI Türkçesi** (1.766) ve `tr_en` "wn" içinde AI kökenli 360 anlam | `add_reverse.py` belgesi "yalnız insan yapımı" diyor | `load_syn` doldurduğu terimleri ayrı işaretlesin; `add_reverse.py` yalnız KeNet terimlerini ters çevirsin. | Geliştirici | Hayır |
| 8 | **Sürümler kayıtlı değil** (kaikki, KeNet, CILI, Tatoeba, Kindle .mobi, damdafayton commit) | Kayıtların çoğu `source_version_missing` | İş akışları indirdikleri dosyanın tarihini/commit'ini/SHA-256'sını `meta` tablosuna ve kayıt defterine yazsın; `master` yerine sabit commit. | Geliştirici | Hayır |
| 9 | **FreeDict GPL** | 1 `expr` kaydı (çıkarım); Ayarlar'da gereksiz satır | Kaydı ayıklamak veya GPL olarak işaretlemek; Ayarlar satırını güncellemek. | Geliştirici | Paket GPL yapılacaksa evet |
| 10 | **`expr` içinde kaynağı bilinmeyen** 6.137 Türkçe anlam, 9.571 örnek, 453 tanım | | `build_dict.py` her alanı dolduran adımı kayda yazsın (`stage`); eski kayıtlar `unknown` kalır. | Geliştirici | Hayır |
| 11 | **FrequencyWords "CC BY-SA 4.0"** dayanaksız | Yalnız sıra | Lisans dayanağını bulmak veya ifadeyi kaldırmak; gerekirse wordfreq (Apache-2.0 kod, CC BY-SA 4.0 veri) ile değiştirmek. | Geliştirici | Hayır |
| 12 | **Vikisözlük (TR) lisansı** okunamadı | `expr` kısmı | tr.wiktionary.org telif sayfasını okuyup kayıt defterine kanıt eklemek. | Geliştirici | Hayır |
| 13 | **Storilex katkıları** sahibinin beyanı | 14.189 kayıt | Katkıların kapalı sözlüklerden kopyalanmadığına dair kısa yazılı beyan (CONTRIBUTING notu). | Sahip | Hayır |

## Derlemeye provenance eklemek (sonraki görev için öneri)

1. `build_dict.py`, `main_meanings.py`, `add_reverse.py`, `contrib/apply.py` her yazdıkları değer için
   `PROVENANCE_SCHEMA.md` alanlarını bir yan dosyaya (`assets/dict.provenance.jsonl.gz`, uygulamayla dağıtılmaz) yazsın.
2. Uygulama şeması değişmez; yalnız gerekiyorsa `ft`'ye bir kaynak sütunu eklenir ve `DictDb.policyVersion` artırılır.
3. `lexicon-provenance.yml` yeni sürüm PR'larında `--mode release --baseline <son sürüm>` ile çalışır ve kırmızı
   olursa `release.yml` başlatılmaz (bugünkü production onayı korunarak).

## Açık riskler (hukuki görüş gerektirebilir)

- Kindle (GPL-2.0+) derlemesinden çıkarılan Wiktionary alt kümesinin CC BY-SA 4.0 olarak kullanılması.
- CC BY 2.0 FR (Tatoeba) içeriğin CC BY-SA 4.0 veritabanında uyarlama olarak dağıtılması (yaygın uygulama uyumlu
  sayar; resmî bir CC uyumluluk kararı bu denetimde okunmadı).
- AI sağlayıcılarının çıktı şartları (her sağlayıcı ayrı; bu denetimde okunmadı).
- Daha önce dağıtılmış sürümlerdeki FreeDict ve damdafayton içeriği.
