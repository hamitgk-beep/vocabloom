"""Synthetic tests of build_candidate.py and check_candidate.py. Small made-up
dictionaries with the app's schema; no real dictionary or user data.

  python3 -I -m unittest discover -s tools/lexicon_remediation -p 'test_*.py' -v
"""
import gzip
import hashlib
import json
import os
import shutil
import sqlite3
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import build_candidate as bc  # noqa: E402
import check_candidate as cc  # noqa: E402

DICT_SCHEMA = """
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE ft(word TEXT PRIMARY KEY, tr TEXT);
CREATE TABLE syn(id INTEGER PRIMARY KEY, pos TEXT, gloss TEXT, examples TEXT, words TEXT, tr TEXT, extr TEXT);
CREATE TABLE sense(lemma TEXT, pos TEXT, rank INTEGER, syn_id INTEGER);
CREATE TABLE exc(form TEXT, lemma TEXT, pos TEXT);
CREATE TABLE famg(id INTEGER PRIMARY KEY, root TEXT, members TEXT, negs TEXT);
CREATE TABLE fam(word TEXT PRIMARY KEY, gid INTEGER);
CREATE TABLE expr(id INTEGER PRIMARY KEY, phrase TEXT, cat TEXT, tr TEXT, en TEXT, forms TEXT, ex TEXT, entr TEXT, extr TEXT);
CREATE TABLE exd(phrase TEXT, cat TEXT, json TEXT, PRIMARY KEY(phrase, cat));
CREATE TABLE exs(key TEXT, en TEXT, tr TEXT);
CREATE TABLE wfreq(word TEXT PRIMARY KEY, n INTEGER);
CREATE TABLE exfreq(phrase TEXT, cat TEXT, n INTEGER);
CREATE TABLE wd(word TEXT PRIMARY KEY, tr TEXT, json TEXT);
CREATE TABLE own_word(word TEXT PRIMARY KEY, senses TEXT NOT NULL, keep_tr TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL,
  reviewed INTEGER NOT NULL DEFAULT 0, action TEXT, source TEXT, note TEXT);
CREATE TABLE own_expr(phrase TEXT NOT NULL, cat TEXT NOT NULL DEFAULT '', senses TEXT NOT NULL, status TEXT NOT NULL,
  reviewed INTEGER NOT NULL DEFAULT 0, action TEXT, source TEXT, note TEXT, PRIMARY KEY(phrase, cat));
CREATE INDEX sense_lemma ON sense(lemma);
"""
TR_SCHEMA = """
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE lemma(word TEXT PRIMARY KEY, rank INTEGER, senses TEXT);
CREATE TABLE form(form TEXT, lemma TEXT, PRIMARY KEY(form, lemma));
CREATE TABLE ex(lemma TEXT, tr TEXT, en TEXT, id INTEGER);
CREATE TABLE ctx(lemma TEXT, g INTEGER, word TEXT, n INTEGER);
CREATE TABLE ctxn(lemma TEXT, g INTEGER, n INTEGER);
CREATE INDEX ex_lemma ON ex(lemma);
"""
MEANINGS = [
    {'w': 'book', 'wk': ['kitap, cilt'], 'dm': ['defter', 'kitap']},   # mixed: "defter" is damdafayton only
    {'w': 'pen', 'dm': ['kalem']},                                       # damdafayton only
    {'w': 'sea', 'wk': ['deniz']},                                       # Wiktionary only
]
KITAP = [{'p': 'noun', 'g': ['book']}, {'p': 'n', 'g': ['volume (a book)', 'tome (a big book)'], 's': 'wn'},
         {'p': '', 'g': ['book; ledger'], 's': 'fd'}]


def sha(path):
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def r(db, table, key, idx, field, source, ai='none', transforms=()):
    return {'id': f'{db}/{table}/{key}#{idx}:{field}', 'db': db, 'table': table, 'key': key, 'field': field,
            'sources': [{'id': source, 'role': 'origin'}], 'ai': ai, 'transforms': list(transforms), 'count': 1}


