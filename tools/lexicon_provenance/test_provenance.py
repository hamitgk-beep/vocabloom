"""Synthetic tests for the provenance records and the publish gate.

  python3 -I -m unittest discover -s tools/lexicon_provenance -p 'test_*.py' -v

Only made-up records and tiny temporary databases are used; no user data.
"""
import copy
import gzip
import hashlib
import json
import os
import sqlite3
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import gate as gate_cli  # noqa: E402
import inventory  # noqa: E402
from provenance import Gate, independent_count, load_registry, run_gate, write_records  # noqa: E402

LIC = {
    'CC-BY-SA-4.0': {'attribution': True, 'share_alike': True, 'into_bundle': {'CC-BY-SA-4.0': True}},
    'CC-BY-4.0': {'attribution': True, 'into_bundle': {'CC-BY-SA-4.0': True}},
    'GPL-2.0-or-later': {'attribution': True, 'copyleft': True, 'into_bundle': {'CC-BY-SA-4.0': False}},
    'unknown': {'into_bundle': {'CC-BY-SA-4.0': None}},
    'AI-output': {'into_bundle': {'CC-BY-SA-4.0': None}},
}


def good(**kw):
    s = {'kind': 'primary', 'derived_from': [], 'version': '1.0', 'license_ids': ['CC-BY-4.0'],
         'license_choice': 'CC-BY-4.0', 'license_status': 'verified', 'data_origin': 'known',
         'commercial_use': 'yes', 'redistribution': 'allowed', 'attribution': 'Example source, CC BY 4.0.',
         'evidence_value': 'independent'}
    s.update(kw)
    return s


def registry():
    return {'policy': {'bundle_license': 'CC-BY-SA-4.0'}, 'licenses': copy.deepcopy(LIC), 'sources': {
        'good': good(),
        'wikt': good(license_ids=['CC-BY-SA-4.0'], license_choice='CC-BY-SA-4.0'),
        'kaikki': good(kind='extraction', derived_from=['wikt'], license_status='inherited',
                       license_ids=['CC-BY-SA-4.0'], license_choice='CC-BY-SA-4.0', evidence_value='derived'),
        'dbnary': good(kind='extraction', derived_from=['wikt'], license_status='inherited',
                       license_ids=['CC-BY-SA-4.0'], license_choice='CC-BY-SA-4.0', evidence_value='derived'),
        'other': good(),
        'nolicense': good(license_ids=['unknown'], license_choice='unknown', license_status='unknown'),
        'claimed_mit': good(license_status='claimed_unverified', data_origin='unknown'),
        'gpl': good(license_ids=['GPL-2.0-or-later'], license_choice='GPL-2.0-or-later'),
        'noattr': good(attribution=''),
        'noversion': good(version=''),
        'evalonly': good(redistribution='evaluation_only'),
        'ai': good(kind='ai', license_ids=['AI-output'], license_choice='AI-output', license_status='unknown',
                   ai='generated', evidence_value='none', derived_from=['good']),
    }}


def record(rid='dict.db/ft/x#0', sources=None, **kw):
    r = {'id': rid, 'db': 'dict.db', 'table': 'ft', 'key': 'x', 'field': 'tr', 'kind': 'translation',
         'sources': sources if sources is not None else [{'id': 'good', 'role': 'origin', 'origin_record': 'good:x',
                                                           'method': 'derivation', 'confidence': 'exact'}],
         'ai': 'none', 'human_verified': None}
    r.update(kw)
    return r


def s(sid, **kw):
    d = {'id': sid, 'role': 'origin', 'origin_record': f'{sid}:x', 'method': 'derivation', 'confidence': 'exact'}
    d.update(kw)
    return d


