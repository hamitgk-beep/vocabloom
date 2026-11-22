"""Record-level provenance and the licence / publish gate for the Storilex dictionaries.

Only the Python standard library is used. Nothing here writes to a dictionary
database: records come in as JSON lines and decisions go out as reports.

A provenance record (one JSON object per line, see docs/lexicon_provenance/PROVENANCE_SCHEMA.md):

  {"id": "dict.db/ft/bank#0.1", "kind": "translation", "db": "dict.db", "table": "ft",
   "key": "bank", "field": "tr", "count": 1,
   "sources": [{"id": "kindle_en_tr_wiktionary_part", "role": "origin",
                "origin_record": "kindle:bank", "method": "derivation", "confidence": "exact"}],
   "transforms": ["main_meanings.merged"], "ai": "none", "human_verified": null,
   "evidence": [], "claimed_status": null, "notes": []}

Statuses, from best to worst: approved < needs_review < unknown < blocked.
The gate never upgrades a record: unknown and needs_review stay what they are
until a person changes the registry or the record.
"""
import csv
import gzip
import json
import os
from collections import Counter, defaultdict

STATUSES = ('approved', 'needs_review', 'unknown', 'blocked')
RANK = {s: i for i, s in enumerate(STATUSES)}
AI_NEEDS_HUMAN = {'generated', 'assisted', 'unknown'}


def worst(a, b):
    return a if RANK[a] >= RANK[b] else b


def load_registry(path):
    with open(path, encoding='utf-8') as f:
        reg = json.load(f)
    for sid, s in reg['sources'].items():
        for d in s.get('derived_from', []):
            if d not in reg['sources']:
                raise ValueError(f'source {sid}: derived_from {d} is not in the registry')
        for lid in s.get('license_ids', []):
            if lid not in reg['licenses']:
                raise ValueError(f'source {sid}: licence {lid} is not in the registry')
    return reg


def roots(reg, sid, _seen=None):
    """The primary sources a source is ultimately made from (its lineage roots)."""
    src = reg['sources'].get(sid)
    if src is None:
        return {sid}
    _seen = _seen or set()
    if sid in _seen:
        return set()
    _seen.add(sid)
    parents = src.get('derived_from') or []
    if not parents:
        return {sid}
    out = set()
    for p in parents:
        out |= roots(reg, p, _seen)
    return out


def independent_count(reg, source_ids):
    """How many independent confirmations a set of sources gives.

    Sources sharing a lineage root count once (Wiktionary, kaikki and DBnary are
    one). Sources whose evidence_value is "none" (AI output, our own AI-written
    lists) never count: a draft made from the dictionary cannot confirm it."""
    groups = []
    for sid in source_ids:
        src = reg['sources'].get(sid)
        if src is None or src.get('evidence_value') == 'none':
            continue
        r = roots(reg, sid)
        for g in groups:
            if g & r:
                g |= r
                break
        else:
            groups.append(set(r))
    # merge groups that became connected
    merged = True
    while merged:
        merged = False
        for i in range(len(groups)):
            for j in range(i + 1, len(groups)):
                if groups[i] & groups[j]:
                    groups[i] |= groups.pop(j)
                    merged = True
                    break
            if merged:
                break
    return len(groups)


def _finding(code, status, detail=''):
    return {'code': code, 'status': status, 'detail': detail}


