"""Run from the repository root: python3 -m unittest discover -s tools/lexicon/tests -t tools

Each test class maps to one of the acceptance points of the first PR:
  1 directions tested separately       DirectionTests
  2 new sense for an existing word     NewSenseTests
  3 source / licence / permission / scope stored separately   ProvenanceTests
  4 unclear licence and private books can't reach the shared export   SharingGuardTests
  5 the dictionaries are not changed   DictionaryIntegrityTests (synthetic) and RealAssetsTests (real files)
plus: no automatic acceptance, adapters, path guards.
"""
import os
import sqlite3
import tempfile
import unittest

from lexicon.tests.helpers import REPO, make_dict_db, make_tr_en_db, sha256  # noqa: F401 (sets sys.path)
from lexicon.adapters.english import BuiltinEnglishAnalyzer, make_english
from lexicon.adapters.turkish import BuiltinTurkishAnalyzer
from lexicon.compare import EnTrDictionary, TrEnDictionary, compare_word
from lexicon.extract import add_sense, extract
from lexicon.store import CandidateStore

EN_TEXT = ('Alice was very tired of sitting by the hole. She gave up. The rabbit ran away. '
           'Then the quokka stopped and it hopped up.')
TR_TEXT = 'Bir gün Ali eve gitti. Ali\'nin evde kedisi vardı. Tavşan zıpladı.'


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = self.tmp.name
        self.dict_path, self.tr_en_path = os.path.join(d, 'src', 'dict.db'), os.path.join(d, 'src', 'tr_en.db')
        os.makedirs(os.path.join(d, 'src'))
        make_dict_db(self.dict_path)
        make_tr_en_db(self.tr_en_path)
        self.hashes = (sha256(self.dict_path), sha256(self.tr_en_path))
        self.en = EnTrDictionary(self.dict_path)
        self.tr = TrEnDictionary(self.tr_en_path)
        self.store = CandidateStore(os.path.join(d, 'out', 'candidates.db'))
        self.pd_en = self.store.add_source('alice-pd', 'public_domain_text', 'Public domain', 'en')
        self.pd_tr = self.store.add_source('hoca-pd', 'public_domain_text', 'Public domain', 'tr')

    def tearDown(self):
        self.en.close()
        self.tr.close()
        self.store.close()
        self.tmp.cleanup()

    def heads(self, **where):
        return {r['headword'] for r in self.store.candidates(**where)}


class DirectionTests(Base):
    def test_en_tr_extraction(self):
        counts = extract(self.store, BuiltinEnglishAnalyzer(self.en), self.en, self.pd_en, EN_TEXT, 'en-tr')
        self.assertEqual(counts['sentences'], 4)
        rows = self.store.candidates(direction='en-tr')
        self.assertTrue(rows)
        self.assertEqual({r['direction'] for r in self.store.candidates()}, {'en-tr'})
        words = self.heads(kind='word')
        self.assertIn('quokka', words)                   # new word
        self.assertIn('hopped', words)                   # unknown stem: kept as written, no guessed lemma
        self.assertNotIn('quokka', self.heads(kind='example'))
        self.assertNotIn('rabbit', words)                # known
        self.assertNotIn('ran', words)                   # irregular form of known "run"
        self.assertIn('run away', self.heads(kind='phrasal_verb'))   # clause-final particle, not in tables
        self.assertNotIn('give up', self.heads(kind='phrasal_verb'))  # already in expr
        self.assertIn('run', self.heads(kind='example'))  # example for a known word

    def test_tr_en_extraction(self):
        extract(self.store, BuiltinTurkishAnalyzer(self.tr), self.tr, self.pd_tr, TR_TEXT, 'tr-en')
        self.assertEqual({r['direction'] for r in self.store.candidates()}, {'tr-en'})
        words = self.heads(kind='word')
        self.assertIn('kedisi', words)                   # unknown form -> new (low confidence, no lemma)
        self.assertIn('zıpladı', words)
        self.assertNotIn('eve', words)                   # known form of "ev"
        self.assertNotIn('ali', words)                   # proper noun
        self.assertNotIn('nin', words)                   # suffix after apostrophe
        self.assertIn('ev', self.heads(kind='example'))
        self.assertEqual(self.store.candidates(headword='kedisi')[0]['confidence'], 0.2)

    def test_directions_do_not_mix(self):
        with self.assertRaises(ValueError):
            extract(self.store, BuiltinEnglishAnalyzer(self.en), self.en, self.pd_tr, EN_TEXT, 'en-tr')
        with self.assertRaises(ValueError):
            self.store.add_candidate(kind='word', direction='tr-en', headword='x', source_id=self.pd_en,
                                     engine='t')

    def test_compare_each_direction(self):
        self.assertEqual(compare_word(self.en, 'rabbit')[0], 'known_headword')
        self.assertEqual(compare_word(self.en, 'gave', 'gave')[0], 'known_form')
        self.assertEqual(compare_word(self.en, 'quokka')[0], 'new_headword')
        self.assertEqual(compare_word(self.tr, 'ev')[0], 'known_headword')
        self.assertEqual(compare_word(self.tr, 'gittim', 'gittim'), ('known_form', {'lemma': 'gitmek'}))
        self.assertEqual(compare_word(self.tr, 'kedi')[0], 'new_headword')