class GateRules(unittest.TestCase):
    def setUp(self):
        self.reg = registry()
        self.gate = Gate(self.reg)

    def status(self, rec, gate=None):
        return (gate or self.gate).evaluate(rec)

    def codes(self, rec, gate=None):
        return {f['code'] for f in self.status(rec, gate)[1]}

    def test_clean_record_is_approved(self):
        self.assertEqual(self.status(record())[0], 'approved')

    def test_unknown_license_is_never_approved(self):
        st, _ = self.status(record(sources=[s('nolicense')]))
        self.assertEqual(st, 'unknown')
        self.assertIn('license_unknown', self.codes(record(sources=[s('nolicense')])))

    def test_claimed_license_without_data_origin_is_blocked(self):
        # damdafayton's case: README says MIT, no licence file, data origin unknown
        self.assertEqual(self.status(record(sources=[s('claimed_mit')]))[0], 'blocked')

    def test_source_missing_from_registry_is_unknown(self):
        self.assertEqual(self.status(record(sources=[s('nobody')]))[0], 'unknown')

    def test_record_without_source_is_unknown(self):
        self.assertEqual(self.status(record(sources=[]))[0], 'unknown')
        self.assertEqual(self.status(record(sources=[s('unknown', confidence='unknown')]))[0], 'unknown')

    def test_missing_attribution_is_caught(self):
        st, f = self.status(record(sources=[s('noattr')]))
        self.assertEqual(st, 'blocked')
        self.assertIn('attribution_missing', {x['code'] for x in f})

    def test_gpl_into_cc_by_sa_bundle_is_blocked(self):
        self.assertEqual(self.status(record(sources=[s('gpl')]))[0], 'blocked')
        # the same record is fine for a GPL-3.0 bundle in this synthetic registry
        self.reg['licenses']['GPL-2.0-or-later']['into_bundle']['GPL-3.0-only'] = True
        self.reg['licenses']['CC-BY-4.0']['into_bundle']['GPL-3.0-only'] = True
        self.assertEqual(self.status(record(sources=[s('gpl')]), Gate(self.reg, bundle='GPL-3.0-only'))[0], 'approved')

    def test_share_alike_obligation_is_reported(self):
        self.assertIn('obligation_share_alike', self.codes(record(sources=[s('wikt')])))

    def test_missing_version_and_record_id_need_review(self):
        self.assertEqual(self.status(record(sources=[s('noversion')]))[0], 'needs_review')
        no_id = s('good')
        del no_id['origin_record']
        st, f = self.status(record(sources=[no_id]))
        self.assertEqual(st, 'needs_review')
        self.assertIn('origin_record_missing', {x['code'] for x in f})

    def test_disallowed_transfer_is_blocked(self):
        self.assertEqual(self.status(record(sources=[s('evalonly')]))[0], 'blocked')

    def test_ai_content_needs_a_human(self):
        st, f = self.status(record(sources=[s('good')], ai='generated'))
        self.assertEqual(st, 'needs_review')
        self.assertEqual(self.status(record(sources=[s('good')], ai='generated', human_verified=True))[0], 'approved')
        # an AI source is caught even if the record forgets to say so
        self.assertIn('ai_needs_human_review', self.codes(record(sources=[s('ai')], ai='none')))

    def test_inferred_source_needs_review(self):
        self.assertEqual(self.status(record(sources=[s('good', confidence='inferred', method='rebuild_match')]))[0],
                         'needs_review')

    def test_wrongly_approved_record_is_caught(self):
        st, f = self.status(record(sources=[s('noversion')], claimed_status='approved'))
        self.assertEqual(st, 'blocked')
        self.assertIn('false_approval', {x['code'] for x in f})
        # a correct claim stays approved
        self.assertEqual(self.status(record(claimed_status='approved'))[0], 'approved')

    def test_unknown_and_review_are_never_upgraded(self):
        for rec in (record(sources=[s('nolicense')]), record(sources=[s('noversion')])):
            st, _ = self.status(rec)
            for _ in range(3):
                rec = dict(rec, claimed_status=st)
                self.assertNotEqual(self.status(rec)[0], 'approved')


