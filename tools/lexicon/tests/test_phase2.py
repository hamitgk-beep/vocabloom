"""Phase 2 tests: lemmas, proper-name filter, known phrases, collocations, word-class gaps, gap report, spaCy.

Run from the repository root:  python3 -m unittest discover -s tools/lexicon/tests -t tools
The spaCy tests are skipped when spaCy / en_core_web_sm are not installed (tools/lexicon/setup_spacy.sh).
"""
import importlib.util
import json
import os
import sqlite3
import tempfile
import unittest

from lexicon.tests.helpers import REPO, make_dict_db, make_tr_en_db, sha256  # noqa: F401 (sets sys.path)
from lexicon.adapters.english import BuiltinEnglishAnalyzer, EnglishAnalyzer, make_english
from lexicon.adapters.types import PhraseMatch, Sentence, Token
from lexicon.compare import EnTrDictionary, TrEnDictionary, compare_phrase, compare_word, find_known_phrases
from lexicon.extract import extract, name_evidence
from lexicon.gaps import gap_rows, write_report
from lexicon.store import CandidateStore

HAVE_SPACY = bool(importlib.util.find_spec('spacy') and importlib.util.find_spec('en_core_web_sm'))
REAL_DICT = os.path.join(REPO, 'assets', 'dict.db')


def add_entries(path):
    """Extra synthetic entries (only in the temporary test copy)."""
    db = sqlite3.connect(path)
    db.executemany('INSERT INTO ft VALUES (?, ?)', [(w, json.dumps(['x'])) for w in (
        'sea', 'cook', 'bed', 'post', 'break', 'ice', 'make', 'decision', 'plaster', 'time', 'brave', 'pleasant',
        'happy', 'big', 'thinking', 'morning', 'morn', 'news', 'new', 'descend', 'mother', 'law', 'dinner',
        'hand', 'shake', 'pull', 'leg', 'he', 'his', 'my', 'we', 'they', 'by', 'mischief')])
    db.executemany('INSERT INTO sense VALUES (?, ?, 1, 0)', [
        ('cook', 'v'), ('think', 'v'), ('plaster', 'v'), ('break', 'v'), ('make', 'v'), ('shake', 'v'),
        ('pull', 'v'), ('descend', 'v'), ('hole', 'n'), ('time', 'n'), ('mischief', 'n'), ('decision', 'n')])
    db.executemany('INSERT INTO exc VALUES (?, ?, ?)', [('broke', 'break', 'v'), ('met', 'meet', 'v')])
    db.execute("INSERT INTO own_word VALUES ('hand', ?, '[]', 'contrib', 1, NULL, NULL, NULL)",
               [json.dumps([{'pos': 'isim', 'tr': 'el'}, {'pos': 'fiil', 'tr': 'uzatmak'}], ensure_ascii=False)])
    db.executemany("INSERT INTO expr(id, phrase, cat, tr) VALUES (?, ?, ?, 'x')", [
        (10, 'break the ice', 'idioms'), (11, "pull someone's leg", 'idioms'), (12, 'make a decision', 'collocations'),
        (13, 'shake hands', 'collocations')])
    db.commit()
    db.close()


class StubAnalyzer(EnglishAnalyzer):
    """Returns prepared sentences, so extract() rules can be tested without spaCy."""
    name, version, licence = 'stub-en', '1', 'test'

    def __init__(self, sentences):
        self.sentences = sentences

    def analyze(self, text):
        return self.sentences


def sent(text, words, phrases=()):
    """words: [(text, lemma, pos)] in order; offsets are found in `text`."""
    toks, pos = [], 0
    for w, lemma, upos, *ent in words:
        i = text.index(w, pos)
        toks.append(Token(w, lemma, upos, w[0].isalpha(), i, ent[0] if ent else ''))
        pos = i + len(w)
    return Sentence(text, toks, [PhraseMatch(p, k, c) for p, k, c in phrases])


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dict_path = os.path.join(self.tmp.name, 'src', 'dict.db')
        os.makedirs(os.path.dirname(self.dict_path))
        make_dict_db(self.dict_path)
        add_entries(self.dict_path)
        self.en = EnTrDictionary(self.dict_path)
        self.store = CandidateStore(os.path.join(self.tmp.name, 'out', 'c.db'))
        self.src = self.store.add_source('pd', 'public_domain_text', 'Public domain', 'en')

    def tearDown(self):
        self.en.close()
        self.store.close()
        self.tmp.cleanup()

    def run_stub(self, sentences, **kw):
        return extract(self.store, StubAnalyzer(sentences), self.en, self.src, '', 'en-tr', **kw)

    def rows(self, kind):
        return {r['headword']: r for r in self.store.candidates(kind=kind)}


