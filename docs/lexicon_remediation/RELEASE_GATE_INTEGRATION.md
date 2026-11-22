# Gerçek yayın kapısı (Görev 5D, Aşama 6)

## Ne değişti

`release.yml`'a `prepare` ile `publish` arasına **`dictionary-gate`** işi eklendi; `publish` artık
`needs: [prepare, dictionary-gate]`. Kapı başarısız olursa veya atlanırsa `publish` hiç başlamaz; production
onayı da istenmez.

```
prepare (elle, main, sahip, YAYINLA, production ortamı, build seçimi)
   └─ dictionary-gate (yapı dosyalarındaki sözlükler + manifest)     ← yeni
         └─ publish (environment: production → reviewer onayı)
               ├─ "Same dictionaries as the gate checked"            ← yeni
               └─ paketle, doğrula, yayınla (değişmedi)
```

Korunanlar: elle başlatma, yalnız main, yalnız sahip, `YAYINLA`, production ortamında zorunlu reviewer
(`check-env`), build çalışması seçimi, sürüm sırası, `release_files.txt`, yayın sonrası kontrol. `build.yml` ve
`release_check.py check-workflows` kuralları değişmedi (yalnız release.yml 'latest'i değiştirebilir).

## Kapı neyi kontrol eder (`tools/lexicon_remediation/release_gate.py check`)

1. **Gerçek yapı dosyaları**: Windows, Android (.apk), iOS (.ipa), macOS, Linux yapılarının her birinde
   `flutter_assets/assets/dict.db` ve `tr_en.db` bulunur (zip/apk/ipa/tar.gz içinde de). Hepsi bayt bayt aynı ve
   yayın commit'indeki `assets/` dosyalarıyla aynı olmalı.
2. **Manifest**: `tools/lexicon_remediation/dictionary_manifest.json` içinde bu SHA çiftine ait tek bir girdi olmalı;
   gerçek dosyanın tablo kayıt sayıları girdidekiyle aynı olmalı.
3. **Karar**:
   * `gate`: girdide provenance kayıt dosyası (depo yolu veya https) ve SHA-256'sı olmalı. Kapı dosyayı indirir, SHA'yı
     doğrular, boş olmayan her tablonun kaydı olduğunu kontrol eder ve `gate --mode release` mantığını çalıştırır
     (her kayıt `approved`, isteğe bağlı taban ile gerileme yok). Mod değiştirilemez; legacy yok.
   * `legacy_exception`: daha önce yayımlanmış sözlük için görünür istisna. `reason`, `doc`, `published_in`,
     `approved_by` (= depo sahibi), `approved_on`, `expires_on` dolu olmalı; tarih geçmemiş ve gelecekte olmamalı.
     Her yayında `::warning::` ve iş özetinde "These dictionaries do NOT pass the licence gate" yazar.
   * `legacy_exception_proposed` veya girdi yok: **yayın durur.**
4. `publish` işi paketlemeden önce `same-dbs` ile paketlenecek dosyaların kapının kontrol ettiği SHA'ları taşıdığını
   yeniden doğrular.
5. Kapı adımı `set -euo pipefail` ile çalışır (`| tee` hatayı gizlemesin). Aynı koruma `publish`'in
   "Package and check the files" adımına da eklendi: önceden `verify-dist … | tee SHA256SUMS` başarısız doğrulamayı
   gizleyebiliyordu (mevcut bir açık; `build.yml` provasında aynı desen duruyor, PR'ları kırmamak için dokunulmadı).

Yeşil bir CI veya `lexicon-provenance` legacy raporu onay **sayılmaz**: kapı hiçbir CI sonucunu okumaz; `release.yml`
legacy modu veya lexicon-provenance kullanırsa `check-workflow` reddeder.

## Legacy exception

Bugünkü sözlük (8.3 ile aynı) `gate --mode release`'den geçmiyor (104.062 blocked). Manifestte bu sözlük için
**önerilmiş ama onaylanmamış** bir istisna var (`legacy_exception_proposed`, `approved_by` boş). Sonuç:

> **Bu PR birleşirse, sözlük düzeltilene veya Hamit istisnayı onaylayana kadar hiçbir yayın yapılamaz.**

Sadece uygulama kodu değişen bir yayın için Hamit ayrı bir PR'da girdiyi şöyle değiştirebilir (açık, görünür, süreli):

```json
"decision": "legacy_exception",
"exception": { "...": "...", "approved_by": "hamitgk-beep", "approved_on": "2026-11-23", "expires_on": "2027-02-28" }
```

Bu onay sözlüğü lisans güvenli yapmaz; yalnızca zaten yayında olan dosyaların yeniden dağıtılmasına sahibin bilerek
izin verdiğini kaydeder. Yeni veya değişmiş bir sözlük bu istisnayı kullanamaz (SHA eşleşmez).

## Kanıt: gerçek veriyle prova (yayın yok)

Gerçek `assets/*.db` dosyaları sahte yapı klasörlerine (5 platform düzeni, apk/ipa zip) konup kapı çalıştırıldı:

```
$ release_gate.py check --dist dist --src . --manifest tools/lexicon_remediation/dictionary_manifest.json --owner hamitgk-beep
::error::dictionary gate: entry 'Storilex 8.3 dictionaries (published, legacy)' is only a proposed exception; the owner has not approved it (...)
exit=1
```

Aynı prova, geçici bir manifest kopyasında istisna onaylı sayılarak:

```
dict.db: ab4a7a53… (585231 rows in 15 tables)
tr_en.db: 49a661b9… (631345 rows in 6 tables)
::warning::WARNING: released under the exception "Storilex 8.3 dictionaries (published, legacy)", approved by hamitgk-beep … These dictionaries do NOT pass the licence gate.
dictionary gate: allowed
exit=0
```

Aday sözlük için kapı (provenance kayıtlarıyla `gate` kararı) geçmez: `COVERAGE_AND_QUALITY_IMPACT.md` ve
nihai rapor.

## Testler

`tools/lexicon_remediation/test_release_gate.py` (sentetik yapı dosyaları ve sözlükler):

* Yapı dosyaları: eksik platform, eksik sözlük, platformlar arası farklı sözlük, commit'ten farklı sözlük, paketli
  tar.gz okuma, `same-dbs` uyuşmazlığı.
* Manifest: geçen kapı; bilinmeyen sözlük; kayıt sayısı uyuşmazlığı; blocked / needs_review / AI kaydı; kaydı
  olmayan tablo; SHA'sı tutmayan kayıt dosyası; kayıt dosyası olmayan "gate"; commit dışı yol; tabana göre kayıp;
  geçersiz karar (çıkış 2).
* İstisna: önerilmiş istisna yayını durdurur; onaylı istisna uyarı verir; her alan zorunlu; yalnız sahip; süresi
  dolmuş; gelecek tarihli; istisnada da sayılar kontrol edilir.
* `release.yml` yapısı: depodaki dosya geçer; `publish` kapısız, kapı kaldırılmış, `continue-on-error`/`if:` ile
  atlanabilir kapı, `publish`'te `if: always()`, `|| true` veya `pipefail`siz boru, legacy mod, `same-dbs`
  eksik, production ortamı kaldırılmış → hepsi reddedilir. YAYINLA, `check-env` ve `workflow_dispatch` dışında
  tetikleyici olmadığı da kontrol edilir.
* Depodaki manifest: onaylı istisnaların bütün alanları ve belgesi var.

PR CI: `lexicon-provenance.yml` bu testleri ve `check-workflow`'u yalnız ilgili dosyalar değişince çalıştırır
(her PR'ı engellemez). Hiçbir test yayın başlatmaz.