class Lineage(unittest.TestCase):
    def setUp(self):
        self.reg = registry()

    def test_same_root_sources_count_once(self):
        self.assertEqual(independent_count(self.reg, ['wikt', 'kaikki', 'dbnary']), 1)
        self.assertEqual(independent_count(self.reg, ['kaikki', 'dbnary']), 1)
        self.assertEqual(independent_count(self.reg, ['wikt', 'other']), 2)

    def test_ai_draft_is_no_evidence(self):
        self.assertEqual(independent_count(self.reg, ['ai']), 0)
        self.assertEqual(independent_count(self.reg, ['good', 'ai']), 1)

    def test_pseudo_independent_evidence_is_flagged(self):
        g = Gate(self.reg)
        rec = record(sources=[s('wikt')], evidence=['kaikki', 'dbnary'])
        st, f = g.evaluate(rec)
        self.assertIn('evidence_not_independent', {x['code'] for x in f})
        self.assertNotEqual(st, 'approved')
        ok = record(sources=[s('good')], evidence=['other'])
        self.assertNotIn('evidence_not_independent', {x['code'] for x in g.evaluate(ok)[1]})


class Regression(unittest.TestCase):
    def test_lost_source_id_warns(self):
        reg = registry()
        base = {'r1': record('r1', sources=[s('good'), s('other')])}
        g = Gate(reg, baseline=base)
        st, f = g.evaluate(record('r1', sources=[s('good')]))
        self.assertEqual(st, 'blocked')
        self.assertIn('provenance_regression', {x['code'] for x in f})

    def test_lost_origin_record_warns(self):
        reg = registry()
        g = Gate(reg, baseline={'r1': record('r1')})
        no_id = s('good')
        del no_id['origin_record']
        self.assertIn('origin_record_lost', {x['code'] for x in g.evaluate(record('r1', sources=[no_id]))[1]})

    def test_lost_license_warns(self):
        reg = registry()
        g = Gate(reg, baseline={'r1': record('r1', sources=[s('wikt')])})
        codes = {x['code'] for x in g.evaluate(record('r1', sources=[s('unknown', confidence='unknown')]))[1]}
        self.assertIn('license_regression', codes)

    def test_removed_record_is_listed(self):
        reg = registry()
        g = Gate(reg, baseline={'r1': record('r1'), 'r2': record('r2')})
        summary = run_gate([record('r1')], g)
        self.assertEqual(summary['removed_since_baseline'], 1)
        self.assertFalse(summary['release_ok'])


class GateCli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.reg = os.path.join(self.dir, 'reg.json')
        with open(self.reg, 'w') as f:
            json.dump(registry(), f)

    def tearDown(self):
        self.tmp.cleanup()

    def run_gate(self, records, *extra):
        path = os.path.join(self.dir, 'rec.jsonl.gz')
        write_records(path, records)
        out = os.path.join(self.dir, 'out')
        return gate_cli.main(['--records', path, '--registry', self.reg, '--out', out, *extra]), out

    def test_passes_when_all_approved(self):
        code, out = self.run_gate([record('a'), record('b')])
        self.assertEqual(code, 0)
        with open(os.path.join(out, 'summary.json')) as f:
            self.assertTrue(json.load(f)['release_ok'])

    def test_fails_with_nonzero_exit(self):
        code, out = self.run_gate([record('a'), record('b', sources=[s('nolicense')])])
        self.assertEqual(code, 1)
        for name in ('summary.json', 'by_source.csv', 'by_license.csv', 'unknown_source.csv', 'publish_unclear.csv',
                     'missing_attribution.csv', 'ai_contribution.csv', 'conflicts.csv', 'high_risk.csv', 'regressions.csv'):
            self.assertTrue(os.path.exists(os.path.join(out, name)), name)

    def test_legacy_mode_reports_without_failing_or_approving(self):
        code, out = self.run_gate([record('b', sources=[s('claimed_mit')])], '--mode', 'legacy')
        self.assertEqual(code, 0)
        with open(os.path.join(out, 'summary.json')) as f:
            sm = json.load(f)
        self.assertEqual(sm['by_status'], {'blocked': 1})
        self.assertFalse(sm['release_ok'])

    def test_bad_input_exit_2(self):
        self.assertEqual(gate_cli.main(['--records', os.path.join(self.dir, 'missing.jsonl'), '--registry', self.reg]), 2)
        bad = registry()
        bad['sources']['good']['derived_from'] = ['nowhere']
        with open(self.reg, 'w') as f:
            json.dump(bad, f)
        code, _ = self.run_gate([record('a')])
        self.assertEqual(code, 2)

    def test_baseline_regression_fails_release(self):
        base = os.path.join(self.dir, 'base.jsonl')
        write_records(base, [record('a', sources=[s('good'), s('other')])])
        code, _ = self.run_gate([record('a')], '--baseline', base)
        self.assertEqual(code, 1)


