"""Candidate database: a separate SQLite file that never touches the shipped dictionaries.

Tables
  source           one row per text source. Immutable after insert (triggers abort UPDATE and DELETE), so its
                   kind, language, declared licence and licence class can't be changed to slip past the rules.
  source_approval  append-only log of licence verifications (approve / revoke), each with a person and evidence.
                   Only a source with a permissive licence class can be approved; never a user's book.
  candidate        word / sense / phrasal verb / idiom / collocation / example candidates. The licence is a
                   snapshot that must equal the source's (checked on insert, immutable after), and the
                   permission and private/shared scope are *derived* from the source and its approvals (view
                   candidate_status), so they can't drift apart from the source.
  review_log       append-only log of status changes.

New candidates always start as `unverified`; only `review()` with a named reviewer can accept or reject one.
The export re-checks every rule in Python as well, and refuses to run if a protective trigger is missing.
"""
import json
import os
import sqlite3
import time

from . import SCHEMA_VERSION
from .licenses import PERMISSIVE, SOURCE_KINDS, classify
from .safety import check_writable_target

KINDS = ('word', 'sense', 'phrasal_verb', 'idiom', 'collocation', 'example')
DIRECTIONS = ('en-tr', 'tr-en')
DIRECTION_LANG = {'en-tr': 'en', 'tr-en': 'tr'}
STATUSES = ('unverified', 'needs_review', 'accepted', 'rejected')
# Statuses a pipeline (anything other than a human review) may set.
AUTO_STATUSES = ('unverified', 'needs_review')
CANDIDATE_SOURCE_KINDS = tuple(k for k in SOURCE_KINDS if k != 'existing_dictionary')

_PERMISSIVE_SQL = '(' + ', '.join(f"'{k}'" for k in sorted(PERMISSIVE)) + ')'

TRIGGERS = {
    # --- source: immutable, consistent licence class ---------------------------------------------------
    'source_insert_check': f'''
CREATE TRIGGER source_insert_check BEFORE INSERT ON source
WHEN (NEW.kind = 'user_book') != (NEW.licence_class = 'private_only')
  OR (NEW.licence_class = 'permissive' AND NEW.licence NOT IN {_PERMISSIVE_SQL})
  OR (NEW.licence IN {_PERMISSIVE_SQL} AND NEW.kind != 'user_book' AND NEW.licence_class != 'permissive')
BEGIN SELECT RAISE(ABORT, 'source licence class does not match its licence and kind'); END''',
    'source_no_update': '''
CREATE TRIGGER source_no_update BEFORE UPDATE ON source
BEGIN SELECT RAISE(ABORT, 'sources are immutable; add a new source instead'); END''',
    'source_no_delete': '''
CREATE TRIGGER source_no_delete BEFORE DELETE ON source
BEGIN SELECT RAISE(ABORT, 'sources cannot be deleted'); END''',
    # --- source_approval: append-only, only permissive non-private sources -------------------------------
    'approval_insert_check': '''
CREATE TRIGGER approval_insert_check BEFORE INSERT ON source_approval
WHEN NEW.decision = 'approve' AND (SELECT licence_class FROM source WHERE id = NEW.source_id) IS NOT 'permissive'
BEGIN SELECT RAISE(ABORT, 'only a source with a permissive licence class can be approved'); END''',
    'approval_no_update': '''
CREATE TRIGGER approval_no_update BEFORE UPDATE ON source_approval
BEGIN SELECT RAISE(ABORT, 'the approval log is append-only'); END''',
    'approval_no_delete': '''
CREATE TRIGGER approval_no_delete BEFORE DELETE ON source_approval
BEGIN SELECT RAISE(ABORT, 'the approval log is append-only'); END''',
    # --- candidate: licence snapshot must match the source, identity fields immutable ---------------------
    'candidate_insert_check': '''
CREATE TRIGGER candidate_insert_check BEFORE INSERT ON candidate
WHEN NEW.licence IS NOT (SELECT licence FROM source WHERE id = NEW.source_id)
  OR NEW.direction IS NOT (CASE (SELECT lang FROM source WHERE id = NEW.source_id)
                           WHEN 'en' THEN 'en-tr' WHEN 'tr' THEN 'tr-en' END)
BEGIN SELECT RAISE(ABORT, 'candidate licence or direction does not match its source'); END''',
    'candidate_identity_fixed': '''
CREATE TRIGGER candidate_identity_fixed BEFORE UPDATE OF source_id, licence, direction, kind, headword ON candidate
WHEN NEW.source_id IS NOT OLD.source_id OR NEW.licence IS NOT OLD.licence OR NEW.direction IS NOT OLD.direction
  OR NEW.kind IS NOT OLD.kind OR NEW.headword IS NOT OLD.headword
BEGIN SELECT RAISE(ABORT, 'candidate source, licence, direction, kind and headword are fixed'); END''',
    'review_log_no_update': '''
CREATE TRIGGER review_log_no_update BEFORE UPDATE ON review_log
BEGIN SELECT RAISE(ABORT, 'the review log is append-only'); END''',
    'review_log_no_delete': '''
CREATE TRIGGER review_log_no_delete BEFORE DELETE ON review_log
BEGIN SELECT RAISE(ABORT, 'the review log is append-only'); END''',
}

