# Sözlük kaynak izlenebilirliği ve lisans güvenliği (Görev 5C)

Bu klasör, Storilex sözlüklerinin (`assets/dict.db`, `assets/tr_en.db`) kaynak ve lisans denetimidir.
Sözlük dosyaları, uygulama arayüzü, SenseEngine ve yayın mekanizması **değiştirilmedi**. Hukuki görüş değildir.

| Belge | İçerik |
|---|---|
| [SOURCE_INVENTORY.md](SOURCE_INVENTORY.md) | Her sözlüğün kayıt sayıları, kaynaklar, sürümler, izlenebilirlik oranları |
| [LICENSE_AUDIT.md](LICENSE_AUDIT.md) | damdafayton, FreeDict, Kindle, Tatoeba, Wiktionary/kaikki, KeNet ve diğerleri; kanıtlarıyla |
| [PROVENANCE_SCHEMA.md](PROVENANCE_SCHEMA.md) | Kayıt düzeyinde provenance alanları, kaynak soy ağacı, SenseEngine ile ilişki |
| [PUBLISH_GATE.md](PUBLISH_GATE.md) | Yayın kapısı kuralları, raporlar, testler, CI |
| [ATTRIBUTION_PLAN.md](ATTRIBUTION_PLAN.md) | Lisans ekranı düzeltmeleri, kaynak sayfası taslağı, zorunlu atıflar |
| [REMEDIATION_PLAN.md](REMEDIATION_PLAN.md) | Öncelik sırasıyla düzeltilecek lisans sorunları |
| [reports/](reports/) | 22 Kasım 2026 çalıştırmasının özetleri (JSON/CSV) |

Araçlar: `tools/lexicon_provenance/` (`inventory.py`, `gate.py`, `report.py`, `registry.json`, testler).
Görev 5A araştırması (`f53da4d`, `docs/lexicon_research/`) referans olarak kullanıldı; dosyaları buraya kopyalanmadı.