class RealRegistry(unittest.TestCase):
    """The shipped registry loads and keeps the known risks out of 'approved'."""

    def setUp(self):
        self.reg = load_registry(os.path.join(HERE, 'registry.json'))
        self.gate = Gate(self.reg)

    def test_damdafayton_is_not_treated_as_mit(self):
        self.assertEqual(self.gate.evaluate(record(sources=[s('damdafayton')]))[0], 'blocked')

    def test_freedict_gpl_is_blocked_in_cc_by_sa_bundle(self):
        self.assertIn('license_incompatible_with_bundle',
                      {x['code'] for x in self.gate.evaluate(record(sources=[s('freedict_eng_tur')]))[1]})

    def test_tatoeba_without_sentence_licence_needs_review(self):
        self.assertNotEqual(self.gate.evaluate(record(sources=[s('tatoeba')]))[0], 'approved')

    def test_wiktionary_family_is_one_lineage(self):
        self.assertEqual(independent_count(self.reg, ['wiktionary_en', 'kaikki_en', 'kindle_en_tr_wiktionary_part']), 1)
        self.assertEqual(independent_count(self.reg, ['kaikki', 'dbnary']), 1)
        self.assertEqual(independent_count(self.reg, ['own_dict_ai', 'ai_pretranslate']), 0)

    def test_ai_drafts_are_not_approved(self):
        self.assertNotEqual(self.gate.evaluate(record(sources=[s('own_dict_ai')], ai='generated'))[0], 'approved')


