"""Read-only comparison of candidates with the two shipped dictionaries.

dict.db  (English -> Turkish): own_word (curated senses), ft (word meanings), sense/syn (WordNet with
                               Turkish), exc (irregular forms), expr/own_expr (phrases: phrasal verbs, idioms ...)
tr_en.db (Turkish -> English): lemma (senses with English glosses), form (inflected form -> lemma)

Both files are opened with SQLite's read-only mode plus `query_only`; nothing is ever written to them.

Results:
  known_headword      the lemma is an entry
  known_form          the word is a known inflected form of an entry (lemma in detail)
  new_headword        not in the dictionary
  known_sense         the candidate's translation already appears among the entry's meanings
  possible_new_sense  the entry exists but the candidate's translation is not among its meanings
  known_phrase / new_phrase   for phrasal verbs, idioms and collocations
"""
import json
import re

from .safety import open_readonly


def fold_tr(s):
    """Lower-cases Turkish correctly (I -> ı, İ -> i) and trims spaces."""
    return s.replace('I', 'ı').replace('İ', 'i').lower().replace('̇', '').strip()


def _split_meanings(text):
    return {fold_tr(p) for p in re.split(r'[,;/]|\s\|\s', text or '') if p.strip()}


def _json_list(text):
    try:
        v = json.loads(text or '[]')
    except ValueError:
        return []
    return v if isinstance(v, list) else []


class EnTrDictionary:
    """Read-only view of assets/dict.db (English -> Turkish)."""

    def __init__(self, path):
        self.db = open_readonly(path)
        names = {r[0] for r in self.db.execute("SELECT name FROM sqlite_master WHERE type IN ('table', 'view')")}
        self._has_own = 'own_word' in names
        self._has_own_expr = 'own_expr' in names

    def close(self):
        self.db.close()

    def _one(self, sql, args):
        return self.db.execute(sql, args).fetchone() is not None

    def has_lemma(self, word):
        w = word.lower()
        if self._has_own and self._one("SELECT 1 FROM own_word WHERE word = ? AND senses != '[]'", [w]):
            return True
        return self._one('SELECT 1 FROM ft WHERE word = ?', [w]) or self._one(
            'SELECT 1 FROM sense WHERE lemma = ? LIMIT 1', [w])

    def is_verb(self, word):
        w = word.lower()
        if self._one("SELECT 1 FROM sense WHERE lemma = ? AND pos = 'v' LIMIT 1", [w]):
            return True
        return self._has_own and self._one("SELECT 1 FROM own_word WHERE word = ? AND senses LIKE '%\"fiil\"%'", [w])

    def irregular_lemmas(self, form):
        return [r[0] for r in self.db.execute('SELECT DISTINCT lemma FROM exc WHERE form = ?', [form.lower()])]

    def translations(self, word):
        w = word.lower()
        out = set()
        if self._has_own:
            for (senses,) in self.db.execute('SELECT senses FROM own_word WHERE word = ?', [w]):
                for s in _json_list(senses):
                    if isinstance(s, dict):
                        out |= _split_meanings(s.get('tr', ''))
        for (tr,) in self.db.execute('SELECT tr FROM ft WHERE word = ?', [w]):
            for t in _json_list(tr):
                out |= _split_meanings(str(t))
        for (tr,) in self.db.execute(
                'SELECT s.tr FROM sense x JOIN syn s ON s.id = x.syn_id WHERE x.lemma = ? AND s.tr IS NOT NULL', [w]):
            for t in _json_list(tr):
                out |= _split_meanings(str(t))
        return out

    def has_phrase(self, phrase):
        p = phrase.lower().strip()
        if self._one('SELECT 1 FROM expr WHERE phrase = ? LIMIT 1', [p]):
            return True
        return self._has_own_expr and self._one('SELECT 1 FROM own_expr WHERE phrase = ? LIMIT 1', [p])


class TrEnDictionary:
    """Read-only view of assets/tr_en.db (Turkish -> English)."""

    def __init__(self, path):
        self.db = open_readonly(path)

    def close(self):
        self.db.close()

    def has_lemma(self, word):
        return self.db.execute('SELECT 1 FROM lemma WHERE word = ?', [fold_tr(word)]).fetchone() is not None

    def lemmas_of_form(self, form):
        return [r[0] for r in self.db.execute(
            'SELECT f.lemma FROM form f JOIN lemma l ON l.word = f.lemma WHERE f.form = ? ORDER BY l.rank',
            [fold_tr(form)])]

    def pos_of(self, lemma):
        r = self.db.execute('SELECT senses FROM lemma WHERE word = ?', [fold_tr(lemma)]).fetchone()
        senses = _json_list(r[0]) if r else []
        return senses[0].get('p', '') if senses and isinstance(senses[0], dict) else ''

    def translations(self, word):
        out = set()
        for (senses,) in self.db.execute('SELECT senses FROM lemma WHERE word = ?', [fold_tr(word)]):
            for s in _json_list(senses):
                if isinstance(s, dict):
                    for g in s.get('g', []):
                        out |= {p.strip().lower() for p in re.split(r'[,;]', str(g)) if p.strip()}
        return out

    def has_phrase(self, phrase):
        return self.has_lemma(phrase)


def compare_word(dictionary, surface, lemma='', translation=''):
    """Classifies one word candidate against a dictionary view. Returns (result, detail)."""
    lemma = lemma or surface
    if dictionary.has_lemma(lemma):
        if translation:
            known = dictionary.translations(lemma)
            t = fold_tr(translation) if isinstance(dictionary, EnTrDictionary) else translation.lower().strip()
            if t in known:
                return 'known_sense', {'lemma': lemma}
            return 'possible_new_sense', {'lemma': lemma, 'known_meanings': len(known)}
        return ('known_headword' if lemma.lower() == surface.lower() else 'known_form'), {'lemma': lemma}
    if isinstance(dictionary, EnTrDictionary):
        irregular = [l for l in dictionary.irregular_lemmas(surface) if dictionary.has_lemma(l)]
        if irregular:
            return 'known_form', {'lemma': irregular[0]}
    else:
        lemmas = dictionary.lemmas_of_form(surface)
        if lemmas:
            return 'known_form', {'lemma': lemmas[0]}
    return 'new_headword', {}


def compare_phrase(dictionary, phrase):
    return ('known_phrase' if dictionary.has_phrase(phrase) else 'new_phrase'), {}