def _license_findings(reg, src, sid, bundle):
    out = []
    ls = src.get('license_status', 'unknown')
    if ls in ('missing', 'conflicting'):
        out.append(_finding('license_missing_or_conflicting', 'blocked', f'{sid}: {ls}'))
    elif ls == 'claimed_unverified':
        if src.get('data_origin') != 'known':
            out.append(_finding('license_claim_without_origin', 'blocked',
                                f'{sid}: licence only claimed and data origin unknown'))
        else:
            out.append(_finding('license_unverified', 'needs_review', f'{sid}: licence only claimed'))
    elif ls == 'inherited':
        # A mechanical extraction keeps its roots' licence when every root is verified.
        # A compilation (selection by a third party, possibly under another licence) needs review.
        root_ok = all(reg['sources'].get(r, {}).get('license_status') == 'verified' for r in roots(reg, sid))
        if src.get('kind') != 'extraction' or not root_ok:
            out.append(_finding('license_inherited', 'needs_review', f'{sid}: licence inherited through a compilation'
                                if src.get('kind') != 'extraction' else f'{sid}: a root licence is not verified'))
    elif ls == 'unknown':
        out.append(_finding('license_unknown', 'unknown', f'{sid}: licence unknown'))
    elif ls not in ('verified', 'owner_declared'):
        out.append(_finding('license_status_invalid', 'unknown', f'{sid}: {ls}'))
    if src.get('data_origin') != 'known' and ls != 'claimed_unverified':
        out.append(_finding('data_origin_unknown', 'blocked', sid))
    lid = src.get('license_choice') or (src.get('license_ids') or ['unknown'])[0]
    lic = reg['licenses'].get(lid)
    if lic is None:
        out.append(_finding('license_not_in_registry', 'unknown', f'{sid}: {lid}'))
        return out
    into = lic.get('into_bundle', {}).get(bundle)
    if into is False:
        out.append(_finding('license_incompatible_with_bundle', 'blocked', f'{sid}: {lid} into {bundle}'))
    elif into is None:
        out.append(_finding('license_compatibility_unclear', 'needs_review', f'{sid}: {lid} into {bundle}'))
    if lic.get('non_commercial') or src.get('commercial_use') == 'no':
        out.append(_finding('commercial_use_forbidden', 'blocked', sid))
    elif src.get('commercial_use') != 'yes':
        out.append(_finding('commercial_use_unverified', 'needs_review', sid))
    if lic.get('attribution') and not (src.get('attribution') or '').strip():
        out.append(_finding('attribution_missing', 'blocked', sid))
    if lic.get('share_alike') or lic.get('copyleft'):
        out.append(_finding('obligation_share_alike', 'approved', f'{sid}: {lid}'))
    red = src.get('redistribution', 'unverified')
    if red in ('forbidden', 'evaluation_only', 'research_only'):
        out.append(_finding('redistribution_not_allowed', 'blocked', f'{sid}: {red}'))
    elif red == 'unverified':
        out.append(_finding('redistribution_unverified', 'needs_review', sid))
    if not (src.get('version') or '').strip():
        out.append(_finding('source_version_missing', 'needs_review', sid))
    return out


