"""Candidate database: a separate SQLite file that never touches the shipped dictionaries.

Every candidate keeps its source, the source's licence, the dictionary direction (en-tr / tr-en), the engine
that produced it, the result of the read-only comparison with the existing dictionaries and a review status.
New candidates always start as `unverified`; only `review()` with a named reviewer can accept or reject one,
and each change is written to `review_log`.
"""
import json
import os
import sqlite3
import time

from . import SCHEMA_VERSION
from .licenses import classify
from .safety import check_writable_target

KINDS = ('word', 'sense', 'phrasal_verb', 'idiom', 'collocation', 'example')
DIRECTIONS = ('en-tr', 'tr-en')
STATUSES = ('unverified', 'needs_review', 'accepted', 'rejected')
# Statuses a pipeline (anything other than a human review) may set.
AUTO_STATUSES = ('unverified', 'needs_review')

SCHEMA = f'''
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
INSERT OR IGNORE INTO meta VALUES ('schema_version', '{SCHEMA_VERSION}');

CREATE TABLE IF NOT EXISTS source(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL,
  licence TEXT NOT NULL,
  licence_url TEXT NOT NULL DEFAULT '',
  permission TEXT NOT NULL CHECK (permission IN ('allowed', 'needs_approval', 'unknown', 'private_only')),
  shareable INTEGER NOT NULL CHECK (shareable IN (0, 1)),
  licence_note TEXT NOT NULL DEFAULT '',
  lang TEXT NOT NULL CHECK (lang IN ('en', 'tr')),
  added_at TEXT NOT NULL,
  CHECK (kind != 'user_book' OR (shareable = 0 AND permission = 'private_only')),
  CHECK (shareable = 0 OR permission = 'allowed')
);

CREATE TABLE IF NOT EXISTS candidate(
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN {KINDS}),
  direction TEXT NOT NULL CHECK (direction IN {DIRECTIONS}),
  headword TEXT NOT NULL,
  lemma TEXT NOT NULL DEFAULT '',
  pos TEXT NOT NULL DEFAULT '',
  translation TEXT NOT NULL DEFAULT '',
  definition TEXT NOT NULL DEFAULT '',
  example TEXT NOT NULL DEFAULT '',
  example_translation TEXT NOT NULL DEFAULT '',
  source_id INTEGER NOT NULL REFERENCES source(id),
  licence TEXT NOT NULL,                -- snapshot of the source licence when the candidate was made
  permission TEXT NOT NULL,             -- snapshot of the source usage permission
  locator TEXT NOT NULL DEFAULT '',
  engine TEXT NOT NULL,
  confidence REAL NOT NULL DEFAULT 0 CHECK (confidence BETWEEN 0 AND 1),
  compare_result TEXT NOT NULL DEFAULT '',
  compare_detail TEXT NOT NULL DEFAULT '',
  occurrences INTEGER NOT NULL DEFAULT 1,
  scope TEXT NOT NULL CHECK (scope IN ('shared', 'private')),
  status TEXT NOT NULL DEFAULT 'unverified' CHECK (status IN {STATUSES}),
  reviewer TEXT NOT NULL DEFAULT '',
  review_note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK (status NOT IN ('accepted', 'rejected') OR reviewer != ''),
  UNIQUE (kind, direction, headword, pos, translation, example, source_id)
);
CREATE INDEX IF NOT EXISTS candidate_head ON candidate(direction, headword);
CREATE INDEX IF NOT EXISTS candidate_status ON candidate(status);

CREATE TABLE IF NOT EXISTS review_log(
  id INTEGER PRIMARY KEY,
  candidate_id INTEGER NOT NULL REFERENCES candidate(id),
  old_status TEXT NOT NULL,
  new_status TEXT NOT NULL,
  reviewer TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  at TEXT NOT NULL
);

-- A candidate from a source that is not shareable can never be marked shared.
CREATE TRIGGER IF NOT EXISTS candidate_scope_insert BEFORE INSERT ON candidate
WHEN NEW.scope = 'shared' AND (SELECT shareable FROM source WHERE id = NEW.source_id) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'candidate from a non-shareable source must be private'); END;
CREATE TRIGGER IF NOT EXISTS candidate_scope_update BEFORE UPDATE OF scope, source_id ON candidate
WHEN NEW.scope = 'shared' AND (SELECT shareable FROM source WHERE id = NEW.source_id) IS NOT 1
BEGIN SELECT RAISE(ABORT, 'candidate from a non-shareable source must be private'); END;
'''


def _now():
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