class NewSenseTests(Base):
    def test_new_sense_for_existing_english_word(self):
        cid = add_sense(self.store, self.en, self.pd_en, 'en-tr', 'run', 'yönetmek', pos='verb',
                        example='She runs a small shop.', example_translation='Küçük bir dükkân işletiyor.')
        row = self.store.get(cid)
        self.assertEqual((row['kind'], row['compare_result'], row['status']),
                         ('sense', 'possible_new_sense', 'unverified'))
        known = self.store.get(add_sense(self.store, self.en, self.pd_en, 'en-tr', 'run', 'Koşmak'))
        self.assertEqual(known['compare_result'], 'known_sense')
        alt = self.store.get(add_sense(self.store, self.en, self.pd_en, 'en-tr', 'get', 'edinmek'))
        self.assertEqual(alt['compare_result'], 'known_sense')     # one of several comma-separated meanings

    def test_new_sense_for_existing_turkish_word(self):
        row = self.store.get(add_sense(self.store, self.tr, self.pd_tr, 'tr-en', 'ev', 'household'))
        self.assertEqual(row['compare_result'], 'possible_new_sense')
        row = self.store.get(add_sense(self.store, self.tr, self.pd_tr, 'tr-en', 'ev', 'home'))
        self.assertEqual(row['compare_result'], 'known_sense')

    def test_sense_for_new_word_and_phrase(self):
        row = self.store.get(add_sense(self.store, self.en, self.pd_en, 'en-tr', 'quokka', 'kısa kuyruklu kanguru'))
        self.assertEqual(row['compare_result'], 'new_headword')
        row = self.store.get(add_sense(self.store, self.en, self.pd_en, 'en-tr', 'give up', 'bırakmak',
                                       kind='phrasal_verb'))
        self.assertEqual(row['compare_result'], 'known_phrase')
        with self.assertRaises(ValueError):
            add_sense(self.store, self.en, self.pd_en, 'en-tr', 'run', '  ')


class ProvenanceTests(Base):
    def test_fields_are_stored_separately(self):
        sa = self.store.add_source('wiki', 'open_license_text', 'CC BY-SA 4.0', 'en')
        unk = self.store.add_source('blog', 'open_license_text', '', 'en')
        book = self.store.add_source('my-novel', 'user_book', 'All rights reserved', 'en')
        expect = {
            self.pd_en: ('public_domain_text', 'public-domain', 'allowed', 1, 'shared'),
            sa: ('open_license_text', 'cc-by-sa-4.0', 'needs_approval', 0, 'private'),
            unk: ('open_license_text', 'unknown', 'unknown', 0, 'private'),
            book: ('user_book', 'all-rights-reserved', 'private_only', 0, 'private'),
        }
        for sid, (kind, lic, perm, shareable, scope) in expect.items():
            src = self.store.source(sid)
            self.assertEqual((src['kind'], src['licence'], src['permission'], src['shareable']),
                             (kind, lic, perm, shareable))
            c = self.store.get(self.store.add_candidate(kind='word', direction='en-tr', headword=f'w{sid}',
                                                        source_id=sid, engine='test', locator='ch1#p2'))
            self.assertEqual((c['source_id'], c['licence'], c['permission'], c['scope'], c['locator'],
                              c['engine'], c['status']), (sid, lic, perm, scope, 'ch1#p2', 'test', 'unverified'))

    def test_occurrences_are_counted_not_duplicated(self):
        for _ in range(3):
            self.store.add_candidate(kind='word', direction='en-tr', headword='quokka', source_id=self.pd_en,
                                     engine='t')
        rows = self.store.candidates(headword='quokka')
        self.assertEqual((len(rows), rows[0]['occurrences']), (1, 3))

    def test_same_word_in_two_sentences_is_one_candidate(self):
        extract(self.store, BuiltinEnglishAnalyzer(self.en), self.en, self.pd_en,
                'A quokka sat. Another quokka ran.', 'en-tr')
        rows = self.store.candidates(kind='word', headword='quokka')
        self.assertEqual((len(rows), rows[0]['occurrences'], rows[0]['example']), (1, 2, 'A quokka sat.'))

    def test_existing_dictionary_is_not_a_source(self):
        with self.assertRaises(ValueError):
            self.store.add_source('dict', 'existing_dictionary', 'CC BY-SA 4.0', 'en')