class BuiltinLemmaTests(Base):
    def test_irregular_form_wins_over_headword(self):
        # "was" is in exc; real dict.db also lists forms like "sat" or "found" as headwords
        self.assertEqual(BuiltinEnglishAnalyzer(self.en).lemma('was'), 'be')

    def test_regular_forms_of_known_verbs(self):
        a = BuiltinEnglishAnalyzer(self.en)
        self.assertEqual(a.lemma('thinking'), 'think')          # "thinking" is a headword but a verb form here
        self.assertEqual(a.lemma('morning'), 'morning')         # kept: listed as written
        self.assertEqual(a.lemma('news'), 'news')

    def test_comparatives_and_prefixes(self):
        a = BuiltinEnglishAnalyzer(self.en)
        self.assertEqual([a.lemma(w) for w in ('braver', 'pleasanter', 'bigger', 'happier', 'dinner')],
                         ['brave', 'pleasant', 'big', 'happy', 'dinner'])
        self.assertEqual(a.lemma('redescended'), 'redescend')
        self.assertIsNone(a.prefixed('quokka'))


class NameTests(Base):
    def test_document_level_names(self):
        s = [sent('Dinah was here.', [('Dinah', 'dinah', ''), ('was', 'be', ''), ('here', 'here', '')]),
             sent('I saw Dinah.', [('I', 'i', ''), ('saw', 'see', ''), ('Dinah', 'dinah', 'PROPN')]),
             sent('Quokkas ran.', [('Quokkas', 'quokka', ''), ('ran', 'run', '')])]
        names, initial = name_evidence(s)
        self.assertIn('dinah', names)              # capitalised inside a sentence, never lower case
        self.assertNotIn('i', names)
        self.assertEqual(initial, {'quokkas'})     # only seen starting a sentence: can't tell

    def test_names_never_become_word_candidates(self):
        s = [sent('Zorblat met the quokka.', [('Zorblat', 'zorblat', 'PROPN'), ('met', 'meet', 'VERB'),
                                               ('the', 'the', 'DET'), ('quokka', 'quokka', 'NOUN')]),
             sent('Then Glimmerton came.', [('Then', 'then', 'ADV'), ('Glimmerton', 'glimmerton', 'NOUN', 'GPE'),
                                            ('came', 'come', 'VERB')])]
        counts = self.run_stub(s)
        words = self.rows('word')
        self.assertIn('quokka', words)
        self.assertNotIn('zorblat', words)
        self.assertNotIn('glimmerton', words)      # entity label, even with a wrong NOUN tag
        self.assertEqual(counts['names_skipped'], 2)


class SpeechCapitalTests(unittest.TestCase):
    def test_capital_after_dash_or_colon_is_not_a_name(self):
        from lexicon.adapters.turkish import BuiltinTurkishAnalyzer
        toks = BuiltinTurkishAnalyzer(None).analyze("Ali'ye döndü: — Kız niçin girmiyorsun? Eskiden san'at vardı.")
        pos = {t.text: t.pos for s in toks for t in s.tokens if t.is_word}
        self.assertEqual(pos['Ali'], 'PROPN')
        self.assertNotEqual(pos['Kız'], 'PROPN')
        self.assertNotEqual(pos['san'], 'PROPN')     # old spelling with an apostrophe, lower case
        names, _ = name_evidence(toks)
        self.assertNotIn('kız', names)


