"""Synthetic tests of the dictionary release gate (release_gate.py) and of its
place in release.yml. No real dictionary, user data or network is used.

  python3 -I -m unittest discover -s tools/lexicon_remediation -p 'test_*.py' -v
"""
import datetime as dt
import gzip
import io
import json
import os
import re
import shutil
import sqlite3
import sys
import tarfile
import tempfile
import unittest
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import release_gate as g  # noqa: E402

TODAY = dt.date(2026, 11, 22)
OWNER = 'owner-x'
WORKFLOW = os.path.join(REPO, '.github', 'workflows', 'release.yml')


def make_db(path, tables):
    con = sqlite3.connect(path)
    for t, rows in tables.items():
        con.execute(f'CREATE TABLE {t}(k TEXT, v TEXT)')
        con.executemany(f'INSERT INTO {t} VALUES (?,?)', rows)
    con.commit()
    con.close()


def rec(db, table, key, source='princeton_wordnet', ai='none'):
    return {'id': f'{db}/{table}/{key}', 'db': db, 'table': table, 'key': key, 'field': 'v', 'kind': 'translation',
            'sources': [{'id': source, 'role': 'origin', 'origin_record': f'{source}:{key}', 'method': 'build_rule',
                         'confidence': 'exact'}],
            'ai': ai, 'human_verified': None, 'count': 1}


