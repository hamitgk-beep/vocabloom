"""Suggests which Turkish meaning of an English word fits a sentence (a hint for reviewers, never an answer).

The curated entries in dict.db (`own_word`) list a word's senses in order, each with a Turkish meaning and English
examples. For a word in a sentence, every sense gets a score from the words it shares with the sentence:

  signature   lemmatised content words of the sense's own examples, plus the definition, examples and synonyms
              of the WordNet synsets (`sense`/`syn`) whose Turkish translation overlaps the sense's Turkish meaning
  weight      rarer words count more (1 / log of the word's count in `wfreq`, the frequency table in dict.db)
  word class  senses whose class (isim/fiil/sıfat/zarf) differs from the word's class in the sentence are skipped,
              when the analyzer gives one and at least one sense matches it
  order       ties go to the earlier sense (the dictionary lists the most common sense first)

  embeddings  optional (embeddings.py): the sentence is compared with the sense's Turkish meaning and linked
              WordNet definitions by a multilingual Sentence Transformers model; word overlap then only adds a little

The result is a ranked list; the first entry is a suggestion with a confidence, not a decision. It is stored only on
candidates in the separate candidate database (see extract.py) and must be reviewed by a person.
Evaluation: eval/evaluate_senses.py.
"""
import math
import re
import sqlite3

from .compare import _json_list, fold_tr

OWN_POS_TO_UPOS = {'isim': 'NOUN', 'fiil': 'VERB', 'deyimsel fiil': 'VERB', 'sıfat': 'ADJ', 'zarf': 'ADV'}
OWN_POS_TO_WN = {'isim': ('n',), 'fiil': ('v',), 'deyimsel fiil': ('v',), 'sıfat': ('a', 's'), 'zarf': ('r',)}

STOPWORDS = set("""
a about above after again against all am an and any are as at be because been before being below between both but by
can could did do does doing down during each few for from further had has have having he her here hers herself him
himself his how i if in into is it its itself just me more most my myself no nor not now of off on once only or other
our ours ourselves out over own same she should so some such than that the their theirs them themselves then there
these they this those through to too under until up very was we were what when where which while who whom why will
with would you your yours yourself yourselves one also us let may might must shall upon thing something someone get
go make take say said like well much many way back come
""".split())

_WORD = re.compile(r"[a-z]+")


def stem(word):
    """Very small suffix stripper, applied to both sides so that 'banks'/'bank', 'rowed'/'row' meet."""
    w = word.lower()
    for suf, rep in (('ies', 'y'), ('ied', 'y'), ('ing', ''), ('ed', ''), ('es', ''), ('s', '')):
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            w = w[:-len(suf)] + rep
            break
    if len(w) > 3 and w[-1] == w[-2] and w[-1] not in 'lsaeiou':
        w = w[:-1]
    return w


def content_words(text, exclude=()):
    ex = {stem(e) for e in exclude}
    out = set()
    for w in _WORD.findall((text or '').lower()):
        if len(w) < 3 or w in STOPWORDS:
            continue
        s = stem(w)
        if s not in ex:
            out.add(s)
    return out


def _tr_parts(text):
    return {fold_tr(p) for p in re.split(r'[,;/]', text or '') if p.strip()}