SCHEMA = f'''
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
INSERT OR IGNORE INTO meta VALUES ('schema_version', '{SCHEMA_VERSION}');

CREATE TABLE IF NOT EXISTS source(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL CHECK (kind IN {CANDIDATE_SOURCE_KINDS}),
  licence TEXT NOT NULL,                -- declared licence, normalised (a claim, not a permission)
  licence_class TEXT NOT NULL CHECK (licence_class IN ('permissive', 'needs_approval', 'unknown', 'private_only')),
  licence_url TEXT NOT NULL DEFAULT '',
  licence_note TEXT NOT NULL DEFAULT '',
  lang TEXT NOT NULL CHECK (lang IN ('en', 'tr')),
  added_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS source_approval(
  id INTEGER PRIMARY KEY,
  source_id INTEGER NOT NULL REFERENCES source(id),
  decision TEXT NOT NULL CHECK (decision IN ('approve', 'revoke')),
  approver TEXT NOT NULL CHECK (length(trim(approver)) > 0),
  evidence TEXT NOT NULL CHECK (length(trim(evidence)) > 0),
  at TEXT NOT NULL
);

-- Effective permission of each source: derived, never stored, so it cannot be edited directly.
CREATE VIEW IF NOT EXISTS source_status AS
SELECT s.*,
  (SELECT a.decision FROM source_approval a WHERE a.source_id = s.id ORDER BY a.id DESC LIMIT 1) AS last_decision,
  (SELECT a.approver FROM source_approval a WHERE a.source_id = s.id ORDER BY a.id DESC LIMIT 1) AS approved_by,
  CASE
    WHEN s.kind = 'user_book' THEN 'private_only'
    WHEN s.licence_class = 'permissive' AND
         (SELECT a.decision FROM source_approval a WHERE a.source_id = s.id ORDER BY a.id DESC LIMIT 1) = 'approve'
      THEN 'allowed'
    WHEN s.licence_class = 'permissive' THEN 'pending_verification'
    ELSE s.licence_class
  END AS permission
FROM source s;

CREATE TABLE IF NOT EXISTS candidate(
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN {KINDS}),
  direction TEXT NOT NULL CHECK (direction IN {DIRECTIONS}),
  headword TEXT NOT NULL CHECK (length(trim(headword)) > 0),
  lemma TEXT NOT NULL DEFAULT '',
  pos TEXT NOT NULL DEFAULT '',
  translation TEXT NOT NULL DEFAULT '',
  definition TEXT NOT NULL DEFAULT '',
  example TEXT NOT NULL DEFAULT '',
  example_translation TEXT NOT NULL DEFAULT '',
  source_id INTEGER NOT NULL REFERENCES source(id),
  licence TEXT NOT NULL,                -- snapshot of source.licence (must match, cannot change)
  locator TEXT NOT NULL DEFAULT '',
  engine TEXT NOT NULL,
  confidence REAL NOT NULL DEFAULT 0 CHECK (confidence BETWEEN 0 AND 1),
  compare_result TEXT NOT NULL DEFAULT '',
  compare_detail TEXT NOT NULL DEFAULT '',
  occurrences INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'unverified' CHECK (status IN {STATUSES}),
  reviewer TEXT NOT NULL DEFAULT '',
  review_note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK (status NOT IN ('accepted', 'rejected') OR length(trim(reviewer)) > 0),
  UNIQUE (kind, direction, headword, pos, translation, example, source_id)
);
CREATE INDEX IF NOT EXISTS candidate_head ON candidate(direction, headword);
CREATE INDEX IF NOT EXISTS candidate_status_idx ON candidate(status);

-- Candidates with their source's current permission and the derived private/shared scope.
CREATE VIEW IF NOT EXISTS candidate_status AS
SELECT c.*, ss.kind AS source_kind, ss.lang AS source_lang, ss.permission AS permission,
  CASE WHEN ss.permission = 'allowed' THEN 'shared' ELSE 'private' END AS scope
FROM candidate c JOIN source_status ss ON ss.id = c.source_id;

CREATE TABLE IF NOT EXISTS review_log(
  id INTEGER PRIMARY KEY,
  candidate_id INTEGER NOT NULL REFERENCES candidate(id),
  old_status TEXT NOT NULL,
  new_status TEXT NOT NULL,
  reviewer TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  at TEXT NOT NULL
);
'''