class Fixture(unittest.TestCase):
    """A release commit (src/assets), five build artifacts and a manifest."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.src = os.path.join(self.tmp, 'src')
        os.makedirs(os.path.join(self.src, 'assets'))
        shutil.copytree(os.path.join(REPO, 'tools', 'lexicon_provenance'), os.path.join(self.src, 'tools', 'lexicon_provenance'),
                        ignore=shutil.ignore_patterns('__pycache__'))
        self.dict = os.path.join(self.src, 'assets', 'dict.db')
        self.tr = os.path.join(self.src, 'assets', 'tr_en.db')
        make_db(self.dict, {'meta': [('v', '1')], 'ft': [('book', 'kitap'), ('dog', 'köpek')], 'wd': []})
        make_db(self.tr, {'meta': [('v', '1')], 'lemma': [('kitap', 'book')]})
        self.dist = os.path.join(self.tmp, 'dist')
        self.build_dist()
        self.records = [rec('dict.db', 'ft', 'book'), rec('dict.db', 'ft', 'dog'), rec('tr_en.db', 'lemma', 'kitap')]
        self.manifest = os.path.join(self.tmp, 'manifest.json')
        self.entry = {'name': 'test', 'decision': 'gate'}
        self.write_manifest()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def build_dist(self, android_dict=None, skip=None):
        shutil.rmtree(self.dist, ignore_errors=True)
        a = 'flutter_assets/assets/'
        for art, base in (('Storilex-Windows', 'data/'), ('Storilex-Linux', 'data/'),
                          ('Storilex-macOS', 'Contents/Frameworks/App.framework/Resources/')):
            d = os.path.join(self.dist, art, base + a)
            os.makedirs(d)
            for db in ('dict.db', 'tr_en.db'):
                if (art, db) != skip:
                    shutil.copy(os.path.join(self.src, 'assets', db), d)
        for art, name, base in (('Storilex-Android', 'app-release.apk', 'assets/'),
                                ('Storilex-iOS', 'Storilex-unsigned.ipa', 'Payload/Runner.app/Frameworks/App.framework/')):
            os.makedirs(os.path.join(self.dist, art))
            with zipfile.ZipFile(os.path.join(self.dist, art, name), 'w', zipfile.ZIP_DEFLATED) as z:
                z.writestr('AndroidManifest.xml', 'x')
                for db in ('dict.db', 'tr_en.db'):
                    if (art, db) == skip:
                        continue
                    p = android_dict if (art == 'Storilex-Android' and db == 'dict.db' and android_dict) else os.path.join(self.src, 'assets', db)
                    z.write(p, base + a + db)

    def write_records(self, records=None):
        path = os.path.join(self.src, 'prov', 'records.jsonl.gz')
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with gzip.open(path, 'wt', encoding='utf-8') as f:
            for r in (self.records if records is None else records):
                f.write(json.dumps(r) + '\n')
        return 'prov/records.jsonl.gz', g.sha256(path)

    def write_manifest(self, **entry):
        e = dict(self.entry, **entry)
        for db, path in (('dict.db', self.dict), ('tr_en.db', self.tr)):
            e.setdefault(db, {'sha256': g.sha256(path), 'tables': g.table_counts(path)})
        if e['decision'] == 'gate' and 'provenance' not in e:
            ref, sha = self.write_records()
            e['provenance'] = {'records': ref, 'sha256': sha}
        with open(self.manifest, 'w') as f:
            json.dump({'schema': 1, 'entries': [e]}, f)

    def run_check(self):
        return g.check(self.dist, self.src, self.manifest, OWNER, TODAY, os.path.join(self.tmp, 'out'))

    def refused(self, pattern):
        with self.assertRaises(g.Refused) as c:
            self.run_check()
        self.assertRegex(str(c.exception), pattern)


class Artifacts(Fixture):
    def test_finds_every_copy(self):
        found = g.find_dbs(self.dist)
        self.assertEqual(set(found), set(g.ARTIFACTS))
        pair = g.one_pair(found, {'dict.db': g.sha256(self.dict), 'tr_en.db': g.sha256(self.tr)})
        self.assertEqual(pair['dict.db'], g.sha256(self.dict))

    def test_missing_artifact(self):
        shutil.rmtree(os.path.join(self.dist, 'Storilex-iOS'))
        self.refused('Storilex-iOS is missing')

    def test_artifact_without_dictionary(self):
        self.build_dist(skip=('Storilex-Android', 'tr_en.db'))
        self.refused('Storilex-Android has no .*tr_en.db')

    def test_artifacts_with_different_dictionaries(self):
        other = os.path.join(self.tmp, 'other.db')
        make_db(other, {'meta': [('v', '2')], 'ft': [('book', 'defter')]})
        self.build_dist(android_dict=other)
        self.refused('2 different dict.db')

    def test_build_is_not_the_release_commit(self):
        con = sqlite3.connect(self.dict)
        con.execute("INSERT INTO ft VALUES ('cat', 'kedi')")
        con.commit()
        con.close()
        self.refused('is not assets/dict.db of the release commit')

    def test_packaged_tar_and_zip_are_read_too(self):
        # The same check works on packaged files (release_files.txt names).
        lin = os.path.join(self.dist, 'Storilex-Linux')
        buf = os.path.join(self.tmp, 'l.tar.gz')
        with tarfile.open(buf, 'w:gz') as t:
            t.add(lin, arcname='.')
        shutil.rmtree(lin)
        os.makedirs(lin)
        shutil.move(buf, os.path.join(lin, 'Storilex-Linux.tar.gz'))
        self.assertEqual(len(g.find_dbs(self.dist)['Storilex-Linux']['dict.db']), 1)

    def test_same_dbs(self):
        d, t = g.sha256(self.dict), g.sha256(self.tr)
        self.assertEqual(g.main(['same-dbs', '--dist', self.dist, '--dict-sha', d, '--tr-en-sha', t]), 0)
        self.assertEqual(g.main(['same-dbs', '--dist', self.dist, '--dict-sha', '0' * 64, '--tr-en-sha', t]), 1)


class Manifest(Fixture):
    def test_gate_pass(self):
        pair, lines = self.run_check()
        self.assertIn('all approved', lines[-1])

    def test_unknown_dictionary(self):
        self.write_manifest(**{'dict.db': {'sha256': '1' * 64, 'tables': {}}})
        self.refused('no entry in the dictionary manifest')

    def test_counts_must_match_the_real_file(self):
        t = g.table_counts(self.dict)
        t['ft'] = 99
        self.write_manifest(**{'dict.db': {'sha256': g.sha256(self.dict), 'tables': t}})
        self.refused('table counts differ.*ft: 99 vs 2')

    def test_blocked_record_fails(self):
        self.records[1] = rec('dict.db', 'ft', 'dog', source='damdafayton')
        self.write_manifest()
        self.refused('gate --mode release failed.*blocked')

    def test_needs_review_fails(self):
        self.records[1] = rec('dict.db', 'ft', 'dog', source='tatoeba')
        self.write_manifest()
        self.refused('gate --mode release failed')

    def test_ai_output_is_not_approved(self):
        self.records[1] = rec('dict.db', 'ft', 'dog', source='ai_pretranslate', ai='generated')
        self.write_manifest()
        self.refused('gate --mode release failed')

    def test_table_without_records(self):
        self.records = self.records[:2]
        self.write_manifest()
        self.refused('tables without provenance records: tr_en.db/lemma')

    def test_records_changed_after_the_manifest(self):
        self.write_manifest()
        self.write_records([rec('dict.db', 'ft', 'x')])
        self.refused('do not match the sha256')

    def test_gate_without_records(self):
        self.write_manifest(provenance={})
        self.refused('no provenance records')

    def test_records_outside_the_release_commit(self):
        self.write_manifest(provenance={'records': '../../etc/passwd', 'sha256': '0' * 64})
        self.refused('outside the release commit')

    def test_lost_records_since_baseline(self):
        ref, sha = self.write_records()
        base = os.path.join(self.src, 'prov', 'base.jsonl')
        with open(base, 'w') as f:
            for r in self.records + [rec('dict.db', 'ft', 'cat')]:
                f.write(json.dumps(r) + '\n')
        self.write_manifest(provenance={'records': ref, 'sha256': sha, 'baseline': 'prov/base.jsonl'})
        self.refused('regressions: 1')

    def test_bad_decision_is_bad_input(self):
        self.write_manifest(decision='approved')
        out = os.path.join(self.tmp, 'o')
        self.assertEqual(g.main(['check', '--dist', self.dist, '--src', self.src, '--manifest', self.manifest,
                                 '--owner', OWNER, '--today', '2026-11-22', '--out', out]), 2)


class Exception_(Fixture):
    def ex(self, **kw):
        e = {'reason': 'published before', 'doc': 'docs/x.md', 'approved_by': OWNER, 'approved_on': '2026-11-20',
             'expires_on': '2027-01-31', 'published_in': 'latest @ abc'}
        e.update(kw)
        return e

    def test_proposed_exception_stops_the_release(self):
        self.write_manifest(decision='legacy_exception_proposed', exception=self.ex(approved_by='', approved_on=''))
        self.refused('only a proposed exception')

    def test_approved_exception_is_loud(self):
        self.write_manifest(decision='legacy_exception', exception=self.ex())
        pair, lines = self.run_check()
        self.assertTrue(lines[-1].startswith('WARNING'))
        self.assertIn('do NOT pass the licence gate', lines[-1])

    def test_exception_needs_every_field(self):
        for k in ('reason', 'doc', 'approved_by', 'approved_on', 'expires_on', 'published_in'):
            self.write_manifest(decision='legacy_exception', exception=self.ex(**{k: ''}))
            self.refused(k)

    def test_exception_only_from_the_owner(self):
        self.write_manifest(decision='legacy_exception', exception=self.ex(approved_by='someone-else'))
        self.refused('repository owner')

    def test_expired_exception(self):
        self.write_manifest(decision='legacy_exception', exception=self.ex(expires_on='2026-11-21'))
        self.refused('ended on')

    def test_exception_dated_in_the_future(self):
        self.write_manifest(decision='legacy_exception', exception=self.ex(approved_on='2026-12-01'))
        self.refused('in the future')

    def test_exception_still_checks_the_files(self):
        t = g.table_counts(self.tr)
        t['lemma'] = 5
        self.write_manifest(decision='legacy_exception', exception=self.ex(),
                            **{'tr_en.db': {'sha256': g.sha256(self.tr), 'tables': t}})
        self.refused('table counts differ')


class Workflow(unittest.TestCase):
    def setUp(self):
        with open(WORKFLOW, encoding='utf-8') as f:
            self.text = f.read()
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def check(self, text):
        p = os.path.join(self.tmp, 'release.yml')
        with open(p, 'w', encoding='utf-8') as f:
            f.write(text)
        g.check_workflow(p)

    def refused(self, text, pattern):
        with self.assertRaises(g.Refused) as c:
            self.check(text)
        self.assertRegex(str(c.exception), pattern)

    def test_repository_release_workflow(self):
        self.check(self.text)
        jobs = g._jobs(self.text)
        self.assertEqual(g._needs(jobs['publish']), ['prepare', 'dictionary-gate'])
        self.assertEqual(g._needs(jobs['dictionary-gate']), ['prepare'])
        # The safeguards that were there before the gate stay.
        self.assertIn('YAYINLA', jobs['prepare'])
        self.assertIn('check-env env.json', jobs['prepare'])
        self.assertRegex(jobs['publish'], r'\n    environment: production')
        self.assertRegex(self.text, r'on:\n  workflow_dispatch:')
        self.assertNotRegex(self.text, r'\n  (push|pull_request|schedule|workflow_run):')

    def test_publish_without_gate(self):
        self.refused(self.text.replace('needs: [prepare, dictionary-gate]', 'needs: prepare'), 'publish does not need dictionary-gate')

    def test_gate_removed(self):
        t = re.sub(r'\n  dictionary-gate:\n.*?(?=\n  publish:)', '', self.text, flags=re.S)
        self.refused(t, 'no dictionary-gate job')

    def test_gate_skippable(self):
        self.refused(self.text.replace('  dictionary-gate:\n    needs: prepare\n',
                                       '  dictionary-gate:\n    needs: prepare\n    continue-on-error: true\n'),
                     'skipped or can fail')
        self.refused(self.text.replace('  dictionary-gate:\n    needs: prepare\n',
                                       "  dictionary-gate:\n    needs: prepare\n    if: inputs.confirm == 'x'\n"),
                     'skipped or can fail')

    def test_publish_after_failed_gate(self):
        self.refused(self.text.replace('    needs: [prepare, dictionary-gate]\n',
                                       '    needs: [prepare, dictionary-gate]\n    if: always()\n'), 'job-level "if:"')

    def test_ignored_result(self):
        self.refused(self.text.replace('| tee gate.log', '|| true'), 'ignored')
        self.refused(self.text.replace('set -euo pipefail\n          python3 -I tools-main/tools/lexicon_remediation',
                                       'python3 -I tools-main/tools/lexicon_remediation'), 'ignored')

    def test_legacy_report_is_not_an_approval(self):
        t = self.text.replace('--out gate-report', '--out gate-report --mode legacy')
        self.refused(t, 'legacy report')

    def test_publish_must_recheck_its_files(self):
        self.refused(self.text.replace('release_gate.py same-dbs', 'release_gate.py same'), 'publish does not check')

    def test_reviewer_kept(self):
        self.refused(self.text.replace('    environment: production\n', ''), 'production environment')


class RealManifest(unittest.TestCase):
    """The committed manifest is well formed and holds no unapproved way through."""

    def test_entries(self):
        m = g.load_manifest(os.path.join(HERE, 'dictionary_manifest.json'))
        for e in m['entries']:
            if e['decision'] == 'legacy_exception':
                ex = e['exception']
                self.assertTrue(ex.get('approved_by') and ex.get('approved_on') and ex.get('expires_on'), e['name'])
                self.assertTrue(os.path.exists(os.path.join(REPO, ex['doc'].split('#')[0])), ex['doc'])
            if e['decision'] == 'gate':
                self.assertRegex(e['provenance']['sha256'], r'^[0-9a-f]{64}$')
            for db in g.DBS:
                self.assertTrue(e[db]['tables'], e['name'])


if __name__ == '__main__':
    unittest.main()
