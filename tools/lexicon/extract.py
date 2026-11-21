"""Turns analysed text into candidates.

English text -> direction en-tr, compared with dict.db. Turkish text -> direction tr-en, compared with tr_en.db.
What is stored (see extract() for the rules and confidences):
  word          lemma not in the dictionary (new_headword); with --include-forms also known_form
  phrasal_verb  English particle verbs not yet in the phrase tables (new_phrase)
  collocation   repeated verb + object pairs not in the phrase tables (spaCy)
  sense         known words used with a word class the dictionary doesn't list (possible_new_sense, spaCy)
  example       one example sentence per known entry or known phrase and source, as a possible new example
Proper names, numbers, abbreviations and one-letter words are skipped. Translations are left empty: they come
later from a person through `add-sense`. Nothing is accepted automatically.
"""
from .adapters.english import EnglishAnalyzer
from .adapters.turkish import TurkishAnalyzer
from .adapters.types import ABBREVIATIONS, SPEECH_OPENERS, sentence_flags
from .compare import EnTrDictionary, TrEnDictionary, compare_phrase, compare_word, find_known_phrases
from .senses import SenseRanker

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
# spaCy word classes -> dictionary word classes (see EnTrDictionary.pos_set)
UPOS_TO_DICT = {'NOUN': 'n', 'VERB': 'v', 'ADJ': 'a', 'ADV': 'r'}
# Word-class gaps reported as possible new senses: noun <-> verb only. With the small English model, adjective
# and adverb tags on known words were mostly tagging errors ("motionless" as a noun) in the evaluation.
SENSE_GAP_POS = ('n', 'v')
NAME_POS = ('PROPN',)


def name_evidence(sentences):
    """Document-level proper-name test, so a name that only starts sentences ("Dinah was ...") is still
    caught when it is a name elsewhere. Returns (names, sentence_initial_only):
      names                  words tagged PROPN / name entity in at least half their uses, or never written in
                             lower case and capitalised at least once inside a sentence
      sentence_initial_only  capitalised words seen only at the start of sentences (can't tell; low confidence)"""
    stats = {}
    for sent in sentences:
        first = True
        for t in sent.tokens:
            if not t.is_word:
                if t.text in SPEECH_OPENERS:     # quoted speech starts with a capital: like a sentence start
                    first = True
                continue
            w = t.text.lower()
            st = stats.setdefault(w, [0, 0, 0, 0, 0])  # uses, tagged name, lower case, capital inside, capital at start
            st[0] += 1
            if t.pos in NAME_POS or t.ent:
                st[1] += 1
            if t.text[:1].islower():
                st[2] += 1
            elif first:
                st[4] += 1
            else:
                st[3] += 1
            first = False
    names, initial_only = set(), set()
    for w, (uses, tagged, lower, cap_inside, cap_start) in stats.items():
        if w == 'i':
            continue
        if tagged * 2 >= uses or (lower == 0 and cap_inside > 0):
            names.add(w)
        elif lower == 0 and cap_inside == 0 and cap_start > 0:
            initial_only.add(w)
    return names, initial_only


def _compound(dictionary, word):
    """For a hyphenated word not in the dictionary: None when it should not be a candidate (the dictionary has it
    written as one word or with spaces, or it is an archaic "a-" verb form like "a-going"), True when every part
    is a known word, False otherwise."""
    parts = word.split('-')
    if parts[0] == 'a' and len(parts) == 2:
        return None
    if dictionary.has_lemma(''.join(parts)) or dictionary.has_phrase(' '.join(parts)) or dictionary.has_lemma(
            ' '.join(parts)):
        return None
    return all(len(p) > 1 and _known_part(dictionary, p) for p in parts)


_PART_SUFFIXES = ('s', 'es', 'd', 'ed', 'er', 'est', 'ing', 'ly', 'y')


def _known_part(dictionary, part):
    """A compound part is known when it, or it without a common ending, is a headword ("softer", "hearted")."""
    if dictionary.has_lemma(part):
        return True
    for suf, repl in (('ier', 'y'), ('iest', 'y'), ('ing', 'e'), ('ed', 'e'), ('ies', 'y')):
        if part.endswith(suf) and dictionary.has_lemma(part[:-len(suf)] + repl):   # "kindlier", "disclosing"
            return True
    return any(part.endswith(suf) and len(part) - len(suf) > 1 and dictionary.has_lemma(part[:-len(suf)])
               for suf in _PART_SUFFIXES)


