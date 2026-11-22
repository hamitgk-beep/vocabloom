#!/usr/bin/env python3
"""Dictionary release gate (Task 5D, docs/lexicon_remediation/RELEASE_GATE_INTEGRATION.md).

release.yml runs this on the real build files before the "publish" job can
start. It reads the dictionaries that are inside the build artifacts, not the
files in the repository and not the result of any earlier CI run, and stops
the release unless they are allowed by tools/lexicon_remediation/dictionary_manifest.json:

  python3 -I tools/lexicon_remediation/release_gate.py check --dist DIST --src SRC \
      --manifest MANIFEST --owner OWNER [--today YYYY-MM-DD] [--out DIR] [--github-output FILE]
  python3 -I tools/lexicon_remediation/release_gate.py same-dbs --dist DIST --dict-sha X --tr-en-sha Y
  python3 -I tools/lexicon_remediation/release_gate.py check-workflow .github/workflows/release.yml

check
  1. Every build artifact (Storilex-Windows, -Android, -iOS, -macOS, -Linux) holds
     flutter_assets/assets/dict.db and tr_en.db, also inside .apk / .ipa / .zip / .tar.gz,
     and all copies are byte-identical to SRC/assets (the release commit).
  2. The SHA-256 pair has an entry in the manifest, and the table row counts of
     the real files equal the counts written in that entry.
  3. The entry's decision:
       "gate"              its provenance records (sha-checked) cover every
                           non-empty table and pass gate --mode release
                           (every record approved, no regression against its
                           baseline). The mode cannot be changed here.
       "legacy_exception"  an exception for dictionaries that were already
                           published: it needs a reason, a document, the
                           repository owner as approved_by, an approval date and
                           an end date that has not passed. It is printed as a
                           warning and in the run summary on every release.
     Anything else (no entry, "legacy_exception_proposed", missing fields) fails.
same-dbs
  The publish job checks that the files it packages hold the same dictionaries
  the gate checked.
check-workflow
  release.yml still runs the gate before publish and cannot skip it.

Exit codes: 0 allowed, 1 refused, 2 bad input. Only the standard library is used.
Nothing here writes to a dictionary or publishes anything.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import sqlite3
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'lexicon_provenance'))
from provenance import Gate, load_registry, read_records, run_gate  # noqa: E402

ARTIFACTS = ('Storilex-Windows', 'Storilex-Android', 'Storilex-iOS', 'Storilex-macOS', 'Storilex-Linux')
DBS = ('dict.db', 'tr_en.db')
ASSET_PATH = re.compile(r'(^|/)flutter_assets/assets/(dict\.db|tr_en\.db)$')
ARCHIVES = ('.apk', '.ipa', '.zip', '.aab')
DECISIONS = ('gate', 'legacy_exception', 'legacy_exception_proposed')
EXEMPT_TABLES = {'meta'}  # build metadata, not dictionary content


class Refused(Exception):
    pass


def _sha_stream(f):
    h = hashlib.sha256()
    for chunk in iter(lambda: f.read(1 << 20), b''):
        h.update(chunk)
    return h.hexdigest()


def sha256(path):
    with open(path, 'rb') as f:
        return _sha_stream(f)


# ------------------------------------------------------------ finding the files

def find_dbs(dist, keep_dir=None):
    """{artifact: {db: set(sha)}} for the dictionaries inside each artifact.
    With keep_dir, one copy of every distinct file is written there as
    <sha>.db, so it can be opened read-only afterwards."""
    found = {}
    for art in ARTIFACTS:
        root = os.path.join(dist, art)
        if not os.path.isdir(root):
            raise Refused(f'build artifact {art} is missing')
        hits = {db: set() for db in DBS}

        def keep(sha, reader):
            if keep_dir and not os.path.exists(os.path.join(keep_dir, sha + '.db')):
                tmp = os.path.join(keep_dir, sha + '.part')
                with reader() as f, open(tmp, 'wb') as out:
                    shutil.copyfileobj(f, out, 1 << 20)
                os.replace(tmp, os.path.join(keep_dir, sha + '.db'))

        for dirpath, _, files in os.walk(root):
            for name in files:
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, root).replace(os.sep, '/')
                m = ASSET_PATH.search(rel)
                if m:
                    s = sha256(path)
                    hits[m.group(2)].add(s)
                    keep(s, lambda p=path: open(p, 'rb'))
                elif name.endswith(ARCHIVES) and zipfile.is_zipfile(path):
                    with zipfile.ZipFile(path) as z:
                        for info in z.infolist():
                            m = ASSET_PATH.search(info.filename)
                            if m:
                                with z.open(info) as f:
                                    s = _sha_stream(f)
                                hits[m.group(2)].add(s)
                                keep(s, lambda i=info, zz=z: zz.open(i))
                elif name.endswith(('.tar.gz', '.tgz')):
                    with tarfile.open(path) as t:
                        for member in t:
                            m = ASSET_PATH.search(member.name)
                            if m and member.isfile():
                                s = _sha_stream(t.extractfile(member))
                                hits[m.group(2)].add(s)
                                keep(s, lambda mm=member, tt=t: tt.extractfile(mm))
        found[art] = hits
    return found


def one_pair(found, src_shas):
    """The single (dict sha, tr_en sha) every artifact carries; refuses otherwise."""
    pair = {}
    for db in DBS:
        shas = set()
        for art, hits in found.items():
            if not hits[db]:
                raise Refused(f'{art} has no flutter_assets/assets/{db}')
            shas |= hits[db]
        if len(shas) != 1:
            raise Refused(f'the build artifacts carry {len(shas)} different {db} files: {sorted(shas)}')
        pair[db] = shas.pop()
        if src_shas is not None and pair[db] != src_shas[db]:
            raise Refused(f'{db} in the build ({pair[db]}) is not assets/{db} of the release commit ({src_shas[db]})')
    return pair


# ------------------------------------------------------------ database facts

def table_counts(path):
    con = sqlite3.connect(f'file:{path}?mode=ro&immutable=1', uri=True)
    try:
        names = [n for (n,) in con.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        return {n: con.execute(f'SELECT count(*) FROM "{n}"').fetchone()[0] for n in names}
    finally:
        con.close()


# ------------------------------------------------------------ the manifest

def load_manifest(path):
    with open(path, encoding='utf-8') as f:
        m = json.load(f)
    if m.get('schema') != 1 or not isinstance(m.get('entries'), list):
        raise ValueError('manifest: schema 1 with an "entries" list expected')
    for e in m['entries']:
        if e.get('decision') not in DECISIONS:
            raise ValueError(f'manifest entry {e.get("name")!r}: decision must be one of {DECISIONS}')
        for db in DBS:
            if not re.fullmatch(r'[0-9a-f]{64}', (e.get(db) or {}).get('sha256', '')):
                raise ValueError(f'manifest entry {e.get("name")!r}: {db}.sha256 missing')
    return m


def entry_for(manifest, pair):
    hits = [e for e in manifest['entries'] if all(e[db]['sha256'] == pair[db] for db in DBS)]
    if not hits:
        raise Refused('these dictionaries (dict.db %s, tr_en.db %s) have no entry in the dictionary manifest; '
                      'a new dictionary needs provenance records that pass the release gate' % (pair['dict.db'], pair['tr_en.db']))
    if len(hits) > 1:
        raise Refused('the dictionary manifest lists these dictionaries more than once')
    return hits[0]


def check_counts(entry, counts):
    for db in DBS:
        want = entry[db].get('tables')
        if not want:
            raise Refused(f'manifest entry {entry["name"]!r} has no table counts for {db}')
        if want != counts[db]:
            diff = sorted(set(want) | set(counts[db]))
            d = ', '.join(f'{t}: {want.get(t)} vs {counts[db].get(t)}' for t in diff if want.get(t) != counts[db].get(t))
            raise Refused(f'{db} table counts differ from the manifest ({d})')


def check_exception(entry, owner, today):
    ex = entry.get('exception') or {}
    missing = [k for k in ('reason', 'doc', 'approved_by', 'approved_on', 'expires_on', 'published_in') if not str(ex.get(k) or '').strip()]
    if missing:
        raise Refused(f'exception {entry["name"]!r} is not complete: {", ".join(missing)} empty')
    if ex['approved_by'] != owner:
        raise Refused(f'exception {entry["name"]!r} must be approved by the repository owner {owner}, not {ex["approved_by"]}')
    try:
        approved = dt.date.fromisoformat(ex['approved_on'])
        expires = dt.date.fromisoformat(ex['expires_on'])
    except ValueError:
        raise Refused(f'exception {entry["name"]!r}: approved_on / expires_on must be YYYY-MM-DD')
    if approved > today:
        raise Refused(f'exception {entry["name"]!r} is approved in the future ({approved})')
    if expires < today:
        raise Refused(f'exception {entry["name"]!r} ended on {expires}')
    return ex


def fetch(ref, src, work):
    """A provenance file named in the manifest: a path in the release commit or an https URL."""
    if re.match(r'https://', ref):
        out = os.path.join(work, 'records' + ('.jsonl.gz' if ref.endswith('.gz') else '.jsonl'))
        with urllib.request.urlopen(ref, timeout=120) as r, open(out, 'wb') as f:
            shutil.copyfileobj(r, f, 1 << 20)
        return out
    path = os.path.normpath(os.path.join(src, ref))
    if not path.startswith(os.path.abspath(src) + os.sep):
        raise Refused(f'provenance path {ref} is outside the release commit')
    return path


def check_gate(entry, counts, src, work, out_dir):
    p = entry.get('provenance') or {}
    if not p.get('records') or not re.fullmatch(r'[0-9a-f]{64}', p.get('sha256', '')):
        raise Refused(f'entry {entry["name"]!r} has decision "gate" but no provenance records with a sha256')
    path = fetch(p['records'], src, work)
    if sha256(path) != p['sha256']:
        raise Refused('the provenance records do not match the sha256 in the manifest')
    registry = load_registry(os.path.join(src, p.get('registry', 'tools/lexicon_provenance/registry.json')))
    baseline = {}
    if p.get('baseline'):
        bpath = fetch(p['baseline'], src, work)
        if p.get('baseline_sha256') and sha256(bpath) != p['baseline_sha256']:
            raise Refused('the baseline records do not match baseline_sha256')
        baseline = {r['id']: r for r in read_records(bpath)}
    covered = set()

    def recs():
        for r in read_records(path):
            covered.add((r.get('db'), r.get('table')))
            yield r

    summary = run_gate(recs(), Gate(registry, bundle=p.get('bundle'), baseline=baseline), out_dir, mode='release')
    bare = [f'{db}/{t}' for db in DBS for t, n in counts[db].items()
            if n and t not in EXEMPT_TABLES and (db, t) not in covered]
    if bare:
        raise Refused('tables without provenance records: ' + ', '.join(bare))
    if summary['records'] == 0:
        raise Refused('the provenance file holds no records')
    if not summary['release_ok']:
        raise Refused('gate --mode release failed: %s (regressions: %d)' % (
            json.dumps(summary['by_status'], sort_keys=True), summary['list_sizes'].get('regressions', 0)))
    return summary


def check(dist, src, manifest_path, owner, today, out_dir=None):
    """Returns (pair, report lines). Raises Refused when the release must stop."""
    src_shas = {db: sha256(os.path.join(src, 'assets', db)) for db in DBS}
    work = tempfile.mkdtemp(prefix='dict-gate-')
    try:
        found = find_dbs(dist, keep_dir=work)
        pair = one_pair(found, src_shas)
        counts = {db: table_counts(os.path.join(work, pair[db] + '.db')) for db in DBS}
        entry = entry_for(load_manifest(manifest_path), pair)
        check_counts(entry, counts)
        lines = [f'{db}: {pair[db]} ({sum(counts[db].values())} rows in {len(counts[db])} tables)' for db in DBS]
        if entry['decision'] == 'gate':
            s = check_gate(entry, counts, src, work, out_dir)
            lines.append(f'provenance gate (release mode) passed: {s["records"]} records, all approved')
        elif entry['decision'] == 'legacy_exception':
            ex = check_exception(entry, owner, today)
            lines.append(f'WARNING: released under the exception "{entry["name"]}", approved by {ex["approved_by"]} '
                         f'on {ex["approved_on"]}, ends {ex["expires_on"]}: {ex["reason"]} ({ex["doc"]}). '
                         'These dictionaries do NOT pass the licence gate.')
        else:
            raise Refused(f'entry {entry["name"]!r} is only a proposed exception; the owner has not approved it '
                          f'({(entry.get("exception") or {}).get("doc", "")})')
        return pair, lines
    finally:
        shutil.rmtree(work, ignore_errors=True)


# ------------------------------------------------------------ release.yml shape

def _jobs(text):
    """{job: block text} of a workflow, by indentation (no YAML library on the runner)."""
    m = re.search(r'^jobs:\s*\n', text, re.M)
    if not m:
        return {}
    body = text[m.end():]
    jobs, cur, buf = {}, None, []
    for line in body.splitlines():
        jm = re.match(r'^  ([A-Za-z0-9_-]+):\s*$', line)
        if jm:
            if cur:
                jobs[cur] = '\n'.join(buf)
            cur, buf = jm.group(1), []
        elif re.match(r'^\S', line):
            break
        else:
            buf.append(line)
    if cur:
        jobs[cur] = '\n'.join(buf)
    return jobs


def _needs(block):
    m = re.search(r'^    needs:\s*(.+)$', block, re.M)
    if not m:
        return []
    return [x.strip() for x in m.group(1).strip().strip('[]').split(',') if x.strip()]


def check_workflow(path):
    with open(path, encoding='utf-8') as f:
        text = f.read()
    jobs = _jobs(text)
    problems = []
    gate, pub = jobs.get('dictionary-gate'), jobs.get('publish')
    if gate is None:
        problems.append('release.yml has no dictionary-gate job')
    if pub is None:
        problems.append('release.yml has no publish job')
    if gate is not None and pub is not None:
        if 'dictionary-gate' not in _needs(pub):
            problems.append('publish does not need dictionary-gate')
        if 'prepare' not in _needs(gate):
            problems.append('dictionary-gate does not need prepare')
        if re.search(r'^    if:', pub, re.M):
            problems.append('publish has a job-level "if:", which could run it after a skipped or failed gate')
        if re.search(r'^    (if|continue-on-error):', gate, re.M) or re.search(r'continue-on-error:\s*true', gate):
            problems.append('dictionary-gate can be skipped or can fail without stopping the release')
        if 'release_gate.py check ' not in gate and 'release_gate.py check\\' not in gate:
            problems.append('dictionary-gate does not run release_gate.py check')
        step = gate[gate.find('release_gate.py check '):] if 'release_gate.py check ' in gate else ''
        if re.search(r'\|\|\s*(true|:|exit 0)|;\s*true\b|set \+e', step) or \
                ('|' in step.replace('||', '') and 'pipefail' not in gate):
            problems.append('the result of release_gate.py check is ignored (|| true, set +e, or a pipe without pipefail)')
        if 'release_gate.py same-dbs' not in pub:
            problems.append('publish does not check that it packages the dictionaries the gate checked')
        if re.search(r'environment:\s*production', gate):
            problems.append('dictionary-gate must run before the production approval, not inside it')
        if not re.search(r'^    environment:\s*production', pub, re.M):
            problems.append('publish lost its production environment (required reviewer)')
    if 'YAYINLA' not in (jobs.get('prepare') or ''):
        problems.append('prepare no longer asks for YAYINLA')
    if re.search(r'--mode\s+legacy', text) or re.search(r'lexicon-provenance', text):
        problems.append('release.yml must not use the legacy report or a lexicon-provenance run as approval')
    if problems:
        raise Refused('; '.join(problems))


# ------------------------------------------------------------ CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('check')
    c.add_argument('--dist', required=True)
    c.add_argument('--src', required=True)
    c.add_argument('--manifest', required=True)
    c.add_argument('--owner', required=True)
    c.add_argument('--today')
    c.add_argument('--out')
    c.add_argument('--github-output')
    s = sub.add_parser('same-dbs')
    s.add_argument('--dist', required=True)
    s.add_argument('--dict-sha', required=True)
    s.add_argument('--tr-en-sha', required=True)
    w = sub.add_parser('check-workflow')
    w.add_argument('path')
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'check':
            today = dt.date.fromisoformat(a.today) if a.today else dt.datetime.now(dt.timezone.utc).date()
            pair, lines = check(a.dist, a.src, a.manifest, a.owner, today, a.out)
            for line in lines:
                print(('::warning::' + line) if line.startswith('WARNING') else line)
            if a.github_output:
                with open(a.github_output, 'a', encoding='utf-8') as f:
                    f.write(f'dict_sha={pair["dict.db"]}\ntr_en_sha={pair["tr_en.db"]}\n')
            print('dictionary gate: allowed')
        elif a.cmd == 'same-dbs':
            pair = one_pair(find_dbs(a.dist), None)
            if pair != {'dict.db': a.dict_sha, 'tr_en.db': a.tr_en_sha}:
                raise Refused(f'the files to publish carry other dictionaries than the gate checked: {pair}')
            print('the files to publish carry the dictionaries the gate checked')
        else:
            check_workflow(a.path)
            print('release.yml runs the dictionary gate before publish')
    except Refused as e:
        print(f'::error::dictionary gate: {e}')
        return 1
    except (OSError, ValueError, KeyError, sqlite3.Error) as e:
        print(f'::error::dictionary gate: bad input: {e}')
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