class CandidateStore:
    def __init__(self, path):
        real = check_writable_target(path)
        os.makedirs(os.path.dirname(real) or '.', exist_ok=True)
        self.path = real
        self.db = sqlite3.connect(real)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys = ON')
        self.db.executescript(SCHEMA)
        self.db.commit()

    def close(self):
        self.db.close()

    # ---- sources -------------------------------------------------------------------------------------
    def add_source(self, name, kind, licence, lang, licence_url=''):
        lid, permission, shareable, note = classify(licence, kind)
        if kind == 'existing_dictionary':
            raise ValueError('shipped dictionaries are compared read-only and are not candidate sources')
        row = self.db.execute('SELECT id FROM source WHERE name = ?', [name]).fetchone()
        if row:
            return row['id']
        cur = self.db.execute(
            'INSERT INTO source(name, kind, licence, licence_url, permission, shareable, licence_note, lang, added_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [name, kind, lid, licence_url, permission, int(shareable), note, lang, _now()])
        self.db.commit()
        return cur.lastrowid

    def source(self, source_id):
        return self.db.execute('SELECT * FROM source WHERE id = ?', [source_id]).fetchone()

    # ---- candidates ----------------------------------------------------------------------------------
    def add_candidate(self, *, kind, direction, headword, source_id, engine, lemma='', pos='', translation='',
                      definition='', example='', example_translation='', locator='', confidence=0.0,
                      compare_result='', compare_detail=None, status='unverified'):
        """Inserts a candidate, or counts one more occurrence of an identical one. Returns its id.

        Pipelines can only set `unverified` or `needs_review`; acceptance goes through `review()`."""
        if status not in AUTO_STATUSES:
            raise ValueError(f'a pipeline cannot set status {status!r}; use review() with a reviewer')
        if kind not in KINDS:
            raise ValueError(f'unknown kind: {kind}')
        if direction not in DIRECTIONS:
            raise ValueError(f'unknown direction: {direction}')
        src = self.source(source_id)
        if src is None:
            raise ValueError(f'unknown source id: {source_id}')
        if (src['lang'], direction) not in (('en', 'en-tr'), ('tr', 'tr-en')):
            raise ValueError(f'source language {src["lang"]} does not match direction {direction}')
        headword = headword.strip()
        if not headword:
            raise ValueError('empty headword')
        scope = 'shared' if src['shareable'] else 'private'
        detail = json.dumps(compare_detail or {}, ensure_ascii=False, sort_keys=True)
        now = _now()
        # Examples are distinct per sentence; every other kind is one row per headword/meaning and source,
        # keeping the first example and counting further occurrences.
        sql = ('SELECT id FROM candidate WHERE kind=? AND direction=? AND headword=? AND pos=? AND translation=? '
               'AND source_id=?')
        key = [kind, direction, headword, pos, translation, source_id]
        if kind == 'example':
            sql += ' AND example=?'
            key.append(example)
        row = self.db.execute(sql, key).fetchone()
        if row:
            self.db.execute('UPDATE candidate SET occurrences = occurrences + 1, updated_at = ? WHERE id = ?',
                            [now, row['id']])
            self.db.commit()
            return row['id']
        cur = self.db.execute(
            'INSERT INTO candidate(kind, direction, headword, lemma, pos, translation, definition, example, '
            'example_translation, source_id, licence, permission, locator, engine, confidence, compare_result, '
            'compare_detail, scope, status, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [kind, direction, headword, lemma, pos, translation, definition, example, example_translation,
             source_id, src['licence'], src['permission'], locator, engine, float(confidence), compare_result,
             detail, scope, status, now, now])
        self.db.commit()
        return cur.lastrowid

    def get(self, candidate_id):
        return self.db.execute('SELECT * FROM candidate WHERE id = ?', [candidate_id]).fetchone()

    def review(self, candidate_id, new_status, reviewer, note=''):
        """The only way to accept or reject a candidate. Needs a reviewer name; every change is logged."""
        if new_status not in STATUSES:
            raise ValueError(f'unknown status: {new_status}')
        reviewer = (reviewer or '').strip()
        if not reviewer:
            raise ValueError('a review needs a reviewer name')
        row = self.get(candidate_id)
        if row is None:
            raise ValueError(f'unknown candidate id: {candidate_id}')
        now = _now()
        self.db.execute('UPDATE candidate SET status=?, reviewer=?, review_note=?, updated_at=? WHERE id=?',
                        [new_status, reviewer, note, now, candidate_id])
        self.db.execute('INSERT INTO review_log(candidate_id, old_status, new_status, reviewer, note, at) '
                        'VALUES (?, ?, ?, ?, ?, ?)', [candidate_id, row['status'], new_status, reviewer, note, now])
        self.db.commit()

    def candidates(self, **where):
        sql = 'SELECT * FROM candidate'
        if where:
            sql += ' WHERE ' + ' AND '.join(f'{k} = ?' for k in where)
        return self.db.execute(sql + ' ORDER BY id', list(where.values())).fetchall()

    def summary(self):
        out = {}
        for r in self.db.execute('SELECT direction, kind, compare_result, scope, status, COUNT(*) AS n '
                                 'FROM candidate GROUP BY 1, 2, 3, 4, 5 ORDER BY 1, 2, 3, 4, 5'):
            out['|'.join([r['direction'], r['kind'], r['compare_result'], r['scope'], r['status']])] = r['n']
        return out

    def export_reviewed_shared(self, out_path):
        """Writes accepted candidates from shareable sources to a JSONL file for a later, separate,
        human-run dictionary step. Private (user book) and unreviewed candidates are never exported.
        This does not modify any dictionary."""
        check_writable_target(out_path)
        rows = self.db.execute(
            "SELECT c.*, s.name AS source_name, s.licence AS source_licence, s.licence_url AS source_licence_url "
            "FROM candidate c JOIN source s ON s.id = c.source_id "
            "WHERE c.status = 'accepted' AND c.scope = 'shared' AND c.permission = 'allowed' "
            "AND s.shareable = 1 AND s.permission = 'allowed' AND s.kind != 'user_book' ORDER BY c.id").fetchall()
        with open(out_path, 'w', encoding='utf-8') as f:
            for r in rows:
                f.write(json.dumps(dict(r), ensure_ascii=False) + '\n')
        return len(rows)
