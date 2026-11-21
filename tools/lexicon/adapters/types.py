from dataclasses import dataclass, field


@dataclass
class Token:
    text: str
    lemma: str
    pos: str = ''          # Universal POS tag when the engine knows it (NOUN, VERB, PROPN ...), else ''
    is_word: bool = True   # False for punctuation, numbers and symbols
    start: int = 0         # character offset in the sentence


@dataclass
class PhraseMatch:
    phrase: str            # normalised phrase, e.g. "give up"
    kind: str              # 'phrasal_verb', 'idiom', 'collocation'
    confidence: float


@dataclass
class Sentence:
    text: str
    tokens: list = field(default_factory=list)
    phrases: list = field(default_factory=list)


import re

# Words that end with a full stop without ending the sentence (compared case-insensitively, without the dot).
ABBREVIATIONS = {
    # English
    'mr', 'mrs', 'ms', 'dr', 'st', 'prof', 'jr', 'sr', 'vs', 'etc', 'e.g', 'i.e', 'no', 'mt', 'capt', 'col',
    'gen', 'lt', 'sgt', 'rev', 'fig', 'approx', 'u.s', 'u.k',
    # Turkish
    'doç', 'av', 'yrd', 'bkz', 'vb', 'vd', 'sn', 'alb', 'org', 'örn', 'yy', 'bşk', 'müd',
}

_BOUNDARY = re.compile(r'([.!?…]+)(["\'’”)»]*)\s+(?=["\'‘“(«–—-]*\s*[A-ZÇĞİÖŞÜÂÎÛ0-9])')
_PREV_WORD = re.compile(r'([\wçğıöşüÇĞİÖŞÜ.]+)$')


def _is_abbreviation(text_before):
    m = _PREV_WORD.search(text_before)
    if not m:
        return False
    w = m.group(1).rstrip('.').lower()
    return w in ABBREVIATIONS or (len(w) == 1 and w.isalpha())  # "J. K. Rowling"


def split_sentences(text):
    """Small, dependency-free sentence splitter shared by the built-in adapters.

    Splits after . ! ? … (and closing quotes) when the next word starts with a capital letter (Turkish capitals
    included) or a digit. Does not split after known abbreviations ("Mr.", "Dr.", "vb.") or single-letter
    initials. Known limits: speech followed by a capitalised verb of saying is cut ("– Ver elini! Ver elini!
    diye seslendi." gives two pieces) and an abbreviation at the real end of a sentence joins two sentences.
    `sentence_flags` marks such pieces so their candidates get a low confidence."""
    out = []
    for para in re.split(r'\n\s*\n', text):
        para = ' '.join(para.split())
        if not para or para.startswith('#'):
            continue
        start = 0
        for m in _BOUNDARY.finditer(para):
            if m.group(1) == '.' and _is_abbreviation(para[start:m.start()]):
                continue
            piece = para[start:m.end(2) if m.group(2) else m.end(1)].strip()
            if piece:
                out.append(piece)
            start = m.end()
        rest = para[start:].strip()
        if rest:
            out.append(rest)
    return out


def sentence_flags(sentence):
    """Reasons a piece from split_sentences may not be a clean, complete sentence (empty list when fine)."""
    flags = []
    words = re.findall(r'[^\W\d_]+', sentence)
    if len(words) < 3:
        flags.append('short')
    if sentence.count('"') % 2 or sentence.count('“') != sentence.count('”') or \
            sentence.count('«') != sentence.count('»'):
        flags.append('unbalanced_quotes')
    first = next((ch for ch in sentence if ch.isalpha()), '')
    if first and first.islower():
        flags.append('starts_lowercase')
    if re.search(r'[!?…]["\'’”]?\s+[a-zçğıöşü]', sentence):
        flags.append('speech_inside')        # "Ver elini! diye seslendi": possibly the tail of a cut dialogue
    if not re.search(r'[.!?…]["\'’”)»]*$', sentence):
        flags.append('no_final_punctuation')
    if any(re.search(r'(?<![\w.])' + re.escape(a) + r'\.', sentence.lower()) for a in ABBREVIATIONS if len(a) > 1):
        flags.append('abbreviation')
    return flags
