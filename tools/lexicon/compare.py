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


_CIRCUMFLEX = str.maketrans('âîûÂÎÛ', 'aiuAIU')


def _tr_keys(word):
    """Lookup keys for a Turkish word: as written, then without circumflexes ("hakikî" -> "hakiki")."""
    k = fold_tr(word)
    plain = k.translate(_CIRCUMFLEX)
    return [k] if plain == k else [k, plain]


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

    # Dictionary word classes: WordNet letters in `sense`, Turkish labels in own_word senses.
    _OWN_POS = {'isim': 'n', 'fiil': 'v', 'deyimsel fiil': 'v', 'sıfat': 'a', 'zarf': 'r'}

    def pos_set(self, word):
        """Word classes the dictionary lists for a lemma: subset of {'n', 'v', 'a', 'r'} (empty = unknown)."""
        w = word.lower()
        out = {('a' if p == 's' else p) for (p,) in self.db.execute('SELECT DISTINCT pos FROM sense WHERE lemma = ?', [w])}
        if self._has_own:
            for (senses,) in self.db.execute('SELECT senses FROM own_word WHERE word = ?', [w]):
                for s in _json_list(senses):
                    if isinstance(s, dict) and s.get('pos') in self._OWN_POS:
                        out.add(self._OWN_POS[s['pos']])
        return out & {'n', 'v', 'a', 'r'}

    _phrases = None
    # Phrase categories matched in running text, and the candidate kind they map to.
    PHRASE_CATS = {'idioms': 'idiom', 'proverbs': 'idiom', 'similes': 'idiom', 'binomials': 'idiom',
                   'phrasal_verbs': 'phrasal_verb', 'collocations': 'collocation'}

    def phrase_index(self):
        """Known multi-word phrases by first word: {first: [(tokens, phrase, kind)]}, longest first."""
        if self._phrases is None:
            idx = {}
            sql = 'SELECT phrase, cat FROM expr'
            if self._has_own_expr:
                sql += ' UNION SELECT phrase, cat FROM own_expr'
            for phrase, cat in self.db.execute(sql):
                kind = self.PHRASE_CATS.get(cat)
                toks = tuple(re.findall(r"[a-z]+(?:'[a-z]+)?", (phrase or '').lower()))
                if kind is None or not 2 <= len(toks) <= 6:
                    continue
                idx.setdefault(toks[0], []).append((toks, phrase.lower(), kind))
            for v in idx.values():
                v.sort(key=lambda e: -len(e[0]))
            self._phrases = idx
        return self._phrases


class TrEnDictionary:
    """Read-only view of assets/tr_en.db (Turkish -> English)."""

    def __init__(self, path):
        self.db = open_readonly(path)

    def close(self):
        self.db.close()

    def lemma_key(self, word):
        """The headword as tr_en.db spells it ("hakikî" -> "hakiki"), or None."""
        for k in _tr_keys(word):
            if self.db.execute('SELECT 1 FROM lemma WHERE word = ?', [k]).fetchone():
                return k
        return None

    def has_lemma(self, word):
        return self.lemma_key(word) is not None

    def lemmas_of_form(self, form):
        return [r[0] for r in self.db.execute(
            'SELECT f.lemma FROM form f JOIN lemma l ON l.word = f.lemma WHERE f.form = ? ORDER BY l.rank',
            [fold_tr(form)])]

    def pos_of(self, lemma):
        r = self.db.execute('SELECT senses FROM lemma WHERE word = ?', [self.lemma_key(lemma) or '']).fetchone()
        senses = _json_list(r[0]) if r else []
        return senses[0].get('p', '') if senses and isinstance(senses[0], dict) else ''

    def translations(self, word):
        out = set()
        for (senses,) in self.db.execute('SELECT senses FROM lemma WHERE word = ?', [self.lemma_key(word) or '']):
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
    if hasattr(dictionary, 'lemma_key') and dictionary.has_lemma(lemma):
        same = fold_tr(lemma) == fold_tr(surface)
        lemma = dictionary.lemma_key(lemma)        # dictionary spelling ("hakikî" -> "hakiki")
        if same:
            surface = lemma
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
        # The analyzer's lemma may itself be a listed form ("fevkalâde" -> "fevkalade"), else the word as written.
        for w in dict.fromkeys([lemma, surface]):
            for k in _tr_keys(w):
                lemmas = dictionary.lemmas_of_form(k)
                if lemmas:
                    return 'known_form', {'lemma': lemmas[0]}
    return 'new_headword', {}


def compare_phrase(dictionary, phrase):
    """known_phrase when the phrase, or a verb-object pair with an article or "one's" ("make decision" ->
    "make a decision"), is in the dictionary."""
    if dictionary.has_phrase(phrase):
        return 'known_phrase', {}
    parts = phrase.split()
    if len(parts) == 2:
        for filler in ('a', 'an', 'the', "one's", 'some'):
            alt = f'{parts[0]} {filler} {parts[1]}'
            if dictionary.has_phrase(alt):
                return 'known_phrase', {'as': alt}
    return 'new_phrase', {}


# Placeholders in dictionary phrases ("pull someone's leg") and the words that may stand for them.
_POSSESSIVES = {'my', 'your', 'his', 'her', 'its', 'our', 'their'}
_SLOTS = {'someone', 'somebody', 'something', 'sb', 'sth', "someone's", "somebody's", "one's"}


def _slot_ok(slot, word):
    if slot in ("one's", "someone's", "somebody's"):
        return word in _POSSESSIVES or word.endswith("'s")
    return True


def find_known_phrases(dictionary, tokens):
    """Known dictionary phrases in a token list, matched on lemmas or on the words as written, so inflected
    uses are found ("broke the ice" -> "break the ice"). Returns [(phrase, kind, start, end)]."""
    if not hasattr(dictionary, 'phrase_index'):
        return []
    idx = dictionary.phrase_index()
    words = [(t.lemma or t.text).lower() for t in tokens if t.is_word]
    surface = [t.text.lower() for t in tokens if t.is_word]
    found, i = [], 0
    while i < len(words):
        hit = None
        for key in {words[i], surface[i]}:
            for toks, phrase, kind in idx.get(key, ()):
                n = len(toks)
                if i + n > len(words):
                    continue
                if all(t == words[i + k] or t == surface[i + k] or (t in _SLOTS and _slot_ok(t, surface[i + k]))
                       for k, t in enumerate(toks)) and toks[0] not in _SLOTS:
                    if hit is None or n > hit[3] - hit[2]:
                        hit = (phrase, kind, i, i + n)
                    break
        if hit:
            found.append(hit)
            i = hit[3]
        else:
            i += 1
    return found
