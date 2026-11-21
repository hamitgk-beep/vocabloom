"""Turkish analysis adapters (independent of the English ones)."""
import re
from abc import ABC, abstractmethod

from .types import Sentence, Token, split_sentences


def _lower(s):
    return s.replace('I', 'ı').replace('İ', 'i').lower().replace('̇', '')


class TurkishAnalyzer(ABC):
    name = ''
    version = ''
    licence = ''

    @abstractmethod
    def analyze(self, text):
        """Returns a list of Sentence objects with tokens (lemma '' when unknown)."""

    @property
    def engine_id(self):
        return f'{self.name}@{self.version}'


_WORD = re.compile(r"[A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû]+|['’]|\d+|[^\s\w]")


class BuiltinTurkishAnalyzer(TurkishAnalyzer):
    """Lexicon-based fallback with no third-party code: an inflected form is mapped to its lemma with the
    form table of the read-only tr_en.db view (`lexicon` needs has_lemma / lemmas_of_form / pos_of).
    Words after an apostrophe split ("Ali'nin") and capitalised words inside a sentence are proper nouns.
    A future Zemberek (Apache-2.0, Java) adapter can implement the same interface."""
    name = 'builtin-tr'
    version = '1'
    licence = 'GPL-3.0 (Storilex source)'

    def __init__(self, lexicon=None):
        self.lexicon = lexicon

    def lemma(self, word):
        w = _lower(word)
        lx = self.lexicon
        if lx is None:
            return w
        if lx.has_lemma(w):
            return w
        lemmas = lx.lemmas_of_form(w)
        return lemmas[0] if lemmas else ''

    def analyze(self, text):
        out = []
        for s in split_sentences(text):
            toks = []
            parts = list(_WORD.finditer(s))
            after_apostrophe = False
            for i, m in enumerate(parts):
                t = m.group(0)
                if t in ("'", '’'):
                    after_apostrophe = True
                    toks.append(Token(t, t, '', False, m.start()))
                    continue
                is_word = t[0].isalpha()
                if not is_word:
                    toks.append(Token(t, t, '', False, m.start()))
                    after_apostrophe = False
                    continue
                if after_apostrophe:  # suffix of a proper noun: "nin" in "Ali'nin"
                    toks.append(Token(t, '', 'SUFFIX', False, m.start()))
                    after_apostrophe = False
                    continue
                nxt_ap = i + 1 < len(parts) and parts[i + 1].group(0) in ("'", '’')
                # Capitalised after the first word of the sentence (a leading dash or quote doesn't count).
                propn = (t[0].isupper() and any(x.is_word for x in toks)) or nxt_ap
                lemma = '' if propn else self.lemma(t)
                pos = 'PROPN' if propn else (self.lexicon.pos_of(lemma) if (self.lexicon and lemma) else '')
                toks.append(Token(t, lemma, pos, True, m.start()))
            out.append(Sentence(s, toks))
        return out


def make_turkish(engine, lexicon=None):
    if engine == 'builtin':
        return BuiltinTurkishAnalyzer(lexicon)
    raise ValueError(f'unknown Turkish engine: {engine} (available: builtin; Zemberek is planned)')
