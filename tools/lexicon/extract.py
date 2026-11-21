"""Turns analysed text into candidates.

English text -> direction en-tr, compared with dict.db. Turkish text -> direction tr-en, compared with tr_en.db.
What is stored:
  word          lemma not in the dictionary (new_headword); with --include-forms also known_form
  phrasal_verb  English particle verbs not yet in the phrase tables (new_phrase)
  example       one example sentence per known entry and source, as a possible new example
Proper nouns, numbers and one-letter words are skipped. Translations are left empty: they come later from a
person (or a reviewed suggestion) through `add`. Nothing is accepted automatically.
"""
from .adapters.english import EnglishAnalyzer
from .adapters.turkish import TurkishAnalyzer
from .adapters.types import sentence_flags
from .compare import EnTrDictionary, TrEnDictionary, compare_phrase, compare_word

# direction -> (source language, dictionary view type, analyzer base class)
ROUTES = {
    'en-tr': ('en', EnTrDictionary, EnglishAnalyzer),
    'tr-en': ('tr', TrEnDictionary, TurkishAnalyzer),
}


def check_route(store, source_id, direction, dictionary, analyzer=None):
    """Rejects, before anything is written, any mix of source language, direction, dictionary and analyzer
    that doesn't belong together (e.g. an English source with tr_en.db, or a Turkish analyzer for en-tr)."""
    if direction not in ROUTES:
        raise ValueError(f'unknown direction: {direction!r}')
    lang, dict_type, analyzer_type = ROUTES[direction]
    src = store.source(source_id)
    if src is None:
        raise ValueError(f'unknown source id: {source_id}')
    if src['lang'] != lang:
        raise ValueError(f'source {src["name"]!r} is {src["lang"]}, direction {direction} needs a {lang} source')
    if not isinstance(dictionary, dict_type):
        raise ValueError(f'direction {direction} must be compared with {dict_type.__name__}, '
                         f'not {type(dictionary).__name__}')
    if analyzer is not None and not isinstance(analyzer, analyzer_type):
        raise ValueError(f'direction {direction} needs a {analyzer_type.__name__}, not {type(analyzer).__name__}')
    return src

MAX_EXAMPLE_CHARS = 240


def extract(store, analyzer, dictionary, source_id, text, direction, *, locator='', include_forms=False,
            examples=True, max_examples_per_word=1):
    check_route(store, source_id, direction, dictionary, analyzer)
    engine = analyzer.engine_id
    counts = {'sentences': 0, 'word': 0, 'phrasal_verb': 0, 'example': 0}
    examples_for = {}
    for si, sent in enumerate(analyzer.analyze(text)):
        counts['sentences'] += 1
        loc = f'{locator}#s{si + 1}' if locator else f's{si + 1}'
        example = sent.text if len(sent.text) <= MAX_EXAMPLE_CHARS else ''
        # Sentences the simple splitter may have cut wrongly (dialogue fragments, abbreviations ...) still
        # give candidates, but with low confidence and the reason in compare_detail.
        flags = sentence_flags(sent.text)
        penalty = 0.1 if flags else 0.0
        seen = set()
        for tok in sent.tokens:
            if not tok.is_word or tok.pos in ('PROPN', 'NUM', 'SUFFIX') or len(tok.text) < 2:
                continue
            lemma = tok.lemma or ''
            key = (lemma or tok.text).lower()
            if key in seen:
                continue
            seen.add(key)
            result, detail = compare_word(dictionary, tok.text, lemma)
            if result == 'new_headword' or (include_forms and result == 'known_form'):
                head = lemma or tok.text.lower()
                store.add_candidate(kind='word', direction=direction, headword=head, lemma=lemma, pos=tok.pos,
                                    source_id=source_id, engine=engine, locator=loc, example=example,
                                    confidence=round((0.2 if not lemma else 0.4) - penalty, 2), compare_result=result,
                                    compare_detail={**detail, **({'sentence_flags': flags} if flags else {})})
                counts['word'] += 1
            elif examples and example and result in ('known_headword', 'known_form'):
                head = detail.get('lemma', lemma) or key
                if examples_for.get(head, 0) < max_examples_per_word:
                    examples_for[head] = examples_for.get(head, 0) + 1
                    store.add_candidate(kind='example', direction=direction, headword=head, lemma=head,
                                        pos=tok.pos, source_id=source_id, engine=engine, locator=loc,
                                        example=example, confidence=round(0.3 - 2 * penalty, 2), compare_result=result,
                                        compare_detail={**detail, **({'sentence_flags': flags} if flags else {})})
                    counts['example'] += 1
        for ph in sent.phrases:
            result, detail = compare_phrase(dictionary, ph.phrase)
            if result == 'new_phrase':
                store.add_candidate(kind=ph.kind, direction=direction, headword=ph.phrase, source_id=source_id,
                                    engine=engine, locator=loc, example=example,
                                    confidence=round(max(0.0, ph.confidence - penalty), 2), compare_result=result,
                                    compare_detail={**detail, **({'sentence_flags': flags} if flags else {})})
                counts[ph.kind] = counts.get(ph.kind, 0) + 1
    return counts


def add_sense(store, dictionary, source_id, direction, headword, translation, *, pos='', definition='',
              example='', example_translation='', engine='manual', kind='sense'):
    """Adds a meaning candidate for a word or phrase (e.g. a new meaning for an existing word). The
    comparison tells whether the meaning is already known (known_sense) or new (possible_new_sense)."""
    check_route(store, source_id, direction, dictionary)
    if not (translation or '').strip():
        raise ValueError('a sense candidate needs a translation')
    if not (headword or '').strip():
        raise ValueError('empty headword')
    if kind in ('phrasal_verb', 'idiom', 'collocation'):
        result, detail = compare_phrase(dictionary, headword)
    else:
        result, detail = compare_word(dictionary, headword, headword, translation)
    return store.add_candidate(kind=kind, direction=direction, headword=headword.lower().strip(), lemma=headword,
                               pos=pos, translation=translation.strip(), definition=definition, example=example,
                               example_translation=example_translation, source_id=source_id, engine=engine,
                               confidence=0.0, compare_result=result, compare_detail=detail)
