"""Adds the own-dictionary tables to a COPY of the app database. Never touches ft or expr.

usage: python3 tools/own_dict/db/migrate.py SOURCE_DB OUT_DB ENTRIES.jsonl.gz

  own_word(word PRIMARY KEY, senses JSON, keep_tr JSON, status, reviewed, action, source, note)
  keep_tr: Turkish meanings that stay (the Wiktionary part); the app shows keep_tr first, then the senses.
  own_expr(phrase, cat, senses JSON, status, reviewed, action, source, note, PRIMARY KEY(phrase, cat))
  od: view with the (word, json) shape that the context-sense reader expects, reading own_word.

Rows are written with INSERT OR IGNORE on the key, so running it twice does not duplicate anything.
Fallback order for the app: own_word/own_expr first, then ft/expr when no own row exists or the own row is empty.
"""
import gzip, json, shutil, sqlite3, sys

src, out, entries = sys.argv[1], sys.argv[2], sys.argv[3]
shutil.copyfile(src, out)
db = sqlite3.connect(out)
db.executescript('''
CREATE TABLE IF NOT EXISTS own_word(
  word TEXT PRIMARY KEY, senses TEXT NOT NULL, keep_tr TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL, reviewed INTEGER NOT NULL DEFAULT 0,
  action TEXT, source TEXT, note TEXT);
CREATE TABLE IF NOT EXISTS own_expr(
  phrase TEXT NOT NULL, cat TEXT NOT NULL DEFAULT '', senses TEXT NOT NULL, status TEXT NOT NULL,
  reviewed INTEGER NOT NULL DEFAULT 0, action TEXT, source TEXT, note TEXT, PRIMARY KEY(phrase, cat));
DROP VIEW IF EXISTS od;
CREATE VIEW od AS SELECT word, senses AS json FROM own_word;
''')
n_w = n_e = skipped = 0
with gzip.open(entries, 'rt', encoding='utf-8') as f:
    for line in f:
        r = json.loads(line)
        if not r['senses'] or r['status'] not in ('auto_generated', 'ai_draft_unreviewed'):
            skipped += 1
            continue
        senses = json.dumps(r['senses'], ensure_ascii=False)
        if r['kind'] == 'word':
            cur = db.execute('INSERT OR IGNORE INTO own_word VALUES (?,?,?,?,?,?,?,?)',
                             (r['w'], senses, json.dumps(r.get('keep_tr', []), ensure_ascii=False), r['status'], 0,
                              r.get('action'), r.get('source'), r.get('note')))
            n_w += cur.rowcount
        else:
            cur = db.execute('INSERT OR IGNORE INTO own_expr VALUES (?,?,?,?,?,?,?,?)',
                             (r['w'], r.get('cat', ''), senses, r['status'], 0, r.get('action'), r.get('source'), r.get('note')))
            n_e += cur.rowcount
db.commit()
print(json.dumps({'own_word_rows': n_w, 'own_expr_rows': n_e, 'skipped': skipped}))
