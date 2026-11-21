"""English analysis adapters (independent of the Turkish ones)."""
import re
from abc import ABC, abstractmethod

from .types import PhraseMatch, Sentence, Token, split_sentences

PARTICLES = {'up', 'down', 'out', 'off', 'in', 'on', 'away', 'back', 'over', 'through', 'around', 'about',
             'along', 'apart', 'aside', 'by', 'forward', 'together'}

# Known words that look like regular forms of another headword but are not ("news" is not "new" + s).
KEEP_AS_WRITTEN = {'its', 'his', 'hers', 'ours', 'yours', 'theirs', 'this', 'thus', 'us', 'yes', 'news', 'always',
                   'perhaps', 'species', 'series', 'means', 'morning', 'evening', 'during', 'nothing', 'something',
                   'anything', 'everything', 'thing', 'ceiling', 'pudding', 'bed', 'red', 'hundred', 'sacred',
                   'wicked', 'naked', 'less', 'unless', 'across', 'besides', 'towards', 'afterwards'}
PREFIXES = ('un', 're', 'dis', 'mis', 'over', 'out', 'under', 'pre', 'non')


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
    version = '2'
    licence = 'GPL-3.0 (Storilex source)'

    def __init__(self, lexicon=None):
        self.lexicon = lexicon

    def lemma(self, word):
        w = word.lower().replace('’', "'")
        lx = self.lexicon
        if lx is None:
            return w
        # Irregular forms first: "sat", "said" and "found" are headwords too, but in running text they are
        # nearly always forms of "sit", "say", "find".
        for l in lx.irregular_lemmas(w):
            if l != w and lx.has_lemma(l):
                return l
        known = lx.has_lemma(w)
        tries = []
        if known and w in KEEP_AS_WRITTEN:
            return w
        verb_forms = []
        if w.endswith('ies') or w.endswith('ied'):
            tries += [w[:-1], w[:-3] + 'y']           # "lies" -> "lie", "studies" -> "study"
        if w.endswith('ing') and len(w) > 5:
            stem = w[:-3]
            verb_forms += [stem, stem + 'e'] + ([stem[:-1]] if len(stem) > 2 and stem[-1] == stem[-2] else [])
        if w.endswith('ed') and len(w) > 4:
            stem = w[:-2]
            verb_forms += [w[:-1], stem] + ([stem[:-1]] if len(stem) > 2 and stem[-1] == stem[-2] else [])
        if w.endswith('es'):
            tries.append(w[:-2])
        # Comparatives and superlatives: braver -> brave, pleasanter -> pleasant, bigger -> big, happier -> happy
        for suf in ('est', 'er'):
            if w.endswith(suf) and len(w) > len(suf) + 2 and not known:   # "dinner", "never" stay
                stem = w[:-len(suf)]
                tries += ([stem[:-1] + 'y'] if stem.endswith('i') else []) + [stem + 'e', stem] + (
                    [stem[:-1]] if len(stem) > 2 and stem[-1] == stem[-2] else [])
        if w.endswith('s') and not w.endswith('ss'):
            tries.append(w[:-1])
        if w.endswith("'s"):
            tries.append(w[:-2])
        # A known word is kept unless it is a regular form of another known word ("thinking" -> "think",
        # "minutes" -> "minute"); without word classes this rule prefers the verb/singular reading.
        is_verb = getattr(lx, 'is_verb', None)
        for t in verb_forms:
            # A known "-ing"/"-ed" word ("morning", "tired") is only reduced to a verb the dictionary has.
            if len(t) > 1 and lx.has_lemma(t) and (not known or is_verb is None or is_verb(t)):
                return t
        for t in tries:
            if len(t) > 1 and lx.has_lemma(t):
                return t
        if known:
            return w
        return self.prefixed(w) or w

    def prefixed(self, word):
        """Lemma of an unknown word made of a prefix and a known word, or None: "redescended" -> "redescend",
        "unplastered" -> "unplastered" ("plastered" is itself a headword)."""
        w = word.lower()
        for prefix in PREFIXES:
            rest = w[len(prefix):]
            if w.startswith(prefix) and len(rest) > 3:
                base = self.lemma(rest)
                if self.lexicon.has_lemma(base):
                    return prefix + base
        return None

    def analyze(self, text):
        out = []
        for s in split_sentences(text):
            toks = []
            for m in _WORD.finditer(s):
                t = m.group(0)
                # Contractions (didn't, it'll) are not dictionary headwords; possessive 's is kept.
                is_word = t[0].isalpha() and not ("'" in t.replace('’', "'") and not t.lower().endswith(("'s", "’s")))
                pos = ''
                if is_word and t[0].isupper() and any(x.is_word for x in toks) and not t.isupper() and t != 'I':
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


