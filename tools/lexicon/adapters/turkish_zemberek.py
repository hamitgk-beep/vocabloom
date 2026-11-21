"""Optional Turkish analyzer backed by Zemberek-NLP 0.18.0 (Apache-2.0, Java). Set up with
tools/lexicon/setup_zemberek.sh, which downloads checksum-pinned jars into build/lexicon/zemberek.

Zemberek runs as one local `java` child process (ZemberekBridge) that reads sentences on stdin and writes
analyses on stdout. It opens no network connection and reads no files besides its own jars. Only the
analysis is used: Zemberek's own word list is never copied into the candidate store (see LICENSE_REPORT.md).
"""
import glob
import os
import shutil
import subprocess

from .turkish import TurkishAnalyzer, _lower
from .types import Sentence, Token, split_sentences

# Zemberek primary POS -> the word-class names used in tr_en.db senses
_POS = {'Noun': 'noun', 'Verb': 'verb', 'Adj': 'adj', 'Adv': 'adv', 'Pron': 'pron', 'Conj': 'conj',
        'Postp': 'postp', 'Det': 'det', 'Interj': 'interj', 'Ques': 'ques', 'Num': 'NUM', 'Dup': 'dup'}


def default_home():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    return os.environ.get('ZEMBEREK_HOME') or os.path.join(root, 'build', 'lexicon', 'zemberek')


def available(home=None):
    home = home or default_home()
    return bool(shutil.which('java') and os.path.isfile(os.path.join(home, 'classes', 'ZemberekBridge.class'))
                and glob.glob(os.path.join(home, 'lib', 'zemberek-morphology-*.jar')))


class ZemberekTurkishAnalyzer(TurkishAnalyzer):
    """Lemmas and word classes from Zemberek's morphological analysis with disambiguation.
    Proper nouns: Zemberek's proper-noun tag, or a capitalised word after the first word of the sentence.
    Words Zemberek can't analyse, or whose root it only guessed, get an empty lemma (low confidence)."""
    name = 'zemberek-tr'
    version = '0.18.0'
    licence = 'Apache-2.0 (Zemberek-NLP) + Apache-2.0/BSD-3-Clause (dependencies)'

    def __init__(self, lexicon=None, home=None):
        self.lexicon = lexicon
        home = home or default_home()
        if not available(home):
            raise RuntimeError('Zemberek is not set up: run tools/lexicon/setup_zemberek.sh')
        cp = os.pathsep.join([os.path.join(home, 'classes')] + sorted(glob.glob(os.path.join(home, 'lib', '*.jar'))))
        self._proc = subprocess.Popen(['java', '-cp', cp, 'ZemberekBridge'], stdin=subprocess.PIPE,
                                      stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                                      encoding='utf-8', bufsize=1)
        if self._proc.stdout.readline().strip() != 'ready':
            self.close()
            raise RuntimeError('Zemberek bridge did not start')

    def close(self):
        p = getattr(self, '_proc', None)
        if p is not None and p.poll() is None:
            p.stdin.close()
            p.wait(timeout=10)
        if p is not None and not p.stdout.closed:
            p.stdout.close()

    def __del__(self):
        try:
            self.close()
        except Exception:
            pass

    def _analyse(self, sentence):
        self._proc.stdin.write(sentence.replace('\n', ' ') + '\n')
        self._proc.stdin.flush()
        rows = []
        for line in iter(self._proc.stdout.readline, ''):
            if line == '\n':
                break
            rows.append(line.rstrip('\n').split('\t'))
        return rows

    def analyze(self, text):
        out = []
        for s in split_sentences(text):
            toks, pos_in = [], 0
            for surface, lemma, upos, spos, flags in self._analyse(s):
                at = s.find(surface, pos_in)
                start = at if at >= 0 else pos_in
                pos_in = start + len(surface) if at >= 0 else pos_in
                if upos == 'Punc' or not surface[:1].isalpha():
                    toks.append(Token(surface, surface, 'NUM' if upos == 'Num' else '', False, start))
                    continue
                inside = any(t.is_word for t in toks)
                if spos == 'Prop' or (surface[0].isupper() and inside) or "'" in surface or '’' in surface:
                    toks.append(Token(surface, '', 'PROPN', True, start))
                    continue
                # Unknown or guessed roots, and halves of doubled words ("harıl" in "harıl harıl"), get no lemma.
                lem = '' if flags in ('unk', 'runtime') or upos == 'Dup' else _lower(lemma)
                toks.append(Token(surface, lem, _POS.get(upos, upos.lower()), True, start))
            out.append(Sentence(s, toks))
        return out
