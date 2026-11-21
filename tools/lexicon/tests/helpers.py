"""Small synthetic copies of the two dictionary schemas, so tests never need the real files."""
import hashlib
import json
import os
import sqlite3
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
REPO = os.path.dirname(TOOLS)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def make_dict_db(path):
    db = sqlite3.connect(path)
    db.executescript('''
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE ft(word TEXT PRIMARY KEY, tr TEXT);
    CREATE TABLE syn(id INTEGER PRIMARY KEY, pos TEXT, gloss TEXT, examples TEXT, words TEXT, tr TEXT, extr TEXT);
    CREATE TABLE sense(lemma TEXT, pos TEXT, rank INTEGER, syn_id INTEGER);
    CREATE TABLE exc(form TEXT, lemma TEXT, pos TEXT);
    CREATE TABLE expr(id INTEGER PRIMARY KEY, phrase TEXT, cat TEXT, tr TEXT, en TEXT, forms TEXT, ex TEXT,
                      entr TEXT, extr TEXT);
    CREATE TABLE own_word(word TEXT PRIMARY KEY, senses TEXT NOT NULL, keep_tr TEXT NOT NULL DEFAULT '[]',
                          status TEXT NOT NULL, reviewed INTEGER NOT NULL DEFAULT 0, action TEXT, source TEXT,
                          note TEXT);
    CREATE TABLE own_expr(phrase TEXT NOT NULL, cat TEXT NOT NULL DEFAULT '', senses TEXT NOT NULL,
                          status TEXT NOT NULL, reviewed INTEGER NOT NULL DEFAULT 0, action TEXT, source TEXT,
                          note TEXT, PRIMARY KEY(phrase, cat));
    ''')
    db.executemany('INSERT INTO ft VALUES (?, ?)', [
        ('rabbit', json.dumps(['tavşan'])), ('sit', json.dumps(['oturmak'])), ('tired', json.dumps(['yorgun'])),
        ('give', json.dumps(['vermek'])), ('be', json.dumps(['olmak'])), ('she', json.dumps(['o'])),
        ('very', json.dumps(['çok'])), ('the', json.dumps(['-'])), ('get', json.dumps(['almak, edinmek'])),
        ('stop', json.dumps(['durmak'])), ('hole', json.dumps(['delik'])), ('run', json.dumps(['koşmak'])),
        ('away', json.dumps(['uzağa'])), ('up', json.dumps(['yukarı'])), ('and', json.dumps(['ve'])),
        ('then', json.dumps(['sonra'])), ('a', json.dumps(['bir'])), ('it', json.dumps(['o'])),
        ('off', json.dumps(['kapalı'])), ('take', json.dumps(['almak']))])
    db.execute("INSERT INTO own_word VALUES ('run', ?, '[]', 'contrib', 1, NULL, NULL, NULL)",
               [json.dumps([{'pos': 'fiil', 'tr': 'koşmak', 'en': 'move fast'}], ensure_ascii=False)])
    db.executemany('INSERT INTO exc VALUES (?, ?, ?)', [('was', 'be', 'v'), ('gave', 'give', 'v'),
                                                       ('ran', 'run', 'v'), ('took', 'take', 'v')])
    db.execute("INSERT INTO expr(id, phrase, cat, tr) VALUES (1, 'give up', 'phrasal_verbs', 'vazgeçmek')")
    db.commit()
    db.close()


def make_tr_en_db(path):
    db = sqlite3.connect(path)
    db.executescript('''
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE lemma(word TEXT PRIMARY KEY, rank INTEGER, senses TEXT);
    CREATE TABLE form(form TEXT, lemma TEXT, PRIMARY KEY(form, lemma));
    CREATE TABLE ex(lemma TEXT, tr TEXT, en TEXT, id INTEGER);
    ''')
    db.executemany('INSERT INTO lemma VALUES (?, ?, ?)', [
        ('ev', 10, json.dumps([{'p': 'noun', 'g': ['house, home']}])),
        ('gitmek', 5, json.dumps([{'p': 'verb', 'g': ['to go', 'to leave']}])),
        ('bir', 1, json.dumps([{'p': 'det', 'g': ['a, one']}])),
        ('gün', 20, json.dumps([{'p': 'noun', 'g': ['day']}]))])
    db.executemany('INSERT INTO form VALUES (?, ?)', [('evde', 'ev'), ('eve', 'ev'), ('gitti', 'gitmek'),
                                                      ('gittim', 'gitmek')])
    db.commit()
    db.close()
