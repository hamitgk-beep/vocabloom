"""Optional word-frequency signal from wordfreq (development machines only; never shipped with the app).

wordfreq 3.1.1 (code Apache-2.0) bundles frequency lists built from Wikipedia, subtitles, news, books and web text;
the data is CC BY-SA 4.0 with attribution (see LICENSE_REPORT.md). Only a number per candidate is kept: the Zipf
value (log10 of uses per billion words; 0 = not in the list). The lists themselves are never copied, and the value
is review metadata in the separate candidate database, not dictionary content.

How extract.py uses it (only when `frequency=` is given, e.g. `run.py extract --wordfreq`):
  zipf / zipf_surface   stored in compare_detail of word candidates, so reviewers can sort by how common a word is
  lemma_suspect         the lemma has Zipf 0 but the word as written is in the list ("unaccounted" -> "unaccount"):
                        probably an analyzer error; confidence drops to 0.1 and
                        suggested_headword holds the written form
Turkish: wordfreq's small_tr list has inflected forms, not dictionary forms ("küflenmek" is 0 while "küflenmiş"
is not), so for Turkish only zipf_surface is meaningful and lemma_suspect is not used.
"""
import importlib.util

INSTALL_HINT = 'wordfreq is not installed: bash tools/lexicon/setup_spacy.sh --with-wordfreq'


def available():
    return importlib.util.find_spec('wordfreq') is not None


class Frequency:
    def __init__(self, lang):
        if not available():
            raise RuntimeError(INSTALL_HINT)
        import wordfreq
        self.lang = lang
        self.version = getattr(wordfreq, '__version__', '') or _dist_version()
        self._zipf = wordfreq.zipf_frequency
        self._cache = {}

    @property
    def source_id(self):
        return f'wordfreq-{self.version}/{self.lang}'

    def zipf(self, word):
        w = (word or '').lower()
        if not w:
            return 0.0
        if w not in self._cache:
            self._cache[w] = self._zipf(w, self.lang)
        return self._cache[w]

    def annotate(self, surface, lemma):
        """{'zipf', 'zipf_surface', 'lemma_suspect'?, 'suggested_headword'?} for a word candidate."""
        out = {'zipf_surface': self.zipf(surface)}
        if lemma and lemma.lower() != surface.lower():
            out['zipf'] = self.zipf(lemma)
            if self.lang == 'en' and out['zipf'] == 0 and out['zipf_surface'] > 0:
                out['lemma_suspect'] = True
                out['suggested_headword'] = surface.lower()
        else:
            out['zipf'] = out['zipf_surface']
        return out


def _dist_version():
    try:
        from importlib.metadata import version
        return version('wordfreq')
    except Exception:  # noqa: BLE001 - only a label
        return 'unknown'
