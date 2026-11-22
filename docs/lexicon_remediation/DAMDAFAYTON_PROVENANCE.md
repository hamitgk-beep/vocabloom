# damdafayton/eng-tur-dictionary: köken araştırması ve etki (Görev 5D, Aşama 2)

Hukuki görüş değildir. Sonuç: **lisans ve veri kökeni doğrulanamadı; içerik `blocked` kalır.**

## Bulunanlar (kanıt)

| Soru | Bulgu | Kanıt |
|---|---|---|
| Depo | github.com/damdafayton/eng-tur-dictionary, 9 commit, son commit `f8f1a3d4c24c8cbb7a492367ff07694f966dee2c` (17.02.2022). Yazarlar: `damdafayton`, `backtofayton` | `git log` (klon) |
| Lisans | README: "This project is [MIT](./MIT.md) licensed." `MIT.md` depoda **yok** (bağlantı 404); `LICENSE` dosyası **yok**; GitHub lisans algılaması yok. Commit geçmişinde lisans dosyası hiç eklenmemiş | klon, `git log --all` |
| MIT neyi kapsıyor? | README bir **komut satırı programını** (start.py, dict_logic.py, dict_base.py) anlatıyor. MIT beyanı geçerli olsa bile verinin (sözlük içeriğinin) bu beyanla lisanslandığı yazılı değil | README |
| Veri kökeni | `english_turkish.sqlite` (61.336 İngilizce başlık, 61.336 Türkçe satır), `dict_base.py` ile `lugat1.xls` adlı, sekmeyle ayrılmış "sıra no / İngilizce / Türkçe" dosyasından üretiliyor. `lugat1.xls` depoda **yok**; kim hazırladığı, nereden alındığı yazmıyor | `dict_base.py` satır 25, `start.py` satır 68 |
| `lugat1.xls` nedir? | Web aramasında bu adla açık kaynaklı bir sözlük dosyası bulunamadı. "Lügat" adlı eski serbest yazılım sözlükleri var; bağlantı **kanıtlanamadı** | Web araması (22.11.2026) |
| Gerçek hak sahibi | **Bilinmiyor.** Depo sahibi verinin yazarı olduğunu söylemiyor | — |
| `backup.sqlite` | `english_turkish.sqlite` ile aynı dosya (SHA `f8b7908d…`) | sha256sum |

Kanıtın sınırı: damdafayton'un GitHub profili, LinkedIn bağlantısı ve olası bir e-posta adresi bu görevde okunmadı;
iletişim için GitHub issue yolu önerildi.

## Kelime düzeyinde etki ve çift sayım

Aynı damdafayton içeriği üç farklı sayıda görünür; bunlar **toplanmamalı**:

| Sayı | Birim | Ne |
|---:|---|---|
| 83.381 | `ft` terimi (virgülle ayrılmış Türkçe anlam) | Yalnız damdafayton'da olan Türkçe anlamlar. 12.345 terim hem Wiktionary'de hem damdafayton'da: bunlar Wiktionary kaynaklı sayılır, damdafayton yalnız "destek" |
| 24.314 | İngilizce kelime | Wiktionary anlamı hiç olmayan, bütün `ft` satırı damdafayton olan kelimeler. Bu 24.314 kelime, 83.381 terimin büyük kısmını taşır; ayrı içerik değildir |
| 20.680 | `tr_en` İngilizce karşılık | `add_reverse.py`'nin aynı `ft` terimlerini **ters çevirmesiyle** oluşan Türkçe→İngilizce karşılıklar. Yeni içerik değil, aynı terimlerin türevi. 16.145 Türkçe başvuru yalnız bunlardan oluşuyor |

Ayrıca etkilenen ama `blocked` sayılmayanlar:

* **9.673 kelime** hem Wiktionary hem damdafayton anlamı taşıyor; 671'inde damdafayton hangi Wiktionary anlamının
  **ilk** gösterileceğini belirlemiş (aday sözlükte 702 kelimenin ilk anlamı değişti).
