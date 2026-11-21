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


def split_sentences(text):
    """Small, dependency-free sentence splitter shared by the built-in adapters."""
    import re
    out = []
    for para in re.split(r'\n\s*\n', text):
        para = ' '.join(para.split())
        if not para or para.startswith('#'):
            continue
        for s in re.split(r'(?<=[.!?…])["\'’”)]*\s+(?=["\'‘“(–-]*[A-ZÇĞİÖŞÜ0-9])', para):
            if s.strip():
                out.append(s.strip())
    return out