class Gate:
    """Evaluates records against the registry. bundle: the licence the release is
    published under. baseline: {record id: record} from the previous release."""

    def __init__(self, reg, bundle=None, baseline=None):
        self.reg = reg
        self.bundle = bundle or reg.get('policy', {}).get('bundle_license', 'CC-BY-SA-4.0')
        self.baseline = baseline or {}
        self._cache = {}

    def source_findings(self, sid):
        if sid not in self._cache:
            src = self.reg['sources'].get(sid)
            if src is None:
                self._cache[sid] = [_finding('source_not_in_registry', 'unknown', sid)]
            else:
                self._cache[sid] = _license_findings(self.reg, src, sid, self.bundle)
        return self._cache[sid]

    def evaluate(self, rec):
        findings = []
        origins = [s for s in rec.get('sources', []) if s.get('role', 'origin') == 'origin']
        if not origins:
            findings.append(_finding('source_unknown', 'unknown', 'no origin source'))
        for s in origins:
            sid = s.get('id') or 'unknown'
            if sid == 'unknown' or s.get('confidence') == 'unknown':
                findings.append(_finding('source_unknown', 'unknown', ', '.join(s.get('candidates', [])) or sid))
                if sid == 'unknown':
                    continue
            findings.extend(self.source_findings(sid))
            src = self.reg['sources'].get(sid, {})
            if s.get('confidence') == 'inferred':
                findings.append(_finding('source_inferred', 'needs_review', f'{sid}: {s.get("method", "")}'))
            if not s.get('origin_record'):
                findings.append(_finding('origin_record_missing', 'needs_review', sid))
            if src.get('per_record_license') and not s.get('license_id'):
                findings.append(_finding('per_record_license_missing', 'needs_review', sid))
        ai = rec.get('ai', 'unknown')
        for s in origins:
            src_ai = self.reg['sources'].get(s.get('id'), {}).get('ai')
            if src_ai in AI_NEEDS_HUMAN and ai == 'none':
                ai = src_ai
        if ai in AI_NEEDS_HUMAN and rec.get('human_verified') is not True:
            findings.append(_finding('ai_needs_human_review', 'needs_review', ai))
        ev = list(rec.get('evidence') or [])
        if ev:
            ids = [s.get('id') for s in origins] + ev
            n = independent_count(self.reg, ids)
            claimed = rec.get('claimed_independent', len(set(ids)))
            if n < claimed:
                findings.append(_finding('evidence_not_independent', 'needs_review',
                                         f'{len(set(ids))} sources, {n} independent'))
        base = self.baseline.get(rec.get('id'))
        if base is not None:
            old = {s.get('id') for s in base.get('sources', []) if s.get('id') not in (None, 'unknown')}
            new = {s.get('id') for s in rec.get('sources', [])}
            lost = sorted(old - new)
            if lost:
                findings.append(_finding('provenance_regression', 'blocked', 'lost: ' + ', '.join(lost)))
            old_or = {s.get('id'): s.get('origin_record') for s in base.get('sources', [])}
            for s in rec.get('sources', []):
                if old_or.get(s.get('id')) and not s.get('origin_record'):
                    findings.append(_finding('origin_record_lost', 'blocked', s.get('id')))
            old_lic = set(self.licenses_of(base)) - {'unknown'}
            lost_lic = old_lic - set(self.licenses_of(rec))
            if lost_lic:
                findings.append(_finding('license_regression', 'blocked', ', '.join(sorted(lost_lic))))
        status = 'approved'
        for f in findings:
            status = worst(status, f['status'])
        claimed = rec.get('claimed_status')
        if claimed == 'approved' and status != 'approved':
            findings.append(_finding('false_approval', 'blocked', f'claimed approved, gate says {status}'))
            status = 'blocked'
        return status, findings

    def licenses_of(self, rec):
        out = []
        for s in rec.get('sources', []):
            if s.get('role', 'origin') != 'origin':
                continue
            if s.get('license_id'):
                out.append(s['license_id'])
                continue
            src = self.reg['sources'].get(s.get('id'))
            out.append((src or {}).get('license_choice') or 'unknown')
        return sorted(set(out)) or ['unknown']


def read_records(path):
    op = gzip.open if path.endswith('.gz') else open
    with op(path, 'rt', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)


def write_records(path, records):
    op = gzip.open if path.endswith('.gz') else open
    n = 0
    with op(path, 'wt', encoding='utf-8') as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + '\n')
            n += 1
    return n


CSV_LIMIT = 200000


