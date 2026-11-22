#!/usr/bin/env python3
"""Per-dictionary traceability numbers from provenance records (inventory.py output).

  python3 -I tools/lexicon_provenance/report.py records.jsonl.gz [--json out.json] [--csv out.csv]

"Content" records are what a reader sees (meanings, definitions, examples,
explanations). "Structural" records are aggregated whole-table rows (sense
order, word families, frequency counts, inflected forms).
"""
import argparse
import csv
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from provenance import Gate, load_registry, read_records  # noqa: E402

UNKNOWN_LICENSES = {'unknown', 'AI-output'}


def summarize(records, reg):
    gate = Gate(reg)
    out = defaultdict(Counter)
    for r in records:
        n = int(r.get('count', 1))
        group = 'structural' if r.get('key') == '*' or (r.get('key') or '').endswith('*') else 'content'
        k = f"{r['db']}|{group}"
        c = out[k]
        c['records'] += n
        origins = [s for s in r.get('sources', []) if s.get('role', 'origin') == 'origin']
        conf = 'unknown'
        if origins and all(s.get('id') != 'unknown' for s in origins):
            conf = 'inferred' if any(s.get('confidence') == 'inferred' for s in origins) else 'exact'
        c['source_' + conf] += n
        if conf != 'unknown' and all(s.get('origin_record') for s in origins):
            c['origin_record_present'] += n
        lic = set(gate.licenses_of(r))
        if lic & UNKNOWN_LICENSES:
            c['license_unknown'] += n
        if len({s.get('id') for s in r.get('sources', [])}) > 1:
            c['multi_source'] += n
        if r.get('ai') in ('generated', 'assisted', 'unknown'):
            c['ai_' + r['ai']] += n
        status, _ = gate.evaluate(r)
        c['status_' + status] += n
    return {k: dict(v) for k, v in sorted(out.items())}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('records')
    ap.add_argument('--registry', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'registry.json'))
    ap.add_argument('--json')
    ap.add_argument('--csv')
    a = ap.parse_args(argv)
    s = summarize(read_records(a.records), load_registry(a.registry))
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as f:
            json.dump(s, f, indent=1)
    if a.csv:
        cols = sorted({c for v in s.values() for c in v})
        with open(a.csv, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f)
            w.writerow(['group'] + cols)
            for k, v in s.items():
                w.writerow([k] + [v.get(c, 0) for c in cols])
    for k, v in s.items():
        tot = v['records']
        pct = lambda x: f'{100 * v.get(x, 0) / tot:.1f}%'  # noqa: E731
        print(f"{k}: {tot} records; exact source {v.get('source_exact', 0)} ({pct('source_exact')}), "
              f"inferred {v.get('source_inferred', 0)} ({pct('source_inferred')}), "
              f"unknown {v.get('source_unknown', 0)} ({pct('source_unknown')}); "
              f"with origin record id {v.get('origin_record_present', 0)} ({pct('origin_record_present')}); "
              f"licence unknown {v.get('license_unknown', 0)}; multi-source {v.get('multi_source', 0)}; "
              f"AI generated {v.get('ai_generated', 0)}, AI assisted {v.get('ai_assisted', 0)}, AI unknown {v.get('ai_unknown', 0)}; "
              f"approved {v.get('status_approved', 0)}, needs_review {v.get('status_needs_review', 0)}, "
              f"unknown {v.get('status_unknown', 0)}, blocked {v.get('status_blocked', 0)}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
