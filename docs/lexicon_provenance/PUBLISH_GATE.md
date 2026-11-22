# Lisans ve yayın güvenliği kapısı (Görev 5C, Aşama 4 ve 6)

Araç: `tools/lexicon_provenance/gate.py` (yalnız Python standart kütüphanesi). Yeni bir sözlük sürümü yayınlanmadan
**önce** çalışır, rapor ve karar üretir. **Hiçbir veriyi silmez, hiçbir veritabanına yazmaz** ve mevcut sürüm yayınlama
mekanizmasına (`release.yml`, "production" ortamı onayı, PR #109) dokunmaz.

## Kullanım

```
# 1. Kayıtları üret (salt okunur)
python3 -I tools/lexicon_provenance/inventory.py --dict assets/dict.db --tr-en assets/tr_en.db --repo . \
    [--raw RAW] --out records.jsonl.gz --stats stats.json
# 2a. Uygulamada bugün olanı raporla (asla başarısız olmaz, hiçbir şeyi onaylamaz)
python3 -I tools/lexicon_provenance/gate.py --records records.jsonl.gz --mode legacy --out report/
# 2b. Yeni kamuya açık sürüm için karar (önceki sürümün kayıtlarıyla karşılaştırarak)
python3 -I tools/lexicon_provenance/gate.py --records new.jsonl.gz --baseline previous.jsonl.gz --mode release --out report/
# 3. Sözlük başına izlenebilirlik oranları
python3 -I tools/lexicon_provenance/report.py records.jsonl.gz --json t.json --csv t.csv
```

Çıkış kodları: **0** geçti, **1** kapı başarısız (en az bir kayıt `approved` değil veya kaynak/lisans kaybı var),
**2** hatalı girdi (dosya yok, kayıt defteri tutarsız, kayıt yok).

## İki mod: "uygulamada kalsın" ≠ "yeni yayına girsin"

- `--mode legacy`: Bugün uygulamada olan içerik raporlanır. Durumlar aynı hesaplanır (çoğu `needs_review`, damdafayton
  `blocked`), ama çıkış 0'dır ve hiçbir şey silinmez. Geçmişten gelen belirsiz kayıtların **uygulamada kalması** bu
  moddur; bu, onları onaylamak anlamına gelmez.
- `--mode release`: Yeni bir kamuya açık dağıtım. Yalnız `approved` kayıtlar geçer; bir tane `needs_review`,
  `unknown` veya `blocked` kayıt ya da önceki sürüme göre kaynak/lisans kaybı varsa çıkış 1'dir.

`unknown` ve `needs_review` hiçbir zaman otomatik olarak `approved` olmaz. Durumu değiştirmenin tek yolu kayıt
defterini (kanıtla) veya kaydı (ör. insan doğrulaması) değiştirmektir; bu değişiklik PR'da görünür.

## Kurallar (istenen 10 kontrol)

| # | Kontrol | Kod | Sonuç |
|---|---|---|---|
| 1 | Kaynağı bilinmeyen kayıt | `source_unknown`, `source_not_in_registry` | unknown |
| 2 | Lisansı belirsiz kayıt | `license_unknown` → unknown; `license_unverified`, `license_inherited` → needs_review; `license_claim_without_origin`, `license_missing_or_conflicting`, `data_origin_unknown` → blocked | |
| 3 | Ticari dağıtıma uygunluğu doğrulanmamış | `commercial_use_unverified` → needs_review; `commercial_use_forbidden` (NC dahil) → blocked | |
| 4 | Eksik atıf | `attribution_missing` (lisans atıf istiyor, kayıt defterinde metin yok) | blocked |
| 5 | Share-alike / copyleft / paket uyumu | `obligation_share_alike` (bilgi), `license_incompatible_with_bundle` → blocked, `license_compatibility_unclear` → needs_review | |
| 6 | Aynı kökten sözde bağımsız kanıt | `evidence_not_independent` | needs_review |
| 7 | İnsan onayı gereken içerik | `ai_needs_human_review` (AI `generated/assisted/unknown` ve `human_verified != true`) | needs_review |
| 8 | Eksik sürüm ve kayıt kimliği | `source_version_missing`, `origin_record_missing`, `per_record_license_missing`, `source_inferred` | needs_review |
| 9 | İzin verilmeyen veri aktarımı | `redistribution_not_allowed` (forbidden, evaluation_only, research_only) → blocked; `redistribution_unverified` → needs_review | |
| 10 | Sürümler arası kaynak/lisans kaybı | `provenance_regression`, `origin_record_lost`, `license_regression` → blocked; `record_removed` listelenir | |
| + | Yanlışlıkla `approved` yazılmış kayıt | `false_approval` | blocked |

Bir kaydın durumu bulguların en kötüsüdür: `approved` < `needs_review` < `unknown` < `blocked`. Paket lisansı
varsayılan olarak `CC-BY-SA-4.0`'dır (`--bundle` ile değiştirilebilir; ör. `GPL-3.0-only` senaryosu).

## Raporlar (`--out` klasörü)

| Dosya | İçerik |
|---|---|
| `summary.json` | Toplamlar: duruma, kaynağa, lisansa, tabloya, kural koduna ve AI katkısına göre |
| `by_source.csv`, `by_license.csv`, `by_table.csv` | Kaynak / lisans / tablo bazında kayıt sayıları ve durumlar |
| `unknown_source.csv` | Kaynağı bilinmeyen kayıtlar |
| `publish_unclear.csv` | Yayın uygunluğu belirsiz (`needs_review` + `unknown`) |
| `missing_attribution.csv` | Atıf metni eksik kaynaklardan gelen kayıtlar |
| `ai_contribution.csv` | AI katkılı kayıtlar |
| `conflicts.csv` | Kaynaklar arası çakışmalar (`conflict:` notlu) |
| `high_risk.csv` | `blocked` kayıtlar |
| `regressions.csv` | Önceki sürüme göre kaynak/lisans kaybı, silinen kayıtlar, yanlış onaylar |

CSV dosyaları 200.000 satırla sınırlıdır; tam liste `records.jsonl.gz` içindedir.

## Bugünkü sözlüklerin sonucu (legacy mod, `RAW` ile, 22 Kasım 2026)

| Durum | Kayıt (toplu tablo satırları dahil) |
|---|---:|
| approved | 387.735 |
| needs_review | 832.592 |
| unknown | 119.088 |
| blocked | 104.062 |
| **Toplam** | **1.443.477** |

`release` modunda çalıştırıldığında çıkış kodu **1**'dir: **bugünkü sözlük yeni bir kamuya açık sürüm için kapıdan
geçmiyor.** Ayrıntı: `reports/gate_summary_legacy.json`, `reports/by_*.csv`, `reports/traceability.json`.

Kaynak kaybı tespitinin gerçek veride denenmesi: `RAW` olmadan üretilen kayıtlar, `RAW` ile üretilenlere karşı
`--baseline` ile kontrol edildiğinde kapı 45.983 kaydı `regressions` listesine koydu (KeNet/Wiktionary bağı
kaybolan `syn.tr`, `expr`, `tr_en` "wn" kayıtları) ve çıkış 1 verdi.

## Testler

`python3 -I -m unittest discover -s tools/lexicon_provenance -p 'test_*.py' -v` — 32 test, yalnız sentetik veri ve
geçici minik veritabanları. İstenen testlerin karşılığı:

| İstenen | Test |
|---|---|
| Bilinmeyen lisans engellenir | `test_unknown_license_is_never_approved`, `test_claimed_license_without_data_origin_is_blocked`, `test_fails_with_nonzero_exit` |
| Eksik attribution yakalanır | `test_missing_attribution_is_caught` |
| Aynı kökenden iki kaynak bağımsız sayılmaz | `test_same_root_sources_count_once`, `test_pseudo_independent_evidence_is_flagged`, `test_wiktionary_family_is_one_lineage` |
| Kaynak kimliği kaybolursa uyarı | `test_lost_source_id_warns`, `test_lost_origin_record_warns`, `test_lost_license_warns`, `test_removed_record_is_listed` |
| Yanlışlıkla approved yakalanır | `test_wrongly_approved_record_is_caught`, `test_unknown_and_review_are_never_upgraded` |
| Mevcut sözlük dosyaları değişmez | `test_databases_unchanged_and_records_written` (SHA-256 önce/sonra, salt okunur bağlantıya yazma denemesi hata verir); CI'da gerçek dosyalarla `inventory.json` → `"unchanged": true` |
| Hatalı durumda başarısız çıkış kodu | `test_fails_with_nonzero_exit`, `test_baseline_regression_fails_release`, `test_bad_input_exit_2` |

## CI

`.github/workflows/lexicon-provenance.yml`: ilgili dosyalara dokunan PR'larda ve elle başlatıldığında testleri çalıştırır,
gerçek sözlükler için kayıt üretir (salt okunur), kapıyı **legacy** modda çalıştırır, sonuçları "lexicon-provenance"
artifact'ına ve çalışma özetine yazar. Yayın yapmaz; mevcut `build`, `quality` ve `release` iş akışları değişmedi.

## Yeni sürüm için önerilen akış (bu PR'da bağlanmadı)

1. Yeni sözlük derlenir; derleme betiği her kayıt için provenance alanlarını yazar (REMEDIATION_PLAN.md).
2. `gate.py --mode release --baseline <önceki sürümün records.jsonl.gz>` çalışır.
3. Çıkış 1 ise yayın durur; `high_risk.csv` ve `publish_unclear.csv` incelenir.
4. Çıkış 0 olduktan sonra bugünkü `release.yml` + "production" onayı aynen uygulanır.