class WordFilterTests(Base):
    def test_compounds_dialect_abbreviations(self):
        text = "The sea-cook said a-going, kep' and wibbly-wobbit etc. here."
        s = [sent(text, [('The', 'the', 'DET'), ('sea-cook', 'sea-cook', 'NOUN'), ('said', 'say', 'VERB'),
                         ('a-going', 'a-going', 'VERB'), ('kep', 'kep', 'VERB'), ('and', 'and', 'CCONJ'),
                         ('wibbly-wobbit', 'wibbly-wobbit', 'NOUN'), ('etc', 'etc', 'X'), ('here', 'here', 'ADV')])]
        self.run_stub(s)
        words = self.rows('word')
        self.assertNotIn('a-going', words)                     # archaic a- verb form
        self.assertNotIn('etc', words)                         # abbreviation
        self.assertLessEqual(words['sea-cook']['confidence'], 0.1)  # both parts known (minus the "etc." penalty)
        self.assertTrue(json.loads(words['sea-cook']['compare_detail'])['compound'])
        self.assertLessEqual(words['kep']['confidence'], 0.1)
        self.assertTrue(json.loads(words['kep']['compare_detail'])['elided'])
        self.assertGreaterEqual(words['wibbly-wobbit']['confidence'], 0.3)   # unknown parts: normal priority

    def test_compound_known_with_space_or_joined_is_not_new(self):
        s = [sent('A bed-post.', [('A', 'a', 'DET'), ('bed-post', 'bed-post', 'NOUN')])]
        db = sqlite3.connect(self.dict_path)
        db.execute("INSERT INTO ft VALUES ('bedpost', '[\"karyola direği\"]')")
        db.commit()
        db.close()
        self.run_stub(s)
        self.assertNotIn('bed-post', self.rows('word'))


class PhraseTests(Base):
    def test_compare_phrase_article_variants(self):
        self.assertEqual(compare_phrase(self.en, 'make decision'), ('known_phrase', {'as': 'make a decision'}))
        self.assertEqual(compare_phrase(self.en, 'give up'), ('known_phrase', {}))
        self.assertEqual(compare_phrase(self.en, 'cook dinner')[0], 'new_phrase')

    def test_find_known_phrases_inflected_and_slots(self):
        toks = BuiltinEnglishAnalyzer(self.en).analyze('He broke the ice and pulled my leg.')[0].tokens
        found = {(p, k) for p, k, _, _ in find_known_phrases(self.en, toks)}
        self.assertEqual(found, {('break the ice', 'idiom'), ("pull someone's leg", 'idiom')})
        toks = BuiltinEnglishAnalyzer(self.en).analyze('Someone pulled the leg.')[0].tokens
        self.assertEqual(find_known_phrases(self.en, toks), [])   # "the" is not a possessive

    def test_known_phrases_give_examples(self):
        text = 'They broke the ice.'
        self.run_stub([sent(text, [('They', 'they', 'PRON'), ('broke', 'break', 'VERB'), ('the', 'the', 'DET'),
                                   ('ice', 'ice', 'NOUN')])])
        ex = self.rows('example')
        self.assertEqual(ex['break the ice']['compare_result'], 'known_phrase')
        self.assertEqual(ex['break the ice']['example'], text)

    def test_collocations_need_repeats_and_must_be_new(self):
        def s(text, *phrases):
            return sent(text, [], [(p, 'collocation', 0.2) for p in phrases])
        self.run_stub([s('a', 'cook dinner', 'make decision', 'mend net'), s('b', 'cook dinner', 'make decision')])
        coll = self.rows('collocation')
        self.assertEqual(set(coll), {'cook dinner'})      # "mend net" once; "make decision" is known
        self.assertEqual(json.loads(coll['cook dinner']['compare_detail'])['count'], 2)


class SenseGapTests(Base):
    def test_pos_set_from_wordnet_and_own_word(self):
        self.assertEqual(self.en.pos_set('hand'), {'n', 'v'})
        self.assertEqual(self.en.pos_set('mischief'), {'n'})
        self.assertEqual(self.en.pos_set('quokka'), set())

    def _uses(self, n_verb, n_noun):
        out = []
        for i in range(n_verb):
            out.append(sent(f'They mischief {i}.', [('They', 'they', 'PRON'), ('mischief', 'mischief', 'VERB')]))
        for i in range(n_noun):
            out.append(sent(f'The mischief {i}.', [('The', 'the', 'DET'), ('mischief', 'mischief', 'NOUN')]))
        return out

    def test_noun_used_as_verb_is_a_possible_new_sense(self):
        self.run_stub(self._uses(3, 2))
        senses = self.rows('sense')
        self.assertEqual(senses['mischief']['compare_result'], 'possible_new_sense')
        self.assertEqual(senses['mischief']['pos'], 'VERB')
        self.assertEqual(senses['mischief']['translation'], '')        # never invented
        self.assertEqual(json.loads(senses['mischief']['compare_detail'])['dictionary_pos'], ['n'])

    def test_rare_or_one_off_tags_are_ignored(self):
        self.run_stub(self._uses(2, 0))            # fewer than min_pos_gap uses
        self.assertEqual(self.rows('sense'), {})
        self.store.db.execute('DELETE FROM candidate')
        self.run_stub(self._uses(3, 30))           # 3 of 33 uses: below min_pos_share, likely tagging errors
        self.assertEqual(self.rows('sense'), {})