class ReviewTests(Base):
    def test_pipeline_cannot_accept(self):
        for status in ('accepted', 'rejected'):
            with self.assertRaises(ValueError):
                self.store.add_candidate(kind='word', direction='en-tr', headword='x', source_id=self.pd_en,
                                         engine='t', status=status)

    def test_review_needs_reviewer_and_is_logged(self):
        cid = self.store.add_candidate(kind='word', direction='en-tr', headword='x', source_id=self.pd_en,
                                       engine='t')
        with self.assertRaises(ValueError):
            self.store.review(cid, 'accepted', '  ')
        with self.assertRaises(sqlite3.IntegrityError):      # the schema enforces it too
            self.store.db.execute("UPDATE candidate SET status = 'accepted' WHERE id = ?", [cid])
        self.store.review(cid, 'accepted', 'Hamit', 'checked')
        self.assertEqual(self.store.get(cid)['status'], 'accepted')
        log = self.store.db.execute('SELECT old_status, new_status, reviewer FROM review_log').fetchall()
        self.assertEqual([tuple(r) for r in log], [('unverified', 'accepted', 'Hamit')])


class SharingGuardTests(Base):
    def test_only_reviewed_permissive_candidates_are_exported(self):
        sa = self.store.add_source('wiki', 'open_license_text', 'CC BY-SA 4.0', 'en')
        nc = self.store.add_source('nc', 'open_license_text', 'CC BY-NC-SA 4.0', 'en')
        unk = self.store.add_source('blog', 'open_license_text', 'my own terms', 'en')
        book = self.store.add_source('my-novel', 'user_book', 'Public domain', 'en')  # claim ignored for books
        ids = {}
        for name, sid in [('pd', self.pd_en), ('sa', sa), ('nc', nc), ('unk', unk), ('book', book)]:
            ids[name] = self.store.add_candidate(kind='word', direction='en-tr', headword=name, source_id=sid,
                                                 engine='t')
            self.store.review(ids[name], 'accepted', 'Hamit')
        self.store.add_candidate(kind='word', direction='en-tr', headword='pd-unreviewed', source_id=self.pd_en,
                                 engine='t')
        out = os.path.join(self.tmp.name, 'out', 'reviewed.jsonl')
        self.assertEqual(self.store.export_reviewed_shared(out), 1)
        with open(out, encoding='utf-8') as f:
            self.assertEqual([__import__('json').loads(l)['headword'] for l in f], ['pd'])

    def test_private_candidate_cannot_be_forced_shared(self):
        book = self.store.add_source('my-novel', 'user_book', '', 'en')
        cid = self.store.add_candidate(kind='word', direction='en-tr', headword='x', source_id=book, engine='t')
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.db.execute("UPDATE candidate SET scope = 'shared' WHERE id = ?", [cid])
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.db.execute("UPDATE source SET shareable = 1 WHERE id = ?", [book])

    def test_user_book_extraction_stays_private(self):
        book = self.store.add_source('my-novel', 'user_book', '', 'en')
        extract(self.store, BuiltinEnglishAnalyzer(self.en), self.en, book, EN_TEXT, 'en-tr')
        self.assertEqual({r['scope'] for r in self.store.candidates(source_id=book)}, {'private'})


class DictionaryIntegrityTests(Base):
    def test_dictionaries_unchanged_after_full_run(self):
        extract(self.store, BuiltinEnglishAnalyzer(self.en), self.en, self.pd_en, EN_TEXT, 'en-tr')
        extract(self.store, BuiltinTurkishAnalyzer(self.tr), self.tr, self.pd_tr, TR_TEXT, 'tr-en')
        add_sense(self.store, self.en, self.pd_en, 'en-tr', 'run', 'yönetmek')
        self.en.close()
        self.tr.close()
        self.assertEqual((sha256(self.dict_path), sha256(self.tr_en_path)), self.hashes)
        self.en, self.tr = EnTrDictionary(self.dict_path), TrEnDictionary(self.tr_en_path)

    def test_dictionary_connections_refuse_writes(self):
        for view in (self.en, self.tr):
            with self.assertRaises(sqlite3.OperationalError):
                view.db.execute("CREATE TABLE x(a)")
        with self.assertRaises(sqlite3.OperationalError):
            self.en.db.execute("DELETE FROM ft")

    def test_candidate_db_cannot_target_dictionaries_or_assets(self):
        for bad in (self.dict_path, self.tr_en_path, os.path.join(REPO, 'assets', 'candidates.db'),
                    os.path.join(REPO, 'assets', 'x', 'c.db')):
            with self.assertRaises(ValueError):
                CandidateStore(bad)
        with self.assertRaises(ValueError):
            self.store.export_reviewed_shared(os.path.join(REPO, 'assets', 'export.jsonl'))