def run_gate(records, gate, out_dir=None, mode='release'):
    """Evaluates all records. Returns the summary dict; writes JSON and CSV
    reports when out_dir is given. mode 'release': the result fails when any
    record is not approved. mode 'legacy': the same statuses are reported, but the
    existing app content is only described, never failed or removed."""
    by_status = Counter()
    by_source = defaultdict(Counter)
    by_license = defaultdict(Counter)
    by_table = defaultdict(Counter)
    by_finding = Counter()
    ai_counts = Counter()
    lists = defaultdict(list)
    seen_ids = set()
    total = 0
    for rec in records:
        n = int(rec.get('count', 1))
        total += n
        seen_ids.add(rec.get('id'))
        status, findings = gate.evaluate(rec)
        lic = gate.licenses_of(rec)
        by_status[status] += n
        by_table[f"{rec.get('db')}/{rec.get('table')}"][status] += n
        for s in rec.get('sources', []):
            if s.get('role', 'origin') == 'origin':
                by_source[s.get('id', 'unknown')][status] += n
        for l in lic:
            by_license[l][status] += n
        codes = sorted({f['code'] for f in findings})
        for c in codes:
            by_finding[c] += n
        ai = rec.get('ai', 'unknown')
        ai_counts[ai] += n
        row = {'id': rec.get('id'), 'db': rec.get('db'), 'table': rec.get('table'), 'key': rec.get('key'),
               'field': rec.get('field'), 'count': n, 'status': status,
               'sources': ' '.join(s.get('id', '') for s in rec.get('sources', [])),
               'licenses': ' '.join(lic), 'findings': ' '.join(codes),
               'notes': ' | '.join(rec.get('notes') or [])}
        if 'source_unknown' in codes:
            lists['unknown_source'].append(row)
        if status in ('needs_review', 'unknown'):
            lists['publish_unclear'].append(row)
        if 'attribution_missing' in codes:
            lists['missing_attribution'].append(row)
        if ai in AI_NEEDS_HUMAN:
            lists['ai_contribution'].append(row)
        if any(x.startswith('conflict:') for x in rec.get('notes') or []):
            lists['conflicts'].append(row)
        if status == 'blocked':
            lists['high_risk'].append(row)
        if any(c in codes for c in ('provenance_regression', 'license_regression', 'origin_record_lost', 'false_approval')):
            lists['regressions'].append(row)
    removed = [i for i in gate.baseline if i not in seen_ids]
    for i in removed:
        lists['regressions'].append({'id': i, 'status': 'removed', 'findings': 'record_removed'})
    passed = (by_status['approved'] == total) and not lists['regressions']
    summary = {
        'mode': mode, 'bundle_license': gate.bundle, 'records': total,
        'by_status': dict(by_status), 'by_source': {k: dict(v) for k, v in sorted(by_source.items())},
        'by_license': {k: dict(v) for k, v in sorted(by_license.items())},
        'by_table': {k: dict(v) for k, v in sorted(by_table.items())},
        'by_finding': dict(sorted(by_finding.items())), 'ai': dict(ai_counts),
        'list_sizes': {k: sum(int(r.get('count', 1)) for r in v) for k, v in lists.items()},
        'removed_since_baseline': len(removed),
        'release_ok': passed,
    }
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, 'summary.json'), 'w', encoding='utf-8') as f:
            json.dump(summary, f, ensure_ascii=False, indent=1)
        _table_csv(os.path.join(out_dir, 'by_source.csv'), 'source', summary['by_source'])
        _table_csv(os.path.join(out_dir, 'by_license.csv'), 'license', summary['by_license'])
        _table_csv(os.path.join(out_dir, 'by_table.csv'), 'table', summary['by_table'])
        for name in ('unknown_source', 'publish_unclear', 'missing_attribution', 'ai_contribution',
                     'conflicts', 'high_risk', 'regressions'):
            rows = lists.get(name, [])
            with open(os.path.join(out_dir, name + '.csv'), 'w', newline='', encoding='utf-8') as f:
                cols = ['id', 'db', 'table', 'key', 'field', 'count', 'status', 'sources', 'licenses', 'findings', 'notes']
                w = csv.DictWriter(f, cols, extrasaction='ignore')
                w.writeheader()
                for r in rows[:CSV_LIMIT]:
                    w.writerow(r)
    return summary


def _table_csv(path, label, data):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow([label, 'total'] + list(STATUSES))
        for k, c in data.items():
            w.writerow([k, sum(c.values())] + [c.get(s, 0) for s in STATUSES])