def _sha(p):
    with open(p, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


class InventoryReadOnly(unittest.TestCase):
    """The inventory reads tiny synthetic databases and leaves them byte-for-byte unchanged."""

    def test_databases_unchanged_and_records_written(self):
        with tempfile.TemporaryDirectory() as tmp:
            # pick one real word from the build input so ft is reproducible
            with gzip.open(os.path.join(REPO, 'tools', 'data', 'main_meanings.jsonl.gz'), 'rt', encoding='utf-8') as f:
                j = None
                for line in f:
                    j = json.loads(line)
                    if j.get('wk') and j.get('dm'):
                        break
            sys.path.insert(0, os.path.join(REPO, 'tools'))
            import main_meanings as mm
            lines = mm.merged(j['w'], j['wk'], j['dm'])
            dpath, tpath = os.path.join(tmp, 'dict.db'), os.path.join(tmp, 'tr_en.db')
            d = sqlite3.connect(dpath)
            d.executescript('''
              CREATE TABLE ft(word TEXT PRIMARY KEY, tr TEXT);
              CREATE TABLE syn(id INTEGER PRIMARY KEY, pos TEXT, gloss TEXT, examples TEXT, words TEXT, tr TEXT, extr TEXT);
              CREATE TABLE sense(lemma TEXT, pos TEXT, rank INTEGER, syn_id INTEGER);
              CREATE TABLE exc(form TEXT, lemma TEXT, pos TEXT);
              CREATE TABLE fam(word TEXT PRIMARY KEY, gid INTEGER);
              CREATE TABLE famg(id INTEGER PRIMARY KEY, root TEXT, members TEXT, negs TEXT);
              CREATE TABLE expr(id INTEGER PRIMARY KEY, phrase TEXT, cat TEXT, tr TEXT, en TEXT, forms TEXT, ex TEXT, entr TEXT, extr TEXT);
              CREATE TABLE exd(phrase TEXT, cat TEXT, json TEXT);
              CREATE TABLE exs(key TEXT, en TEXT, tr TEXT);
              CREATE TABLE wfreq(word TEXT PRIMARY KEY, n INTEGER);
              CREATE TABLE exfreq(phrase TEXT, cat TEXT, n INTEGER);
              CREATE TABLE own_word(word TEXT PRIMARY KEY, senses TEXT, keep_tr TEXT, status TEXT, reviewed INTEGER, action TEXT, source TEXT, note TEXT);
              CREATE TABLE own_expr(phrase TEXT, cat TEXT, senses TEXT, status TEXT, reviewed INTEGER, action TEXT, source TEXT, note TEXT);''')
            d.execute('INSERT INTO ft VALUES (?,?)', (j['w'], json.dumps(lines, ensure_ascii=False)))
            d.execute("INSERT INTO syn VALUES (1,'n','a made-up gloss','[]','[\"example\"]','[\"örnek\"]',NULL)")
            d.execute("INSERT INTO expr(id, phrase, cat, tr) VALUES (1,'made up phrase','idioms','uydurma')")
            d.execute("INSERT INTO exs VALUES ('w:example','This is an example.','Bu bir örnek.')")
            d.execute("INSERT INTO own_word VALUES ('example','[{\"tr\":\"örnek\"}]','[]','ai_draft_unreviewed',0,NULL,'ai_generated',NULL)")
            d.commit()
            d.close()
            t = sqlite3.connect(tpath)
            t.executescript('''
              CREATE TABLE lemma(word TEXT PRIMARY KEY, rank INTEGER, senses TEXT);
              CREATE TABLE form(form TEXT, lemma TEXT);
              CREATE TABLE ex(lemma TEXT, tr TEXT, en TEXT, id INTEGER);
              CREATE TABLE ctx(lemma TEXT, g INTEGER, word TEXT, n INTEGER);
              CREATE TABLE ctxn(lemma TEXT, g INTEGER, n INTEGER);
              CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);''')
            t.execute("INSERT INTO lemma VALUES ('örnek',1,'[{\"p\":\"noun\",\"g\":[\"example\"]},{\"p\":\"\",\"g\":[\"x\"],\"s\":\"zz\"}]')")
            t.execute("INSERT INTO ex VALUES ('örnek','Bu bir örnek.','This is an example.',42)")
            t.commit()
            t.close()
            before = (_sha(dpath), _sha(tpath))
            out = os.path.join(tmp, 'rec.jsonl')
            code = inventory.main(['--dict', dpath, '--tr-en', tpath, '--repo', REPO, '--out', out])
            self.assertEqual(code, 0)
            self.assertEqual(before, (_sha(dpath), _sha(tpath)))
            with open(out, encoding='utf-8') as f:
                recs = [json.loads(x) for x in f]
            ft = [r for r in recs if r['table'] == 'ft']
            self.assertTrue(ft)
            self.assertTrue(all(r['sources'][0]['id'] in ('kindle_en_tr_wiktionary_part', 'damdafayton') for r in ft))
            # without the raw inputs syn Turkish and expression meanings stay unknown, never guessed
            syn_tr = [r for r in recs if r['table'] == 'syn' and r['field'] == 'tr']
            self.assertEqual(syn_tr[0]['sources'][0]['id'], 'unknown')
            expr = [r for r in recs if r['table'] == 'expr' and r['field'] == 'tr']
            self.assertEqual(expr[0]['sources'][0]['id'], 'unknown')
            odd = [r for r in recs if r['table'] == 'lemma' and r['key'] == 'örnek' and r['sources'][0]['id'] == 'unknown']
            self.assertTrue(odd, 'an unknown source tag must stay unknown')
            # the databases cannot be written through the inventory connection
            with self.assertRaises(sqlite3.OperationalError):
                inventory.ro(dpath).execute("INSERT INTO ft VALUES ('zz','[]')")


if __name__ == '__main__':
    unittest.main()