class SenseRanker:
    """Ranks the curated senses of an English lemma for a context. `dictionary` is an EnTrDictionary."""

    # With sentence embeddings: score = cosine(sentence, meaning) + LEXICAL_WEIGHT * word-overlap score, where
    # "meaning" is the sense's Turkish meaning with its note ("kıyı, yamaç (nehir için)") and the linked WordNet
    # definitions; the best of these counts. A suggestion counts as 'context' when it leads by EMBED_MARGIN.
    LEXICAL_WEIGHT = 0.1
    EMBED_MARGIN = 0.05

    def __init__(self, dictionary, encoder=None):
        self.db = dictionary.db
        self.encoder = encoder          # optional embeddings.SentenceEncoder
        self._cache = {}
        self._freq = {}
        self._glosses = {}

    def _weight(self, stemmed):
        if stemmed not in self._freq:
            try:
                row = self.db.execute('SELECT n FROM wfreq WHERE word = ?', [stemmed]).fetchone()
            except sqlite3.OperationalError:          # a dictionary without the frequency table
                row = None
            self._freq[stemmed] = row[0] if row and row[0] else 0
        return 1.0 / math.log(math.e + self._freq[stemmed] / 1000.0)

    def senses(self, lemma):
        """[(index, sense dict, signature set)] for the lemma's curated senses (empty if it has none)."""
        w = lemma.lower()
        if w in self._cache:
            return self._cache[w]
        row = self.db.execute('SELECT senses FROM own_word WHERE word = ?', [w]).fetchone()
        senses = [s for s in _json_list(row[0])] if row else []
        synsets = self.db.execute(
            'SELECT x.pos, y.gloss, y.examples, y.words, y.tr FROM sense x JOIN syn y ON y.id = x.syn_id '
            'WHERE x.lemma = ?', [w]).fetchall()
        out = []
        for i, s in enumerate(senses):
            if not isinstance(s, dict):
                continue
            text = [s.get('en', ''), s.get('note', '')] + [m.get('en', '') for m in s.get('more') or []
                                                           if isinstance(m, dict)]
            tr = _tr_parts(s.get('tr', ''))
            wn_pos = OWN_POS_TO_WN.get(s.get('pos'), ())
            meaning = s.get('tr', '') + (f" ({s['note']})" if s.get('note') else '')
            glosses = [meaning] if s.get('tr') else []
            for pos, gloss, examples, words, syn_tr in synsets:
                if pos not in wn_pos:
                    continue
                if tr & {p for t in _json_list(syn_tr) for p in _tr_parts(str(t))}:
                    text += [gloss or ''] + [str(e) for e in _json_list(examples)] + [str(x) for x in _json_list(words)]
                    if gloss:
                        glosses.append(gloss)
            self._glosses[(w, i)] = glosses
            out.append((i, s, content_words(' '.join(text), exclude=[w])))
        self._cache[w] = out
        return out

    def rank(self, lemma, context, upos=None):
        """Ranks senses for `context` (a sentence string). Returns [(index, score, sense)], best first."""
        senses = self.senses(lemma)
        if not senses:
            return []
        if upos:
            same = [e for e in senses if OWN_POS_TO_UPOS.get(e[1].get('pos')) == upos]
            if same:
                senses = same
        ctx = content_words(context, exclude=[lemma])
        vec = self.encoder.encode([context])[0] if self.encoder else None
        scored = []
        for i, s, sig in senses:
            score = sum(self._weight(c) for c in ctx & sig)
            if vec is not None:
                texts = self._glosses.get((lemma.lower(), i)) or [s.get('en', '')]
                score = float((self.encoder.encode(texts) @ vec).max()) + self.LEXICAL_WEIGHT * score
            scored.append((i, round(score, 3), s))
        scored.sort(key=lambda e: (-e[1], e[0]))
        return scored

    def suggest(self, lemma, context, upos=None):
        """Best sense as {'index', 'tr', 'pos', 'confidence', 'basis'} or None when the lemma has no curated senses.

        confidence is low on purpose: 0.5 when the context picked a sense clearly (more shared words than any
        other sense, or with embeddings a lead of EMBED_MARGIN), 0.3 when the choice rests on the word class or on
        the order of senses only.
        """
        ranked = self.rank(lemma, context, upos)
        if not ranked:
            return None
        best = ranked[0]
        if len(ranked) == 1:
            by_context = False
        elif self.encoder:
            by_context = best[1] - ranked[1][1] >= self.EMBED_MARGIN
        else:
            by_context = best[1] > 0 and best[1] > ranked[1][1]
        out = {'index': best[0], 'tr': best[2].get('tr', ''), 'pos': best[2].get('pos', ''),
               'confidence': 0.5 if by_context else 0.3, 'basis': 'context' if by_context else 'order'}
        if self.encoder:
            out['encoder'] = self.encoder.engine_id
        return out