def _now():
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


def _norm_sql(sql):
    return ' '.join((sql or '').split())


class IntegrityError(RuntimeError):
    """The candidate database has been tampered with (a protective trigger is missing or changed)."""


class CandidateStore:
    def __init__(self, path):
        real = check_writable_target(path)
        os.makedirs(os.path.dirname(real) or '.', exist_ok=True)
        self.path = real
        self.db = sqlite3.connect(real)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys = ON')
        self.db.executescript(SCHEMA)
        existing = {r['name'] for r in self.db.execute("SELECT name FROM sqlite_master WHERE type = 'trigger'")}
        for name, sql in TRIGGERS.items():
            if name not in existing:
                self.db.execute(sql)
        self.db.commit()
        self.verify_integrity()

    def close(self):
        self.db.close()

    def verify_integrity(self):
        """Raises IntegrityError when a protective trigger was dropped or rewritten."""
        have = {r['name']: r['sql'] for r in self.db.execute("SELECT name, sql FROM sqlite_master WHERE type = 'trigger'")}
        for name, sql in TRIGGERS.items():
            if _norm_sql(have.get(name)) != _norm_sql(sql):
                raise IntegrityError(f'protective trigger {name} is missing or was changed')

    # ---- sources -------------------------------------------------------------------------------------
    def add_source(self, name, kind, licence, lang, licence_url=''):
        """Registers a source. The declared licence only sets its licence class: the source is never
        shareable until approve_source() records a verification."""
        if kind == 'existing_dictionary':
            raise ValueError('shipped dictionaries are compared read-only and are not candidate sources')
        if lang not in ('en', 'tr'):
            raise ValueError(f'unknown language: {lang}')
        lid, licence_class, note = classify(licence, kind)
        name = (name or '').strip()
        if not name:
            raise ValueError('a source needs a name')
        row = self.db.execute('SELECT * FROM source WHERE name = ?', [name]).fetchone()
        if row:
            if (row['kind'], row['licence'], row['lang']) != (kind, lid, lang):
                raise ValueError(f'source {name!r} already exists with kind={row["kind"]}, licence={row["licence"]}, '
                                 f'lang={row["lang"]}; sources cannot be changed, use a new name')
            return row['id']
        cur = self.db.execute(
            'INSERT INTO source(name, kind, licence, licence_class, licence_url, licence_note, lang, added_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?)', [name, kind, lid, licence_class, licence_url, note, lang, _now()])
        self.db.commit()
        return cur.lastrowid

    def approve_source(self, source_id, approver, evidence):
        """Records that a person verified the source's permissive licence (e.g. checked the licence page).
        Needed before any candidate of the source can be exported. Not possible for user books or for
        share-alike, copyleft, non-commercial and unknown licences."""
        return self._decide(source_id, 'approve', approver, evidence)

    def revoke_source(self, source_id, approver, evidence):
        return self._decide(source_id, 'revoke', approver, evidence)

    def _decide(self, source_id, decision, approver, evidence):
        src = self.source(source_id)
        if src is None:
            raise ValueError(f'unknown source id: {source_id}')
        approver, evidence = (approver or '').strip(), (evidence or '').strip()
        if not approver or not evidence:
            raise ValueError('a licence decision needs the approver name and evidence (licence URL or note)')
        if decision == 'approve' and src['licence_class'] != 'permissive':
            raise ValueError(f'source {src["name"]!r} cannot be approved: {src["licence_note"] or src["licence_class"]}')
        self.db.execute('INSERT INTO source_approval(source_id, decision, approver, evidence, at) VALUES (?, ?, ?, ?, ?)',
                        [source_id, decision, approver, evidence, _now()])
        self.db.commit()

    def source(self, source_id):
        return self.db.execute('SELECT * FROM source_status WHERE id = ?', [source_id]).fetchone()

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
        if src['lang'] != DIRECTION_LANG[direction]:
            raise ValueError(f'source language {src["lang"]} does not match direction {direction}')
        headword = (headword or '').strip()
        if not headword:
            raise ValueError('empty headword')
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
            'example_translation, source_id, licence, locator, engine, confidence, compare_result, '
            'compare_detail, status, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [kind, direction, headword, lemma, pos, translation, definition, example, example_translation,
             source_id, src['licence'], locator, engine, float(confidence), compare_result, detail, status, now, now])
        self.db.commit()
        return cur.lastrowid

    def get(self, candidate_id):
        return self.db.execute('SELECT * FROM candidate_status WHERE id = ?', [candidate_id]).fetchone()

    def count(self):
        return self.db.execute('SELECT COUNT(*) FROM candidate').fetchone()[0]

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

    _COLUMNS = None

    def candidates(self, **where):
        if self._COLUMNS is None:
            self._COLUMNS = {r[1] for r in self.db.execute('PRAGMA table_info(candidate_status)')}
        for k in where:
            if k not in self._COLUMNS:
                raise ValueError(f'unknown column: {k}')
        sql = 'SELECT * FROM candidate_status'
        if where:
            sql += ' WHERE ' + ' AND '.join(f'"{k}" = ?' for k in where)
        return self.db.execute(sql + ' ORDER BY id', list(where.values())).fetchall()

    def summary(self):
        out = {}
        for r in self.db.execute('SELECT direction, kind, compare_result, scope, status, COUNT(*) AS n '
                                 'FROM candidate_status GROUP BY 1, 2, 3, 4, 5 ORDER BY 1, 2, 3, 4, 5'):
            out['|'.join([r['direction'], r['kind'], r['compare_result'], r['scope'], r['status']])] = r['n']
        return out

    def exportable(self):
        """Accepted candidates that pass every sharing rule, re-checked in Python (not only in SQL)."""
        self.verify_integrity()
        rows = self.db.execute(
            "SELECT c.*, s.name AS source_name, s.licence AS source_licence, s.licence_url AS source_licence_url, "
            "s.approved_by AS source_approved_by FROM candidate_status c JOIN source_status s ON s.id = c.source_id "
            "WHERE c.status = 'accepted' AND c.permission = 'allowed' ORDER BY c.id").fetchall()
        out = []
        for r in rows:
            src = self.db.execute('SELECT * FROM source_status WHERE id = ?', [r['source_id']]).fetchone()
            lid, licence_class, _ = classify(src['licence'], src['kind'])
            ok = (src['kind'] != 'user_book' and licence_class == 'permissive' and lid == src['licence']
                  and src['licence_class'] == 'permissive' and src['last_decision'] == 'approve'
                  and r['licence'] == src['licence'] and r['direction'] == {'en': 'en-tr', 'tr': 'tr-en'}[src['lang']]
                  and r['reviewer'].strip() != '')
            if ok:
                out.append(r)
        return out

    def export_reviewed_shared(self, out_path):
        """Writes accepted candidates from verified, permissive sources to a JSONL file for a later, separate,
        human-run dictionary step. Private (user book), unverified, unclear-licence and unreviewed candidates are
        never exported. This does not modify any dictionary."""
        check_writable_target(out_path)
        rows = self.exportable()
        with open(out_path, 'w', encoding='utf-8') as f:
            for r in rows:
                f.write(json.dumps(dict(r), ensure_ascii=False) + '\n')
        return len(rows)