* `syn.tr` KeNet terimleri `main_meanings.apply` süzgecinden geçerken `ft` (Wiktionary + damdafayton) ile
  karşılaştırıldı; yani damdafayton hangi KeNet teriminin gösterileceğini de etkiledi. Terimlerin kendisi KeNet'in
  (CC BY-SA 4.0); bu bir seçim etkisidir, içerik kopyası değildir. Adayda değiştirilmedi, açık risk olarak yazıldı.
* `blocked` toplamı: 83.381 (`ft`) + 20.680 (`tr_en`) + 1 (FreeDict `expr`) = **104.062**.

24.314 kelimenin adayda ne gösterdiği: `COVERAGE_AND_QUALITY_IMPACT.md`.

## İçerik engelli kalıyor

Yanıt gelene kadar damdafayton içeriği `tools/lexicon_provenance/registry.json` içinde `claimed_unverified` +
`data_origin: unknown` olarak kalır; kapı bunu `blocked` sayar. Kayıt defterinde "approved" yapılmadı, sahte kaynak
yazılmadı. Aday sözlükte bu içerik karantinaya alındı (silinmedi): `quarantine.db` (dağıtılmaz).

Yazardan olumlu yanıt gelse bile tek başına yetmez: **verinin kendisinin** (`lugat1.xls`) kökeni ve o kaynağın
lisansı da gerekir.

## E-posta / issue taslağı (GÖNDERİLMEDİ)

Hamit'in onayı olmadan gönderilmeyecek. Adres bu görevde aranmadı; en güvenli kanal depoda bir GitHub issue'dur.
Taslak iki dilde:

---

**Konu:** eng-tur-dictionary: veri kaynağı ve lisans sorusu / Question about data origin and licence

Merhaba,

Storilex adlı açık kaynaklı (GPL-3.0) bir İngilizce okuma uygulaması geliştiriyorum
(github.com/hamitgk-beep/vocabloom). Uygulamanın sözlüğünde eng-tur-dictionary deposundaki `english_turkish.sqlite`
dosyasından alınmış Türkçe anlamlar var. Bunları kullanmaya devam edip edemeyeceğimizi öğrenmek istiyorum:

1. README "MIT" diyor ama `MIT.md` ve `LICENSE` dosyası depoda yok. MIT lisansı sözlük **verisini** de kapsıyor mu?
2. Veri `lugat1.xls` dosyasından üretilmiş. Bu dosyayı kim hazırladı, nereden alındı? Kaynağının lisansı nedir?
3. Veriyi yeniden dağıtan bir uygulamada (ücretsiz, açık kaynaklı) kullanmamıza izin verir misiniz? Atıfta adınızın
   nasıl yazılmasını istersiniz?

Yanıtınıza kadar bu içeriği yeni sürümlerimize koymuyoruz. Teşekkür ederim.

Hamit Gök

---

Hello,

I develop Storilex, an open-source (GPL-3.0) English reading app (github.com/hamitgk-beep/vocabloom). Its dictionary
contains Turkish meanings taken from `english_turkish.sqlite` in your eng-tur-dictionary repository. Before we
continue to use them I would like to ask:

1. The README says "MIT", but there is no `MIT.md` or `LICENSE` file in the repository. Does the MIT licence also
   cover the dictionary **data**?
2. The data was built from a file named `lugat1.xls`. Who made that file and where does it come from? Under which
   licence was it published?
3. May we redistribute the data in a free, open-source app? How would you like to be credited?

Until we hear from you, this content is not included in new releases. Thank you.

Hamit Gök

---

## Yanıta göre ne olur

| Yanıt | Sonuç |
|---|---|
| Veri yazarın kendi eseri + açık lisans (MIT / CC BY / CC BY-SA / CC0) yazılı | Kayıt defterinde `license_status: verified`, `data_origin: known`, kanıt bağlantısı; kapı yeniden çalışır. Yine de ayrı bir PR ve Hamit onayı |
| `lugat1.xls` üçüncü bir kaynaktan | O kaynağın lisansı araştırılır; bulunamazsa engel sürer |
| Yanıt yok / ret | Engel kalıcı; aday sözlük yolu (damdafayton'suz) uygulanır |