def extract(store, analyzer, dictionary, source_id, text, direction, *, locator='', include_forms=False,
            examples=True, max_examples_per_word=1, min_collocation=2, min_pos_gap=3,
            min_pos_share=0.2, frequency=None, encoder=None):
    """Analyses a whole text, then stores candidates:
      word          lemmas not in the dictionary (proper names left out; dialect spellings with a dropped
                    letter, "kep'", and hyphenated compounds of known words get confidence 0.1)
      phrasal_verb  particle verbs not in the phrase tables
      collocation   verb + object pairs seen at least `min_collocation` times and not in the phrase tables (spaCy)
      sense         a known word used as a word class the dictionary doesn't list, at least `min_pos_gap` times
                    and in at least `min_pos_share` of its uses (spaCy; e.g. a noun-only entry used as a verb):
                    possible missing meaning, no translation
      example       one sentence per known word or known phrase (idioms, phrasal verbs ...) and source; for an
                    English word with several curated senses, compare_detail.sense_hint suggests the fitting one
                    (senses.py, confidence 0.3-0.5, to be checked by a person)
    frequency: an optional frequency.Frequency; word candidates then carry Zipf values in compare_detail and a
    `lemma_suspect` flag (confidence 0.1) when the lemma is unknown to wordfreq but the written word is not.
    encoder: an optional embeddings.SentenceEncoder for the sense hints (see senses.py)."""
    check_route(store, source_id, direction, dictionary, analyzer)
    engine = analyzer.engine_id
    counts = {'sentences': 0, 'word': 0, 'phrasal_verb': 0, 'collocation': 0, 'sense': 0, 'example': 0,
              'names_skipped': 0}
    sentences = analyzer.analyze(text)
    counts['sentences'] = len(sentences)
    names, initial_only = name_evidence(sentences)
    examples_for = {}
    colloc = {}      # phrase -> [count, first locator, first example, flags]
    pos_uses = {}    # (lemma, dict pos) -> [count, upos, first locator, first example]
    lemma_uses = {}  # lemma -> uses in the text (any word class)
    # Curated English senses: example candidates of a word with several senses get a suggested sense.
    ranker = SenseRanker(dictionary, encoder) if direction == 'en-tr' and getattr(dictionary, '_has_own', False) else None

    def detail_with(detail, flags, **extra):
        out = {**detail, **extra}
        if flags:
            out['sentence_flags'] = flags
        return out

    def add_example(head, kind_detail, loc, example, flags, penalty, pos=''):
        if not (examples and example) or examples_for.get(head, 0) >= max_examples_per_word:
            return
        examples_for[head] = examples_for.get(head, 0) + 1
        extra = {}
        if ranker is not None and kind_detail[0] != 'known_phrase' and len(ranker.senses(head)) > 1:
            hint = ranker.suggest(head, example, pos or None)   # a reviewer's hint, never the answer
            if hint:
                extra['sense_hint'] = hint
        store.add_candidate(kind='example', direction=direction, headword=head, lemma=head, pos=pos,
                            source_id=source_id, engine=engine, locator=loc, example=example,
                            confidence=round(0.3 - 2 * penalty, 2), compare_result=kind_detail[0],
                            compare_detail=detail_with(kind_detail[1], flags, **extra))
        counts['example'] += 1

    for si, sent in enumerate(sentences):
        loc = f'{locator}#s{si + 1}' if locator else f's{si + 1}'
        example = sent.text if len(sent.text) <= MAX_EXAMPLE_CHARS else ''
        # Sentences the simple splitter may have cut wrongly (dialogue fragments, abbreviations ...) still
        # give candidates, but with low confidence and the reason in compare_detail.
        flags = sentence_flags(sent.text)
        penalty = 0.1 if flags else 0.0
        seen = set()
        for tok in sent.tokens:
            if not tok.is_word or tok.pos in ('PROPN', 'NUM', 'SUFFIX') or tok.ent or len(tok.text) < 2:
                if tok.is_word and (tok.pos == 'PROPN' or tok.ent):
                    counts['names_skipped'] += 1
                continue
            lower = tok.text.lower()
            end = tok.start + len(tok.text)
            if lower in ABBREVIATIONS and sent.text[end:end + 1] == '.':
                continue                           # "etc.", "Mr.": abbreviations, not headwords
            after, before = sent.text[end:end + 1], sent.text[tok.start - 1:tok.start] if tok.start else ''
            # "kep'", "stickin'", "'nough", "'Tis": dialect spelling with a dropped letter
            elided = ((after in ("'", '’') and not sent.text[end + 1:end + 2].isalpha()) or before in ("'", '’'))
            if lower in names:
                counts['names_skipped'] += 1
                continue
            lemma = tok.lemma or ''
            key = (lemma or tok.text).lower()
            if key in seen:
                continue
            seen.add(key)
            result, detail = compare_word(dictionary, tok.text, lemma)
            compound = None
            if result == 'new_headword' and '-' in key:
                # Checked as written and as lemma ("bed-posts" may be in the dictionary as "bedpost").
                written, base = _compound(dictionary, lower), _compound(dictionary, key)
                compound = None if written is None or base is None else base
                if compound is None:
                    continue
            if result == 'new_headword' or (include_forms and result == 'known_form'):
                head = lemma or lower
                conf = 0.2 if not lemma else 0.4
                extra = {}
                if compound:                       # "sea-cook": every part is a known word, lower priority
                    conf, extra = 0.1, {'compound': True}
                if elided:
                    conf, extra = 0.1, {'elided': True}
                elif tok.pos == 'INTJ':            # "ch-chow-wow!": sounds, rarely dictionary words
                    conf, extra = 0.1, {'interjection': True}
                if lower in initial_only:          # "Dinah was ..." with no other use: may be a name
                    conf, extra = 0.1, {'possible_name': True}
                if frequency is not None:          # optional wordfreq signal (frequency.py)
                    fq = frequency.annotate(tok.text, lemma)
                    if fq.get('lemma_suspect'):    # "anywher": the lemma is unknown, the written word common
                        conf = 0.1
                    extra = {**extra, **fq}
                store.add_candidate(kind='word', direction=direction, headword=head, lemma=lemma, pos=tok.pos,
                                    source_id=source_id, engine=engine, locator=loc, example=example,
                                    confidence=round(max(0.0, conf - penalty), 2), compare_result=result,
                                    compare_detail=detail_with(detail, flags, **extra))
                counts['word'] += 1
            elif result in ('known_headword', 'known_form'):
                head = detail.get('lemma', lemma) or key
                add_example(head, (result, detail), loc, example, flags, penalty, tok.pos)
                dpos = UPOS_TO_DICT.get(tok.pos)
                lemma_uses[head] = lemma_uses.get(head, 0) + 1
                if dpos in SENSE_GAP_POS and not elided and hasattr(dictionary, 'pos_set'):
                    st = pos_uses.setdefault((head, dpos), [0, tok.pos, loc, example, flags])
                    st[0] += 1
        # Known dictionary phrases used in the sentence (inflected too) give example candidates.
        for phrase, kind, _, _ in find_known_phrases(dictionary, sent.tokens):
            add_example(phrase, ('known_phrase', {'kind': kind}), loc, example, flags, penalty)
        for ph in sent.phrases:
            if ph.kind == 'collocation':
                st = colloc.setdefault(ph.phrase, [0, loc, example, flags])
                st[0] += 1
                continue
            result, detail = compare_phrase(dictionary, ph.phrase)
            if result == 'new_phrase':
                store.add_candidate(kind=ph.kind, direction=direction, headword=ph.phrase, source_id=source_id,
                                    engine=engine, locator=loc, example=example,
                                    confidence=round(max(0.0, ph.confidence - penalty), 2), compare_result=result,
                                    compare_detail=detail_with(detail, flags))
                counts[ph.kind] = counts.get(ph.kind, 0) + 1
    for phrase, (n, loc, example, flags) in sorted(colloc.items()):
        if n < min_collocation:
            continue
        result, detail = compare_phrase(dictionary, phrase)
        if result == 'new_phrase':
            store.add_candidate(kind='collocation', direction=direction, headword=phrase, source_id=source_id,
                                engine=engine, locator=loc, example=example,
                                confidence=round(min(0.5, 0.1 * n), 2), compare_result=result,
                                compare_detail=detail_with(detail, flags, count=n))
            counts['collocation'] += 1
    for (head, dpos), (n, upos, loc, example, flags) in sorted(pos_uses.items()):
        # A rare tag among many uses is usually a tagger error ("at all" tagged as an adverb), not a new sense.
        if n < min_pos_gap or n < min_pos_share * lemma_uses.get(head, n):
            continue
        known = dictionary.pos_set(head)
        if known and dpos not in known and set(SENSE_GAP_POS) & known:
            store.add_candidate(kind='sense', direction=direction, headword=head, lemma=head, pos=upos,
                                source_id=source_id, engine=engine, locator=loc, example=example, confidence=0.2,
                                compare_result='possible_new_sense',
                                compare_detail=detail_with({'dictionary_pos': sorted(known), 'count': n}, flags))
            counts['sense'] += 1
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
