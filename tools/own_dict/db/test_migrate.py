"""Checks migrate.py on a small synthetic database. Run: python3 -m unittest tools/own_dict/db/test_migrate.py

Covers: ft and expr are unchanged, invalid candidates are skipped, a second run adds no rows,
and the fallback rule (no own row, or an empty one, means ft is used) holds in SQL.
"""
import gzip, json, os, sqlite3, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
MIGRATE = os.path.join(HERE, 'migrate.py')


def make_source(path):
    db = sqlite3.connect(path)
    db.executescript('''
    CREATE TABLE ft(word TEXT PRIMARY KEY, tr TEXT);
    CREATE TABLE expr(id INTEGER PRIMARY KEY, phrase TEXT, cat TEXT, tr TEXT);
    INSERT INTO ft VALUES ('apple', '["elma"]'), ('pear', '["armut"]');
    INSERT INTO expr VALUES (1, 'by and large', 'idiom', '["genel olarak"]');
    ''')
    db.commit()
    db.close()


def make_entries(path, records):
    with gzip.open(path, 'wt', encoding='utf-8') as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')


SENSE = {'pos': 'noun', 'tr': 'elma', 'ex_tr': 'Bir elma yedim.', 'en': 'a fruit'}

RECORDS = [
    {'w': 'apple', 'kind': 'word', 'senses': [SENSE], 'keep_tr': ['elma ağacı'], 'status': 'auto_generated'},
    {'w': 'pear', 'kind': 'word', 'senses': [], 'keep_tr': ['armut'], 'status': 'auto_generated'},
    {'w': 'plum', 'kind': 'word', 'senses': [SENSE], 'keep_tr': [], 'status': 'invalid_candidate'},
    {'w': 'by and large', 'kind': 'expr', 'senses': [SENSE], 'status': 'auto_generated'},
    {'w': 'by and large', 'kind': 'expr', 'senses': [SENSE], 'status': 'auto_generated'},
]


class MigrateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.src = os.path.join(self.tmp, 'src.db')
        self.out = os.path.join(self.tmp, 'out.db')
        self.entries = os.path.join(self.tmp, 'entries.jsonl.gz')
        make_source(self.src)
        make_entries(self.entries, RECORDS)

    def run_migrate(self):
        subprocess.run([sys.executable, MIGRATE, self.src, self.out, self.entries], check=True,
                       capture_output=True)

    def rows(self, sql):
        db = sqlite3.connect(self.out)
        try:
            return db.execute(sql).fetchall()
        finally:
            db.close()

    def test_ft_and_expr_unchanged(self):
        self.run_migrate()
        src = sqlite3.connect(self.src)
        before = (src.execute('SELECT * FROM ft ORDER BY word').fetchall(),
                  src.execute('SELECT * FROM expr ORDER BY id').fetchall())
        src.close()
        after = (self.rows('SELECT * FROM ft ORDER BY word'), self.rows('SELECT * FROM expr ORDER BY id'))
        self.assertEqual(before, after)

    def test_invalid_candidates_skipped(self):
        self.run_migrate()
        self.assertEqual(self.rows("SELECT word FROM own_word WHERE word = 'plum'"), [])

    def test_second_run_adds_no_rows(self):
        self.run_migrate()
        first = self.rows('SELECT COUNT(*) FROM own_word'), self.rows('SELECT COUNT(*) FROM own_expr')
        self.run_migrate()
        second = self.rows('SELECT COUNT(*) FROM own_word'), self.rows('SELECT COUNT(*) FROM own_expr')
        self.assertEqual(first, second)

    def test_expr_key_is_unique(self):
        self.run_migrate()
        self.assertEqual(self.rows("SELECT COUNT(*) FROM own_expr WHERE phrase = 'by and large'"), [(1,)])

    def test_keep_tr_stored(self):
        self.run_migrate()
        keep = self.rows("SELECT keep_tr FROM own_word WHERE word = 'apple'")[0][0]
        self.assertEqual(json.loads(keep), ['elma ağacı'])

    def test_fallback_rule(self):
        # Mirrors lookup() in dict_db.dart: own row used only when it has senses or keep_tr,
        # otherwise ft is used. 'apple' has an own row; 'pear' has an empty one; 'kiwi' has none.
        self.run_migrate()
        db = sqlite3.connect(self.out)
        db.execute("INSERT INTO ft VALUES ('kiwi', '[\"kivi\"]')")
        db.execute("INSERT INTO own_word(word, senses, keep_tr, status) VALUES ('empty', '[]', '[]', 'auto_generated')")
        db.execute("INSERT INTO ft VALUES ('empty', '[\"boş\"]')")
        db.commit()

        def effective(word):
            own = db.execute('SELECT senses, keep_tr FROM own_word WHERE word = ?', (word,)).fetchone()
            if own:
                tr = json.loads(own[1]) + [s['tr'] for s in json.loads(own[0])]
                if tr:
                    return tr
            row = db.execute('SELECT tr FROM ft WHERE word = ?', (word,)).fetchone()
            return json.loads(row[0]) if row else []

        self.assertEqual(effective('apple'), ['elma ağacı', 'elma'])
        self.assertEqual(effective('pear'), ['armut'])
        self.assertEqual(effective('kiwi'), ['kivi'])
        self.assertEqual(effective('empty'), ['boş'])
        db.close()


if __name__ == '__main__':
    unittest.main()
