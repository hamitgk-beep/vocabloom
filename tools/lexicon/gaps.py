"""Gap report: what the candidate store says the dictionaries are missing, grouped across sources.

Read-only on the candidate store. One row per (direction, kind, headword, pos) with the number of sources and
occurrences, the best confidence and the comparison result, so the most widely seen gaps come first:
  word          headwords not in the dictionary
  sense         known headwords used with a word class the dictionary doesn't list (possible new sense)
  phrasal_verb / idiom / collocation   phrases not in the phrase tables
Rejected candidates are left out. Example sentences from private sources (a user's own book) are never
written to the report, only their counts.
"""
import csv
import json

from .safety import check_writable_target

GAP_KINDS = ('word', 'sense', 'phrasal_verb', 'idiom', 'collocation')
GAP_RESULTS = ('new_headword', 'possible_new_sense', 'new_phrase')


def gap_rows(store, *, min_confidence=0.0, direction=None, kinds=GAP_KINDS):
    sql = f'''
        SELECT c.direction, c.kind, c.headword, c.pos, c.compare_result,
               COUNT(DISTINCT c.source_id) AS sources, SUM(c.occurrences) AS occurrences,
               MAX(c.confidence) AS confidence,
               GROUP_CONCAT(DISTINCT s.name) AS source_names,
               MAX(CASE WHEN c.permission != 'private_only' THEN c.example END) AS example,
               MAX(c.compare_detail) AS detail
        FROM candidate_status c JOIN source s ON s.id = c.source_id
        WHERE c.kind IN ({','.join('?' * len(kinds))})
          AND c.compare_result IN ({','.join('?' * len(GAP_RESULTS))})
          AND c.status != 'rejected' AND c.confidence >= ?
          {'AND c.direction = ?' if direction else ''}
        GROUP BY c.direction, c.kind, c.headword, c.pos
        ORDER BY c.direction, c.kind, sources DESC, occurrences DESC, confidence DESC, c.headword'''
    args = list(kinds) + list(GAP_RESULTS) + [min_confidence] + ([direction] if direction else [])
    return [dict(r) for r in store.db.execute(sql, args)]


def _flags(detail):
    try:
        d = json.loads(detail or '{}')
    except ValueError:
        return ''
    out = [k for k in ('compound', 'elided', 'possible_name', 'interjection') if d.get(k)]
    if d.get('dictionary_pos'):
        out.append('dictionary_pos=' + ''.join(d['dictionary_pos']))
    return ' '.join(out + d.get('sentence_flags', []))


def write_report(store, out_path, *, min_confidence=0.3, direction=None, limit=200):
    """Writes <out>.tsv (every row) and <out>.md (the top `limit` rows per kind). Returns {kind: rows}."""
    base = out_path[:-3] if out_path.endswith('.md') else out_path
    rows = gap_rows(store, min_confidence=min_confidence, direction=direction)
    tsv = check_writable_target(base + '.tsv')
    md = check_writable_target(base + '.md')
    cols = ['direction', 'kind', 'headword', 'pos', 'compare_result', 'sources', 'occurrences', 'confidence',
            'source_names', 'flags', 'example']
    with open(tsv, 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f, delimiter='\t')
        w.writerow(cols)
        for r in rows:
            w.writerow([r[c] if c != 'flags' else _flags(r['detail']) for c in cols[:-1]] + [r['example'] or ''])
    counts = {}
    for r in rows:
        counts[(r['direction'], r['kind'])] = counts.get((r['direction'], r['kind']), 0) + 1
    with open(md, 'w', encoding='utf-8') as f:
        f.write(f'# Sözlük eksikleri raporu\n\nAday veritabanından, güven ≥ {min_confidence}. Reddedilenler hariç. '
                'Bu liste bir çalışma listesidir: her satır bir kişi tarafından incelenmeden sözlüğe girmez.\n\n')
        for (d, kind), n in counts.items():
            f.write(f'## {d} · {kind} ({n})\n\n| headword | pos | kaynak | geçiş | güven | işaret | örnek |\n'
                    '|---|---|---|---|---|---|---|\n')
            for r in [r for r in rows if r['direction'] == d and r['kind'] == kind][:limit]:
                ex = (r['example'] or '').replace('|', '\\|')[:120]
                f.write(f"| {r['headword']} | {r['pos'] or ''} | {r['sources']} | {r['occurrences']} | "
                        f"{r['confidence']} | {_flags(r['detail'])} | {ex} |\n")
            f.write('\n')
    return {f'{d}|{k}': n for (d, k), n in counts.items()}