# spaCy word classes -> dictionary word classes (see EnTrDictionary.pos_set)
UPOS_TO_DICT = {'NOUN': 'n', 'VERB': 'v', 'ADJ': 'a', 'ADV': 'r'}

# Named-entity labels that mark names rather than dictionary words.
NAME_ENTS = {'PERSON', 'GPE', 'LOC', 'ORG', 'NORP', 'FAC', 'EVENT', 'WORK_OF_ART', 'PRODUCT', 'LANGUAGE'}


class SpacyEnglishAnalyzer(EnglishAnalyzer):
    """spaCy (MIT) with the en_core_web_sm pipeline (MIT). Optional: imported only when chosen.

    - Lemmas: spaCy's lemma when the dictionary knows it, else the built-in rules when they reach a known
      lemma ("having" -> "have"), else spaCy's lemma.
    - Names: PROPN tags and person/place/organisation entities are marked, so they don't become word candidates.
    - Phrasal verbs from the parser's particle relation (`prt`), so "took it off" is found too; a particle
      followed by the verb's own preposition gives a three-word verb ("put up with") when the dictionary has it.
    - Hyphenated compounds stay one token ("new-fangled"), as in the built-in tokenizer."""
    name = 'spacy-en'
    licence = 'MIT (spaCy) + MIT (en_core_web_sm)'

    def __init__(self, model='en_core_web_sm', lexicon=None):
        self._fallback = BuiltinEnglishAnalyzer(lexicon) if lexicon is not None else None
        import spacy  # noqa: lazy, optional dependency
        self.nlp = spacy.load(model)
        self.version = f'{spacy.__version__}/{model}-{self.nlp.meta.get("version", "?")}'
        lic = self.nlp.meta.get('license', '')
        if lic.upper() != 'MIT':
            raise ValueError(f'model {model} licence is {lic!r}; only MIT models are allowed without approval')

    def _lemma(self, t):
        if not t.is_alpha:
            return t.text
        lemma = t.lemma_.lower()
        fb = self._fallback
        surface = t.lower_
        if fb is not None and lemma != surface and hasattr(fb.lexicon, 'pos_set'):
            # "clothes" (noun) is not a form of the verb "clothe": keep the written word when only it has the
            # word class the parser found.
            dp = UPOS_TO_DICT.get(t.pos_)
            if dp and dp not in fb.lexicon.pos_set(lemma) and dp in fb.lexicon.pos_set(surface):
                return surface
        if fb is not None and not fb.lexicon.has_lemma(lemma):
            alt = fb.lemma(t.text)
            if fb.lexicon.has_lemma(alt):
                return alt
            # spaCy guesses unknown words badly ("recoated" -> "recoate"); a prefix + known word is safer.
            alt = fb.prefixed(surface)
            if alt:
                return alt
        return lemma

    @staticmethod
    def _is_word(t):
        if not t.is_alpha:
            return False
        # Contractions are split by spaCy ("did" + "n't"); "n't", "'ll" are not alphabetic, so they drop out.
        return True

    def analyze(self, text):
        sentences = split_sentences(text)
        out = []
        for s, doc in zip(sentences, self.nlp.pipe(sentences, batch_size=64)):
            toks = []
            i = 0
            while i < len(doc):
                t = doc[i]
                # spaCy splits hyphenated compounds ("new-fangled", "bed-clothes"); the pieces are not the words
                # the text uses, so the compound is kept whole, like the built-in tokenizer does.
                j = i
                while (j + 2 < len(doc) and doc[j + 1].text == '-' and not doc[j].whitespace_
                       and not doc[j + 1].whitespace_ and doc[j].is_alpha and doc[j + 2].is_alpha):
                    j += 2
                if j > i:
                    span = doc[i:j + 1]
                    # A plural noun compound is reduced to its singular ("bed-posts" -> "bed-post"); others stay
                    # as written ("softer-hearted", not "softer-heart").
                    last = self._lemma(doc[j]) if doc[j].pos_ == 'NOUN' else doc[j].lower_
                    lemma = span[:-1].text.lower() + last
                    toks.append(Token(span.text, lemma, doc[j].pos_, True, t.idx, ''))
                    i = j + 1
                    continue
                pos = t.pos_
                # Only the name itself, not words inside the entity span ("the" in "the Scarecrow").
                ent = t.ent_type_ if t.ent_type_ in NAME_ENTS and (pos == 'PROPN' or t.text[:1].isupper()) else ''
                toks.append(Token(t.text, self._lemma(t), pos, self._is_word(t), t.idx, ent))
                i += 1
            sent = Sentence(s, toks)
            for t in doc:
                # Verb + direct object ("make a decision" -> "make decision"): collocation evidence, counted
                # over the whole text by extract() before anything is stored.
                # Not for particle verbs: "took up the cry" is "take up" + object, not "take cry".
                if (t.dep_ == 'dobj' and t.pos_ == 'NOUN' and t.head.pos_ == 'VERB' and not t.ent_type_
                        and t.is_alpha and t.head.is_alpha
                        and not any(c.dep_ in ('prt', 'compound:prt') for c in t.head.children)
                        and not _in_hyphen_compound(doc, t.i)):
                    sent.phrases.append(PhraseMatch(f'{self._lemma(t.head)} {self._lemma(t)}', 'collocation', 0.2))
                if (t.dep_ not in ('prt', 'compound:prt') or t.head.pos_ not in ('VERB', 'AUX')
                        or t.lower_ not in PARTICLES):
                    continue
                verb = self._lemma(t.head)
                if verb == 'be':      # "the sun was up": an adjective use, not a phrasal verb
                    continue
                prep = next((c for c in t.head.children if c.dep_ == 'prep' and c.i == t.i + 1), None)
                # A preposition after the particle is usually just the start of a phrase ("set off for Kent"),
                # so a three-word verb is only reported when the dictionary already has it.
                if prep is not None and self._fallback is not None and self._fallback.lexicon.has_phrase(
                        f'{verb} {t.lower_} {prep.lower_}'):
                    sent.phrases.append(PhraseMatch(f'{verb} {t.lower_} {prep.lower_}', 'phrasal_verb', 0.6))
                sent.phrases.append(PhraseMatch(f'{verb} {t.lower_}', 'phrasal_verb', 0.6))
            out.append(sent)
        return out


def _in_hyphen_compound(doc, i):
    """True for "mother" in "mother-in-law"."""
    return ((i + 1 < len(doc) and doc[i + 1].text == '-' and not doc[i].whitespace_)
            or (i > 0 and doc[i - 1].text == '-' and not doc[i - 1].whitespace_))


def make_english(engine, lexicon=None):
    if engine == 'builtin':
        return BuiltinEnglishAnalyzer(lexicon)
    if engine == 'spacy':
        return SpacyEnglishAnalyzer(lexicon=lexicon)
    raise ValueError(f'unknown English engine: {engine} (choose builtin or spacy)')