class GapReportTests(Base):
    def test_report_groups_sources_and_hides_private_sentences(self):
        book = self.store.add_source('my-book', 'user_book', '', 'en')
        secret = 'The quokka whispered a secret sentence.'
        s = [sent(secret, [('The', 'the', 'DET'), ('quokka', 'quokka', 'NOUN')])]
        extract(self.store, StubAnalyzer(s), self.en, book, '', 'en-tr')
        extract(self.store, StubAnalyzer(s), self.en, self.src, '', 'en-tr')
        rows = [r for r in gap_rows(self.store) if r['headword'] == 'quokka']
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['sources'], 2)
        out = os.path.join(self.tmp.name, 'out', 'gaps.md')
        # Only the user's book: the sentence must not reach the report.
        self.store.db.execute('DELETE FROM candidate WHERE source_id = ?', [self.src])
        write_report(self.store, out, min_confidence=0.0)
        for path in (out, out[:-3] + '.tsv'):
            with open(path, encoding='utf-8') as f:
                text = f.read()
            self.assertIn('quokka', text)
            self.assertNotIn('whispered', text)

    def test_report_refuses_assets(self):
        with self.assertRaises(ValueError):
            write_report(self.store, os.path.join(REPO, 'assets', 'gaps.md'))


class TurkishLookupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, 'tr_en.db')
        make_tr_en_db(self.path)
        db = sqlite3.connect(self.path)
        db.execute("INSERT INTO lemma VALUES ('hakiki', 30, ?)", [json.dumps([{'p': 'adj', 'g': ['real']}])])
        db.execute("INSERT INTO lemma VALUES ('fevkalade', 31, ?)", [json.dumps([{'p': 'adj', 'g': ['extraordinary']}])])
        db.execute("INSERT INTO form VALUES ('fevkalâde', 'fevkalade')")
        db.commit()
        db.close()
        self.tr = TrEnDictionary(self.path)

    def tearDown(self):
        self.tr.close()
        self.tmp.cleanup()

    def test_circumflex_spelling_is_the_same_word(self):
        self.assertTrue(self.tr.has_lemma('hakikî'))
        self.assertEqual(compare_word(self.tr, 'hakikî', 'hakikî')[0], 'known_headword')

    def test_analyzer_lemma_that_is_a_listed_form(self):
        # An analyzer may return "fevkalâde" as the lemma of "fevkalâdeydi"; the form table maps it.
        self.assertEqual(compare_word(self.tr, 'fevkalâdeydi', 'fevkalâde'), ('known_form', {'lemma': 'fevkalade'}))


def _zemberek_ready():
    from lexicon.adapters.turkish_zemberek import available
    return available()


@unittest.skipUnless(_zemberek_ready(), 'Zemberek not set up (tools/lexicon/setup_zemberek.sh)')
class ZemberekTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from lexicon.adapters.turkish import make_turkish
        cls.z = make_turkish('zemberek')

    @classmethod
    def tearDownClass(cls):
        cls.z.close()

    def test_lemmas_names_and_licence(self):
        s = self.z.analyze("Ali'nin kardeşi evlerimizde kitap okudu. İstanbul'a gittiler.")
        by = {t.text: t for x in s for t in x.tokens if t.is_word}
        self.assertEqual(by['evlerimizde'].lemma, 'ev')
        self.assertEqual(by['okudu'].lemma, 'okumak')
        self.assertEqual(by['kardeşi'].lemma, 'kardeş')
        self.assertEqual(by["Ali'nin"].pos, 'PROPN')
        self.assertEqual(by["İstanbul'a"].pos, 'PROPN')
        self.assertIn('Apache-2.0', self.z.licence)

    def test_route_rejects_zemberek_for_english(self):
        from lexicon.extract import check_route
        with tempfile.TemporaryDirectory() as d:
            make_dict_db(os.path.join(d, 'dict.db'))
            en = EnTrDictionary(os.path.join(d, 'dict.db'))
            store = CandidateStore(os.path.join(d, 'c.db'))
            sid = store.add_source('pd', 'public_domain_text', 'Public domain', 'en')
            with self.assertRaises(ValueError):
                check_route(store, sid, 'en-tr', en, self.z)
            en.close()
            store.close()