class Candidate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        # A repo with the real merge code and made-up meaning data.
        self.repo = os.path.join(self.tmp, 'repo')
        os.makedirs(os.path.join(self.repo, 'tools', 'data'))
        os.makedirs(os.path.join(self.repo, 'tools', 'qa'))
        shutil.copy(os.path.join(REPO, 'tools', 'main_meanings.py'), os.path.join(self.repo, 'tools'))
        shutil.copy(os.path.join(REPO, 'tools', 'qa', 'audit_dict.py'), os.path.join(self.repo, 'tools', 'qa'))
        with gzip.open(os.path.join(self.repo, 'tools', 'data', 'main_meanings.jsonl.gz'), 'wt', encoding='utf-8') as f:
            for j in MEANINGS:
                f.write(json.dumps(j, ensure_ascii=False) + '\n')
        sys.path.insert(0, os.path.join(self.repo, 'tools'))
        sys.modules.pop('main_meanings', None)
        import main_meanings as mm
        self.mm = mm
        self.dict = os.path.join(self.tmp, 'dict.db')
        self.tr = os.path.join(self.tmp, 'tr_en.db')
        d = sqlite3.connect(self.dict)
        d.executescript(DICT_SCHEMA)
        for j in MEANINGS:
            d.execute('INSERT INTO ft VALUES (?,?)', (j['w'], json.dumps(mm.merged(j['w'], j.get('wk', []), j.get('dm', [])), ensure_ascii=False)))
        d.execute("INSERT INTO syn VALUES (5, 'n', 'a written work', '[]', '[\"book\"]', '[\"kitap\", \"tomar\"]', NULL)")
        d.execute("INSERT INTO syn VALUES (6, 'n', 'a large body of salt water', '[]', '[\"sea\"]', '[\"deniz\"]', NULL)")
        d.executemany('INSERT INTO sense VALUES (?,?,?,?)', [('book', 'n', 0, 5), ('sea', 'n', 0, 6), ('pen', 'n', 0, 6)])
        d.execute("INSERT INTO expr VALUES (1, 'by the book', 'idiom', 'kurallara göre', NULL, NULL, NULL, NULL, NULL)")
        d.execute("INSERT INTO expr VALUES (2, 'at sea', 'idiom', 'şaşkın', NULL, NULL, NULL, NULL, NULL)")
        d.execute("INSERT INTO own_word VALUES ('pen', '[{\"tr\": \"kalem\"}]', '[]', 'ai_draft_unreviewed', 0, NULL, 'ai_generated', NULL)")
        d.execute("INSERT INTO wfreq VALUES ('pen', 9), ('book', 8), ('sea', 7)")
        d.commit()
        d.close()
        t = sqlite3.connect(self.tr)
        t.executescript(TR_SCHEMA)
        t.execute('INSERT INTO lemma VALUES (?,?,?)', ('kitap', 1, json.dumps(KITAP)))
        t.execute('INSERT INTO lemma VALUES (?,?,?)', ('defter', 2, json.dumps([{'p': '', 'g': ['book'], 's': 'fd'}])))
        t.execute('INSERT INTO lemma VALUES (?,?,?)', ('deniz', 3, json.dumps([{'p': 'noun', 'g': ['sea']}])))
        t.executemany('INSERT INTO form VALUES (?,?)', [('kitabı', 'kitap'), ('denizi', 'deniz')])
        t.executemany('INSERT INTO ex VALUES (?,?,?,?)', [('kitap', 'Kitap okudum.', 'I read a book.', 11),
                                                          ('defter', 'Defter aldım.', 'I bought a notebook.', 12)])
        t.executemany('INSERT INTO ctx VALUES (?,?,?,?)', [('kitap', 3, 'oku', 5), ('kitap', 2, 'büyük', 1), ('kitap', 0, 'yeni', 2)])
        t.executemany('INSERT INTO ctxn VALUES (?,?,?)', [('kitap', 0, 9), ('kitap', 3, 5), ('defter', 0, 2)])
        t.execute("INSERT INTO meta VALUES ('ctx:kitap:3:Kitap okudum.', 'contrib')")
        t.commit()
        t.close()
        self.records = os.path.join(self.tmp, 'records.jsonl.gz')
        self.stats = os.path.join(self.tmp, 'inventory.json')
        recs = [
            r('dict.db', 'syn', '5', 'kitap', 'tr', 'kenet'),
            r('dict.db', 'syn', '5', 'tomar', 'tr', 'ai_pretranslate', ai='generated'),
            r('dict.db', 'syn', '6', 'deniz', 'tr', 'kenet'),
            dict(r('dict.db', 'expr', 'at sea|idiom', 0, 'tr', 'freedict_eng_tur'), id='dict.db/expr/at sea|idiom:tr'),
            r('tr_en.db', 'lemma', 'kitap', '1.0', 'sense', 'kenet', transforms=['add_reverse.py (reverse of dict.db syn)']),
            r('tr_en.db', 'lemma', 'kitap', '1.1', 'sense', 'ai_pretranslate', ai='generated', transforms=['add_reverse.py (reverse of dict.db syn)']),
            r('tr_en.db', 'lemma', 'kitap', '2.0', 'sense', 'kindle_en_tr_wiktionary_part', transforms=['add_reverse.py (reverse of dict.db ft)']),
            r('tr_en.db', 'lemma', 'kitap', '2.1', 'sense', 'damdafayton', transforms=['add_reverse.py (reverse of dict.db ft)']),
            r('tr_en.db', 'lemma', 'defter', '0.0', 'sense', 'damdafayton', transforms=['add_reverse.py (reverse of dict.db ft)']),
        ]
        with gzip.open(self.records, 'wt', encoding='utf-8') as f:
            for x in recs:
                f.write(json.dumps(x, ensure_ascii=False) + '\n')
        with open(self.stats, 'w') as f:
            json.dump({'sha256': {self.dict: sha(self.dict), self.tr: sha(self.tr)}, 'raw': {}}, f)
        self.out = os.path.join(self.tmp, 'cand')

    def tearDown(self):
        sys.path.remove(os.path.join(self.repo, 'tools'))
        sys.modules.pop('main_meanings', None)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def build(self, out=None):
        return bc.main(['--dict', self.dict, '--tr-en', self.tr, '--repo', self.repo, '--records', self.records,
                        '--records-stats', self.stats, '--out', out or self.out])

    def q(self, db, sql, *args):
        c = sqlite3.connect(os.path.join(self.out, db))
        try:
            return c.execute(sql, args).fetchall()
        finally:
            c.close()

    def test_build(self):
        before = (sha(self.dict), sha(self.tr))
        self.assertEqual(self.build(), 0)
        self.assertEqual((sha(self.dict), sha(self.tr)), before, 'the inputs must not change')
        ft = {w: json.loads(t) for w, t in self.q('dict.db', 'SELECT word, tr FROM ft')}
        self.assertEqual(ft, {'book': ['kitap, cilt'], 'sea': ['deniz']})  # no "defter", no "pen"
        self.assertEqual(json.loads(self.q('dict.db', 'SELECT tr FROM syn WHERE id=5')[0][0]), ['kitap'])
        self.assertEqual(self.q('dict.db', "SELECT tr FROM expr WHERE id=2"), [(None,)])
        self.assertEqual(self.q('dict.db', "SELECT tr FROM expr WHERE id=1"), [('kurallara göre',)])
        # The AI draft row and the WordNet senses stay as they were.
        self.assertEqual(self.q('dict.db', 'SELECT count(*) FROM own_word'), [(1,)])
        self.assertEqual(self.q('dict.db', 'SELECT count(*) FROM sense'), [(3,)])
        kitap = json.loads(self.q('tr_en.db', "SELECT senses FROM lemma WHERE word='kitap'")[0][0])
        self.assertEqual(kitap, [KITAP[0], {'p': 'n', 'g': ['volume (a book)'], 's': 'wn'}, {'p': '', 'g': ['book'], 's': 'rv'}])
        self.assertEqual(self.q('tr_en.db', "SELECT word FROM lemma ORDER BY word"), [('deniz',), ('kitap',)])
        self.assertEqual(self.q('tr_en.db', "SELECT count(*) FROM ex WHERE lemma='defter'"), [(0,)])
        self.assertEqual(self.q('tr_en.db', "SELECT count(*) FROM ctxn WHERE lemma='defter'"), [(0,)])
        # Gloss 3 ("book; ledger") is gloss 2 now; gloss 2 (the AI "tome") is gone.
        self.assertEqual(sorted(self.q('tr_en.db', "SELECT g, word, n FROM ctx WHERE lemma='kitap'")), [(0, 'yeni', 2), (2, 'oku', 5)])
        self.assertEqual(sorted(self.q('tr_en.db', "SELECT g, n FROM ctxn WHERE lemma='kitap'")), [(0, 9), (2, 5)])
        self.assertEqual(self.q('tr_en.db', "SELECT key FROM meta WHERE key LIKE 'ctx:%'"), [('ctx:kitap:2:Kitap okudum.',)])
        reasons = dict(self.q('quarantine.db', 'SELECT reason, count(*) FROM removed GROUP BY reason'))
        self.assertEqual(reasons['damdafayton_only'], 2)  # book "defter", pen "kalem"
        self.assertEqual(reasons['ai_not_kenet'], 1)
        self.assertEqual(reasons['freedict_gpl'], 1)
        self.assertEqual(reasons['damdafayton_reverse'], 2)
        self.assertEqual(reasons['reverse_of_ai_syn_tr'], 1)
        self.assertEqual(reasons['no_meaning_left'], 1)
        with open(os.path.join(self.out, 'ft_id_map.tsv')) as f:
            ids = dict(line.rstrip('\n').split('\t') for line in f.readlines()[1:])
        self.assertEqual(ids['ft:book#0'], 'ft:book#0')
        self.assertEqual(ids['ft:pen#0'], '')
        # check_candidate agrees.
        self.assertEqual(cc.main(['--base-dict', self.dict, '--base-tr-en', self.tr, '--cand', self.out]), 0)

    def test_deterministic(self):
        self.assertEqual(self.build(), 0)
        other = os.path.join(self.tmp, 'cand2')
        self.assertEqual(self.build(other), 0)
        for db in ('dict.db', 'tr_en.db'):
            self.assertEqual(sha(os.path.join(self.out, db)), sha(os.path.join(other, db)))

    def test_records_of_other_files_are_refused(self):
        with open(self.stats, 'w') as f:
            json.dump({'sha256': {'x': '0' * 64, 'y': '1' * 64}, 'raw': {}}, f)
        self.assertEqual(self.build(), 2)

    def test_records_without_raw_are_refused(self):
        with open(self.stats, 'w') as f:
            json.dump({'sha256': {self.dict: sha(self.dict), self.tr: sha(self.tr)}}, f)
        self.assertEqual(self.build(), 2)

    def test_ft_that_does_not_reproduce_is_refused(self):
        d = sqlite3.connect(self.dict)
        d.execute("UPDATE ft SET tr = '[\"uydurma\"]' WHERE word = 'sea'")
        d.commit()
        d.close()
        with open(self.stats, 'w') as f:
            json.dump({'sha256': {self.dict: sha(self.dict), self.tr: sha(self.tr)}, 'raw': {}}, f)
        self.assertEqual(self.build(), 2)

    def test_check_finds_new_text(self):
        self.assertEqual(self.build(), 0)
        c = sqlite3.connect(os.path.join(self.out, 'dict.db'))
        c.execute("UPDATE ft SET tr = '[\"kitap, yazı\"]' WHERE word = 'book'")
        c.commit()
        c.close()
        self.assertEqual(cc.main(['--base-dict', self.dict, '--base-tr-en', self.tr, '--cand', self.out]), 1)

    def test_check_finds_fd_tag_and_broken_context(self):
        self.assertEqual(self.build(), 0)
        c = sqlite3.connect(os.path.join(self.out, 'tr_en.db'))
        c.execute("UPDATE lemma SET senses = ? WHERE word = 'kitap'", (json.dumps(KITAP[:1] + [{'p': '', 'g': ['book'], 's': 'fd'}]),))
        c.commit()
        c.close()
        problems = []
        cc.check_tr_en(cc.ro(self.tr), cc.ro(os.path.join(self.out, 'tr_en.db')), problems, {})
        self.assertTrue(any('"fd"' in p for p in problems), problems)
        self.assertTrue(any('point at no gloss' in p for p in problems), problems)

    def test_check_finds_changed_untouchable_table(self):
        self.assertEqual(self.build(), 0)
        c = sqlite3.connect(os.path.join(self.out, 'dict.db'))
        c.execute("UPDATE own_word SET status = 'contrib', reviewed = 1")
        c.commit()
        c.close()
        problems = []
        cc.check_dict(cc.ro(self.dict), cc.ro(os.path.join(self.out, 'dict.db')), problems, {})
        self.assertIn('dict.db: table own_word changed but must not', problems)


if __name__ == '__main__':
    unittest.main()
