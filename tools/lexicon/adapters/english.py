"""English analysis adapters (independent of the Turkish ones)."""
import re
from abc import ABC, abstractmethod

from .types import PhraseMatch, Sentence, Token, split_sentences

PARTICLES = {'up', 'down', 'out', 'off', 'in', 'on', 'away', 'back', 'over', 'through', 'around', 'about',
             'along', 'apart', 'aside', 'by', 'forward', 'together'}


class EnglishAnalyzer(ABC):
    name = ''
    version = ''
    licence = ''      # licence of the engine *and* any model it loads

    @abstractmethod
    def analyze(self, text):
        """Returns a list of Sentence objects with tokens and phrase matches."""

    @property
    def engine_id(self):
        return f'{self.name}@{self.version}'


_WORD = re.compile(r"[A-Za-z]+(?:['’-][A-Za-z]+)*|\d+|[^\sA-Za-z\d]")


class BuiltinEnglishAnalyzer(EnglishAnalyzer):
    """Rule-based fallback with no third-party code. Lemmas come from the irregular-form table and simple
    suffix rules checked against `lexicon` (any object with has_lemma / irregular_lemmas, e.g. the read-only
    dict.db view). Phrasal verbs are only reported when the particle ends the clause ("she gave up."), or when
    the phrase is already known, so the rule stays conservative."""
    name = 'builtin-en'
    version = '1'
    licence = 'GPL-3.0 (Storilex source)'

    def __init__(self, lexicon=None):
        self.lexicon = lexicon

    def lemma(self, word):
        w = word.lower().replace('’', "'")
        lx = self.lexicon
        if lx is None:
            return w
        if lx.has_lemma(w):
            return w
        for l in lx.irregular_lemmas(w):
            if lx.has_lemma(l):
                return l
        tries = []
        if w.endswith('ies') or w.endswith('ied'):
            tries.append(w[:-3] + 'y')
        if w.endswith('ing') and len(w) > 5:
            stem = w[:-3]
            tries += [stem, stem + 'e'] + ([stem[:-1]] if len(stem) > 2 and stem[-1] == stem[-2] else [])
        if w.endswith('ed') and len(w) > 4:
            stem = w[:-2]
            tries += [stem, w[:-1]] + ([stem[:-1]] if len(stem) > 2 and stem[-1] == stem[-2] else [])
        if w.endswith('es'):
            tries.append(w[:-2])
        if w.endswith('s') and not w.endswith('ss'):
            tries.append(w[:-1])
        if w.endswith("'s"):
            tries.append(w[:-2])
        for t in tries:
            if len(t) > 1 and lx.has_lemma(t):
                return t
        return w

    def analyze(self, text):
        out = []
        for s in split_sentences(text):
            toks = []
            for i, m in enumerate(_WORD.finditer(s)):
                t = m.group(0)
                # Contractions (didn't, it'll) are not dictionary headwords; possessive 's is kept.
                is_word = t[0].isalpha() and not ("'" in t.replace('’', "'") and not t.lower().endswith(("'s", "’s")))
                pos = ''
                if is_word and t[0].isupper() and i > 0 and not t.isupper() and t != 'I':
                    pos = 'PROPN'
                toks.append(Token(t, self.lemma(t) if is_word else t, pos, is_word, m.start()))
            sent = Sentence(s, toks)
            for i in range(len(toks) - 1):
                a, b = toks[i], toks[i + 1]
                if not (a.is_word and b.is_word) or a.pos == 'PROPN' or b.text.lower() not in PARTICLES:
                    continue
                is_verb = getattr(self.lexicon, 'is_verb', None)
                if is_verb is not None and not is_verb(a.lemma):
                    continue
                phrase = f'{a.lemma} {b.text.lower()}'
                known = self.lexicon is not None and self.lexicon.has_phrase(phrase)
                nxt = toks[i + 2] if i + 2 < len(toks) else None
                clause_end = nxt is None or not nxt.is_word
                if known or clause_end:
                    sent.phrases.append(PhraseMatch(phrase, 'phrasal_verb', 0.5 if known else 0.3))
            out.append(sent)
        return out


class SpacyEnglishAnalyzer(EnglishAnalyzer):
    """spaCy (MIT) with the en_core_web_sm pipeline (MIT). Optional: imported only when chosen.
    Phrasal verbs come from the parser's particle relation (`prt`), so "took it off" is found too."""
    name = 'spacy-en'
    licence = 'MIT (spaCy) + MIT (en_core_web_sm)'

    def __init__(self, model='en_core_web_sm', lexicon=None):
        # With a lexicon, a lemma spaCy gets wrong ("having") falls back to the built-in rules.
        self._fallback = BuiltinEnglishAnalyzer(lexicon) if lexicon is not None else None
        import spacy  # noqa: lazy, optional dependency
        self.nlp = spacy.load(model, disable=['ner'])
        self.version = f'{spacy.__version__}/{model}-{self.nlp.meta.get("version", "?")}'
        lic = self.nlp.meta.get('license', '')
        if lic.upper() != 'MIT':
            raise ValueError(f'model {model} licence is {lic!r}; only MIT models are allowed without approval')

    def _lemma(self, t):
        if not t.is_alpha:
            return t.text
        lemma = t.lemma_.lower()
        fb = self._fallback
        if fb is not None and not fb.lexicon.has_lemma(lemma):
            alt = fb.lemma(t.text)
            if fb.lexicon.has_lemma(alt):
                return alt
        return lemma

    def analyze(self, text):
        out = []
        for s in split_sentences(text):
            doc = self.nlp(s)
            toks = [Token(t.text, self._lemma(t), t.pos_, t.is_alpha, t.idx) for t in doc]
            sent = Sentence(s, toks)
            for t in doc:
                if t.dep_ in ('prt', 'compound:prt') and t.head.pos_ in ('VERB', 'AUX'):
                    sent.phrases.append(PhraseMatch(f'{t.head.lemma_.lower()} {t.lower_}', 'phrasal_verb', 0.6))
            out.append(sent)
        return out


def make_english(engine, lexicon=None):
    if engine == 'builtin':
        return BuiltinEnglishAnalyzer(lexicon)
    if engine == 'spacy':
        return SpacyEnglishAnalyzer(lexicon=lexicon)
    raise ValueError(f'unknown English engine: {engine} (choose builtin or spacy)')
