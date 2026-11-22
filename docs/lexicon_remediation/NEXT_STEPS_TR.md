# Sonraki adımlar (Görev 5D)

Her biri ayrı onay ister. Sıra önem sırasıdır.

## Hamit'in kararı gerekenler

1. **Yayın kapısı ve legacy istisna.** Bu PR birleşince bugünkü sözlükle yayın durur. İki seçenek:
   (a) istisnayı onaylamak: `tools/lexicon_remediation/dictionary_manifest.json` girdisinde `decision:
   legacy_exception`, `approved_by: hamitgk-beep`, tarih ve bitiş tarihi (ayrı küçük PR);
   (b) onaylamamak: sözlük düzeltilene kadar yayın yok.
2. **damdafayton e-postası / issue'su.** Taslak `DAMDAFAYTON_PROVENANCE.md` içinde; gönderilmedi.
3. **Aday sözlüğü uygulamaya almak mı?** Şimdilik önerilmez: 24.314 kelimenin 18.610'u yalnız AI taslağına kalıyor;
   "the", "a", "could" gibi sık kelimeler ana anlamını kaybediyor; 16 uygulama testi aday veriyle kalıyor. Önce
   aşağıdaki 5–6 yapılmalı.
4. **Kaybolan iki katkı örneği** ("elden geçirmek", "üzerinde durmak"): doğrulanmış bir Türkçe→İngilizce anlamla
   yeniden eklenmeli (katkı xlsx'i).

## Geliştirici işleri

5. Doğrudan kaikki.org İngilizce dökümünden Türkçe çeviriler (sabit tarih + SHA) ile `main_meanings` girdisini
   yeniden üretmek; Kindle (GPL derleme) bağımlılığını kaldırır ve kapsamı ölçer (`SOURCE_REPLACEMENT_MATRIX.md`).
6. Sık ve işlev kelimeleri (ilk 5.000'de kaybolan 636) için katkı turu: Hamit'in elle kontrol edeceği xlsx
   (`tools/contrib` biçimi). AI taslağı ancak kişi onayından sonra `approved` olur.
7. Tatoeba: kimlik/yazar/lisans dökümü ve `exs_src` tablosu (`TATOEBA_ATTRIBUTION_PLAN.md`).
8. Ham kaynak sürümlerini sabitlemek: KeNet `89fee78`, CILI commit, kaikki döküm tarihi, Tatoeba döküm tarihi; iş
   akışları `master` yerine commit indirsin, SHA'yı `meta`'ya yazsın.
9. `expr` içindeki 6.137 kaynaksız anlam için `build_dict.py`'nin her alanı dolduran adımı kayda yazması.
10. Aday uygulamaya alınacaksa: `DictDb.version` artırılır, `ft_id_map.tsv` ile `sense_feedback` taşınır, kalan 16
   test tek tek incelenir (gevşetilmeden), sonra `dictionary_manifest.json`'a `gate` kararıyla girdi eklenir.
11. `build.yml` yayın provasındaki `verify-dist … | tee` deseni de `pipefail` almalı (ayrı PR; PR'ları
    kırabileceği için burada dokunulmadı).

## Bu görevde yapılmayanlar

* Hiçbir yayın, birleştirme, e-posta yok.
* `assets/dict.db` ve `assets/tr_en.db` değişmedi.
* Kişi tarafından kalite örneklemi yapılmadı.
* kaikki.org ve tatoeba.org bu ortamdan erişilemedi; ölçümler bu yüzden eksik.
