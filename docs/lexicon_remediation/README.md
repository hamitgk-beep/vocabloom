# Sözlük lisans düzeltmeleri (Görev 5D)

5C denetiminin (`docs/lexicon_provenance/`) bulgularını gidermek için yapılanlar. Hukuki görüş değildir.
`assets/dict.db` ve `assets/tr_en.db` **değiştirilmedi**; aday sözlük depoya konmadı.

| Belge | İçerik |
|---|---|
| [BASELINE_AND_SHA.md](BASELINE_AND_SHA.md) | Yayın / main / aday: SHA'lar, tablo sayıları, 5C sayılarının yeniden üretimi |
| [LICENSE_TEXT_CORRECTIONS.md](LICENSE_TEXT_CORRECTIONS.md) | Uygulamadaki lisans metinleri, WordNet bildirimi, "fd" etiketi |
| [DAMDAFAYTON_PROVENANCE.md](DAMDAFAYTON_PROVENANCE.md) | Köken araştırması, çift sayım, e-posta taslağı (gönderilmedi) |
| [SOURCE_REPLACEMENT_MATRIX.md](SOURCE_REPLACEMENT_MATRIX.md) | Güvenli alternatif kaynaklar |
| [SAFE_DICTIONARY_BUILD.md](SAFE_DICTIONARY_BUILD.md) | Aday derleme hattı, karantina, bütünlük |
| [COVERAGE_AND_QUALITY_IMPACT.md](COVERAGE_AND_QUALITY_IMPACT.md) | Kazanç / kayıp, aday veriyle uygulama testleri |
| [TATOEBA_ATTRIBUTION_PLAN.md](TATOEBA_ATTRIBUTION_PLAN.md) | Cümle kimliği, yazar, lisans; kaldırma süreci |
| [RELEASE_GATE_INTEGRATION.md](RELEASE_GATE_INTEGRATION.md) | release.yml içindeki sözlük kapısı |
| [REMAINING_LEGAL_RISKS.md](REMAINING_LEGAL_RISKS.md) | Kalan riskler |
| [NEXT_STEPS_TR.md](NEXT_STEPS_TR.md) | Sonraki adımlar ve onay noktaları |
| [reports/](reports/) | Aday derleme raporu, etki, aday kapı özetleri |

Araçlar: `tools/lexicon_remediation/` (`release_gate.py`, `dictionary_manifest.json`, `build_candidate.py`,
`check_candidate.py`, `tatoeba_ids.py`, testler). Testler: `python3 -I -m unittest discover -s
tools/lexicon_remediation -p 'test_*.py' -v`.
