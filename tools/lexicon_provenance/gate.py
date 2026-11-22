#!/usr/bin/env python3
"""Licence and publish gate for a dictionary release. Reads provenance records,
writes reports, never touches a database and never deletes anything.

  python3 -I tools/lexicon_provenance/gate.py --records records.jsonl.gz \
      [--registry tools/lexicon_provenance/registry.json] [--baseline previous.jsonl.gz] \
      [--mode release|legacy] [--bundle CC-BY-SA-4.0] --out report-dir

--mode release  (default) for a new public dictionary version: exit 1 unless
                every record is "approved" and nothing was lost since --baseline.
--mode legacy   describes what the app already ships: same statuses and
                reports, exit 0. It does not approve anything and does not
                remove anything; it only separates "kept in the app for now" from
                "allowed in a new public release".

Exit codes: 0 pass, 1 gate failed, 2 bad input.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from provenance import Gate, load_registry, read_records, run_gate  # noqa: E402

DEFAULT_REGISTRY = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'registry.json')


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--records', required=True)
    ap.add_argument('--registry', default=DEFAULT_REGISTRY)
    ap.add_argument('--baseline')
    ap.add_argument('--mode', choices=('release', 'legacy'), default='release')
    ap.add_argument('--bundle')
    ap.add_argument('--out')
    a = ap.parse_args(argv)
    try:
        reg = load_registry(a.registry)
        baseline = {r['id']: r for r in read_records(a.baseline)} if a.baseline else {}
        gate = Gate(reg, bundle=a.bundle, baseline=baseline)
        summary = run_gate(read_records(a.records), gate, a.out, mode=a.mode)
    except (OSError, ValueError, KeyError) as e:
        print(f'gate: bad input: {e}', file=sys.stderr)
        return 2
    if summary['records'] == 0:
        print('gate: no records', file=sys.stderr)
        return 2
    print(json.dumps({k: summary[k] for k in ('mode', 'bundle_license', 'records', 'by_status', 'list_sizes', 'release_ok')},
                     ensure_ascii=False, indent=1))
    if a.mode == 'legacy':
        print('legacy mode: existing content is reported, not approved and not removed.')
        return 0
    if not summary['release_ok']:
        print('gate: FAILED. A new public release may contain only approved records.', file=sys.stderr)
        return 1
    print('gate: passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