@unittest.skipUnless(HAVE_SPACY, 'spaCy / en_core_web_sm not installed (tools/lexicon/setup_spacy.sh)')
class SpacyTests(Base):
    @classmethod
    def setUpClass(cls):
        import spacy
        cls.nlp_ok = spacy.load('en_core_web_sm').meta.get('license') == 'MIT'

    def analyze(self, text):
        return make_english('spacy', self.en).analyze(text)

    def test_model_licence_checked(self):
        self.assertTrue(self.nlp_ok)
        self.assertIn('MIT', make_english('spacy', self.en).licence)

    def test_separated_particle_and_no_be(self):
        phrases = {p.phrase for s in self.analyze('She took her coat off. The sun was up.') for p in s.phrases
                   if p.kind == 'phrasal_verb'}
        self.assertIn('take off', phrases)
        self.assertNotIn('be up', phrases)

    def test_names_marked(self):
        toks = [t for s in self.analyze('Mary went to London with Peter.') for t in s.tokens]
        by = {t.text: t for t in toks}
        for name in ('Mary', 'London', 'Peter'):
            self.assertTrue(by[name].pos == 'PROPN' or by[name].ent, name)
        self.assertEqual(by['went'].lemma, 'go')

    def test_hyphen_compound_is_one_token(self):
        toks = [t for s in self.analyze('The sea-cooks laughed.') for t in s.tokens if t.is_word]
        self.assertIn('sea-cooks', [t.text for t in toks])
        self.assertEqual({t.text: t.lemma for t in toks}['sea-cooks'], 'sea-cook')

    def test_no_collocation_from_particle_verb_or_compound(self):
        phrases = {p.phrase for s in self.analyze('The others took up the cry. He met his mother-in-law.')
                   for p in s.phrases if p.kind == 'collocation'}
        self.assertNotIn('take cry', phrases)
        self.assertNotIn('meet mother', phrases)


@unittest.skipUnless(os.path.isfile(REAL_DICT) and os.path.isfile(os.path.join(REPO, 'assets', 'tr_en.db')),
                     'shipped dictionaries not present')
class EvaluationThresholdTests(unittest.TestCase):
    """Guards the measured quality on eval/en_gold.jsonl (30 public-domain sentences, real dict.db read-only)."""

    def _run(self, engine):
        from lexicon.eval.evaluate import evaluate, load_gold
        d = EnTrDictionary(REAL_DICT)
        try:
            before = sha256(REAL_DICT)
            r = evaluate(engine, d, load_gold())
            self.assertEqual(sha256(REAL_DICT), before)
            return r
        finally:
            d.close()

    def test_builtin(self):
        r = self._run('builtin')
        self.assertGreaterEqual(r['lemma_accuracy'], 0.9)
        self.assertGreaterEqual(r['name_recall'], 0.8)
        self.assertLessEqual(r['name_leakage'], 0.1)

    def _run_tr(self, engine):
        from lexicon.eval.evaluate import TR_GOLD, evaluate_tr, load_gold
        path = os.path.join(REPO, 'assets', 'tr_en.db')
        d = TrEnDictionary(path)
        try:
            before = sha256(path)
            r = evaluate_tr(engine, d, load_gold(TR_GOLD))
            self.assertEqual(sha256(path), before)
            return r
        finally:
            d.close()

    def test_builtin_turkish(self):
        r = self._run_tr('builtin')
        self.assertGreaterEqual(r['lemma_accuracy'], 0.7)
        self.assertGreaterEqual(r['name_precision'], 0.9)
        self.assertEqual(r['name_leakage'], 0.0)

    @unittest.skipUnless(_zemberek_ready(), 'Zemberek not set up')
    def test_zemberek_turkish(self):
        r = self._run_tr('zemberek')
        self.assertGreaterEqual(r['lemma_accuracy'], 0.9)
        self.assertGreaterEqual(r['name_recall'], 0.95)
        self.assertGreaterEqual(r['name_precision'], 0.9)
        self.assertEqual(r['name_leakage'], 0.0)

    @unittest.skipUnless(HAVE_SPACY, 'spaCy not installed')
    def test_spacy(self):
        r = self._run('spacy')
        self.assertGreaterEqual(r['lemma_accuracy'], 0.95)
        self.assertGreaterEqual(r['name_recall'], 0.95)
        self.assertEqual(r['name_leakage'], 0.0)
        self.assertGreaterEqual(r['phrasal_precision'], 0.9)
        self.assertGreaterEqual(r['phrasal_recall'], 0.8)


if __name__ == '__main__':
    unittest.main()