class AdapterTests(Base):
    def test_english_builtin_lemmas(self):
        a = BuiltinEnglishAnalyzer(self.en)
        self.assertEqual([a.lemma(w) for w in ['ran', 'stopped', 'sitting', 'rabbits', 'Was']],
                         ['run', 'stop', 'sit', 'rabbit', 'be'])
        self.assertEqual(BuiltinEnglishAnalyzer(None).lemma('Rabbits'), 'rabbits')

    def test_english_builtin_skips_contractions_and_non_verbs(self):
        sent = BuiltinEnglishAnalyzer(self.en).analyze("She didn't run off. Rabbit's hole, then it off.")
        words = {t.text for s in sent for t in s.tokens if t.is_word}
        self.assertNotIn("didn't", words)
        self.assertIn("Rabbit's", words)
        phrases = {p.phrase for s in sent for p in s.phrases}
        self.assertEqual(phrases, {'run off'})          # "it off": "it" is not a verb

    def test_turkish_builtin_tokens(self):
        sent = BuiltinTurkishAnalyzer(self.tr).analyze("Ali'nin evde İstanbul'a gitti.")[0]
        by = {t.text: t for t in sent.tokens}
        self.assertEqual((by['evde'].lemma, by['evde'].pos), ('ev', 'noun'))
        self.assertEqual(by['gitti'].lemma, 'gitmek')
        self.assertEqual(by['Ali'].pos, 'PROPN')
        self.assertEqual(by['İstanbul'].pos, 'PROPN')

    def test_languages_are_independent(self):
        import lexicon.adapters.english as en
        import lexicon.adapters.turkish as tr
        for mod, other in ((en, 'turkish'), (tr, 'english')):
            with open(mod.__file__, encoding='utf-8') as f:
                self.assertNotIn(other, f.read().lower().replace(f'{other} ones', ''))
        with self.assertRaises(ValueError):
            make_english('stanza')

    @unittest.skipUnless(__import__('importlib').util.find_spec('spacy') and
                         __import__('importlib').util.find_spec('en_core_web_sm'), 'spaCy / en_core_web_sm not installed')
    def test_spacy_adapter(self):
        a = make_english('spacy')
        self.assertIn('MIT', a.licence)
        sent = a.analyze('She took her coat off and gave up.')[0]
        phrases = {p.phrase for p in sent.phrases}
        self.assertIn('take off', phrases)
        self.assertIn('give up', phrases)
        self.assertEqual({t.text: t.lemma for t in sent.tokens}['took'], 'take')


@unittest.skipUnless(os.path.isfile(os.path.join(REPO, 'assets', 'dict.db')) and
                     os.path.isfile(os.path.join(REPO, 'assets', 'tr_en.db')), 'shipped dictionaries not present')
class RealAssetsTests(unittest.TestCase):
    """Runs the pipeline against the real shipped dictionaries and checks their bytes did not change."""

    def test_real_dictionaries_read_only(self):
        dpath = os.path.join(REPO, 'assets', 'dict.db')
        tpath = os.path.join(REPO, 'assets', 'tr_en.db')
        before = (sha256(dpath), sha256(tpath), os.path.getmtime(dpath), os.path.getmtime(tpath))
        with tempfile.TemporaryDirectory() as d:
            store = CandidateStore(os.path.join(d, 'c.db'))
            en, tr = EnTrDictionary(dpath), TrEnDictionary(tpath)
            try:
                s_en = store.add_source('t-en', 'public_domain_text', 'Public domain', 'en')
                s_tr = store.add_source('t-tr', 'public_domain_text', 'Public domain', 'tr')
                extract(store, BuiltinEnglishAnalyzer(en), en, s_en, EN_TEXT, 'en-tr')
                extract(store, BuiltinTurkishAnalyzer(tr), tr, s_tr, TR_TEXT, 'tr-en')
                self.assertEqual(compare_word(en, 'house')[0], 'known_headword')
                self.assertEqual(compare_word(en, 'went', 'went'), ('known_form', {'lemma': 'go'}))
                self.assertEqual(compare_word(tr, 'evde', 'evde'), ('known_form', {'lemma': 'ev'}))
                self.assertEqual(store.get(add_sense(store, en, s_en, 'en-tr', 'run', 'koşmak'))['compare_result'],
                                 'known_sense')
                with self.assertRaises(sqlite3.OperationalError):
                    en.db.execute("UPDATE ft SET tr = '[]'")
            finally:
                en.close()
                tr.close()
                store.close()
        after = (sha256(dpath), sha256(tpath), os.path.getmtime(dpath), os.path.getmtime(tpath))
        self.assertEqual(after, before)


if __name__ == '__main__':
    unittest.main()
