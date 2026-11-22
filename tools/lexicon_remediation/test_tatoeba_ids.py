"""Synthetic tests of tatoeba_ids.py: made-up sentences in the Tatoeba export format."""
import gzip
import json
import os
import shutil
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tatoeba_ids as ti  # noqa: E402


class Tatoeba(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        p = lambda n: os.path.join(self.tmp, n)  # noqa: E731
        with open(p('detailed.csv'), 'w') as f:
            f.write('1\teng\tI read a book.\talice\t2020\t2020\n'
                    '2\ttur\tKitap okudum.\tbora\t2020\t2020\n'
                    '3\teng\tHello.\t\\N\t2020\t2020\n'
                    '4\ttur\tMerhaba.\tcem\t2020\t2020\n'
                    '5\ttur\tMerhaba.\tdeniz\t2021\t2021\n'
                    '6\tfra\tBonjour.\teve\t2020\t2020\n')
        with open(p('links.csv'), 'w') as f:
            f.write('1\t2\n2\t1\n3\t4\n3\t5\n3\t6\n')
        with open(p('cc0.csv'), 'w') as f:
            f.write('2\ttur\tKitap okudum.\t2020\n')
        self.pairs = ti.build_pairs(p('detailed.csv'), p('links.csv'), p('cc0.csv'), '2026-11-22')
        self.d = p('dict.db')
        c = sqlite3.connect(self.d)
        c.execute('CREATE TABLE exs(key TEXT, en TEXT, tr TEXT)')
        c.executemany('INSERT INTO exs VALUES (?,?,?)', [('w:book', 'I read a book.', 'Kitap okudum.'),
                                                         ('w:hello', 'Hello.', 'Merhaba.'),
                                                         ('w:book', 'I read a book!', 'Kitap okudum.')])
        c.commit()
        c.close()
        self.t = p('tr_en.db')
        c = sqlite3.connect(self.t)
        c.execute('CREATE TABLE ex(lemma TEXT, tr TEXT, en TEXT, id INTEGER)')
        c.executemany('INSERT INTO ex VALUES (?,?,?,?)', [('merhaba', 'Merhaba.', 'Hello.', 5), ('kitap', 'Kitap okudum.', 'I read a book.', 99),
                                                          ('kitap', 'Kitabım.', 'My book.', None)])
        c.commit()
        c.close()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_pairs_keep_ids_authors_licences(self):
        self.assertEqual(len(self.pairs), 3)  # eng->tur only, both directions of a link not doubled
        book = self.pairs[0]
        self.assertEqual((book['en_id'], book['tr_id'], book['en_user'], book['tr_user']), (1, 2, 'alice', 'bora'))
        self.assertEqual((book['en_license'], book['tr_license']), ('CC-BY-2.0-FR', 'CC0-1.0'))
        self.assertIsNone(self.pairs[1]['en_user'])  # no username: kept as unknown, not invented

    def test_exact_unique_match_only(self):
        matched, unmatched, ambiguous, st = ti.match(self.pairs, self.d, self.t)
        self.assertEqual(st['dict.db/exs_matched'], 1)
        self.assertEqual(st['dict.db/exs_ambiguous'], 1)   # "Hello." has two Turkish sentences "Merhaba."
        self.assertEqual(st['dict.db/exs_unmatched'], 1)   # "!" differs: no similarity matching
        self.assertEqual(st['tr_en.db/ex_matched'], 1)     # same text and the stored Turkish id 5
        self.assertEqual(st['tr_en.db/ex_unmatched'], 1)   # stored id 99 does not fit the text
        self.assertNotIn('tr_en.db/ex_ambiguous', st)
        self.assertEqual(matched[0]['en_id'], 1)

    def test_cli_roundtrip(self):
        out = os.path.join(self.tmp, 'pairs.jsonl.gz')
        with gzip.open(out, 'wt') as f:
            for r in self.pairs:
                f.write(json.dumps(r) + '\n')
        before = open(self.d, 'rb').read()
        self.assertEqual(ti.main(['match', out, '--dict', self.d, '--tr-en', self.t, '--out', os.path.join(self.tmp, 'm')]), 0)
        self.assertEqual(open(self.d, 'rb').read(), before)
        self.assertTrue(os.path.exists(os.path.join(self.tmp, 'm', 'unmatched.tsv')))


if __name__ == '__main__':
    unittest.main()
