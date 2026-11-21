"""Run from the repository root: python3 -m unittest discover -s tools/lexicon/tests -t tools

Each test class maps to one of the acceptance points of the first PR:
  1 directions tested separately       DirectionTests
  2 new sense for an existing word     NewSenseTests
  3 source / licence / permission / scope stored separately   ProvenanceTests
  4 unclear licence and private books can't reach the shared export   SharingGuardTests
  5 the dictionaries are not changed   DictionaryIntegrityTests (synthetic) and RealAssetsTests (real files)
plus: no automatic acceptance, adapters, path guards.
"""
import json
import os
import sqlite3
import tempfile
import unittest

from lexicon.tests.helpers import REPO, make_dict_db, make_tr_en_db, sha256  # noqa: F401 (sets sys.path)
from lexicon.adapters.english import BuiltinEnglishAnalyzer, make_english
from lexicon.adapters.turkish import BuiltinTurkishAnalyzer
from lexicon.adapters.types import sentence_flags, split_sentences
from lexicon.compare import EnTrDictionary, TrEnDictionary, compare_word
from lexicon.extract import add_sense, extract
from lexicon.store import TRIGGERS, CandidateStore, IntegrityError

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


class RouteValidationTests(Base):
    """Every entry point refuses a source / direction / dictionary / analyzer mix that doesn't fit,
    before writing anything."""

    def assertRefused(self, fn):
        before = self.store.count()
        with self.assertRaises(ValueError):
            fn()
        self.assertEqual(self.store.count(), before)

    def test_extract_wrong_combinations(self):
        en_an, tr_an = BuiltinEnglishAnalyzer(self.en), BuiltinTurkishAnalyzer(self.tr)
        bad = [
            (en_an, self.tr, self.pd_en, EN_TEXT, 'en-tr'),   # English source, Turkish dictionary
            (tr_an, self.en, self.pd_en, EN_TEXT, 'en-tr'),   # Turkish analyzer for en-tr
            (en_an, self.en, self.pd_tr, TR_TEXT, 'en-tr'),   # Turkish source for en-tr
            (tr_an, self.tr, self.pd_en, TR_TEXT, 'tr-en'),   # English source for tr-en
            (en_an, self.tr, self.pd_tr, TR_TEXT, 'tr-en'),   # English analyzer for tr-en
            (tr_an, self.en, self.pd_tr, TR_TEXT, 'tr-en'),   # English dictionary for tr-en
            (en_an, self.en, self.pd_en, EN_TEXT, 'en-en'),   # unknown direction
            (en_an, self.en, 999, EN_TEXT, 'en-tr'),          # unknown source
        ]
        for analyzer, dictionary, sid, text, direction in bad:
            self.assertRefused(lambda: extract(self.store, analyzer, dictionary, sid, text, direction))

    def test_add_sense_wrong_combinations(self):
        bad = [
            (self.en, self.pd_en, 'tr-en'), (self.tr, self.pd_en, 'en-tr'), (self.tr, self.pd_en, 'tr-en'),
            (self.en, self.pd_tr, 'tr-en'), (self.en, self.pd_tr, 'en-tr'), (self.tr, self.pd_tr, 'en-tr'),
            (self.en, self.pd_en, 'EN-TR'), (self.en, 999, 'en-tr'),
        ]
        for dictionary, sid, direction in bad:
            self.assertRefused(lambda: add_sense(self.store, dictionary, sid, direction, 'run', 'yönetmek'))

    def test_store_wrong_combinations(self):
        for sid, direction in ((self.pd_en, 'tr-en'), (self.pd_tr, 'en-tr'), (self.pd_en, 'xx')):
            self.assertRefused(lambda: self.store.add_candidate(kind='word', direction=direction, headword='x',
                                                                source_id=sid, engine='t'))
        with self.assertRaises(ValueError):
            self.store.add_source('bad-lang', 'public_domain_text', 'Public domain', 'de')

    def test_both_directions_still_work(self):
        self.assertEqual(self.store.get(add_sense(self.store, self.en, self.pd_en, 'en-tr', 'run', 'yönetmek'))
                         ['direction'], 'en-tr')
        self.assertEqual(self.store.get(add_sense(self.store, self.tr, self.pd_tr, 'tr-en', 'ev', 'household'))
                         ['direction'], 'tr-en')

    def test_command_line_derives_direction_from_source(self):
        import contextlib
        import io
        from lexicon import run
        db = os.path.join(self.tmp.name, 'out', 'cli.db')
        common = ['--db', db, '--dict-db', self.dict_path, '--tr-en-db', self.tr_en_path]
        text = os.path.join(self.tmp.name, 'tr.txt')
        with open(text, 'w', encoding='utf-8') as f:
            f.write(TR_TEXT)
        with contextlib.redirect_stdout(io.StringIO()):
            run.main(common + ['add-source', '--name', 'hoca', '--kind', 'public_domain_text',
                               '--licence', 'Public domain', '--lang', 'tr'])
            run.main(common + ['extract', '--source', 'hoca', '--text', text])
            run.main(common + ['add-sense', '--source', 'hoca', '--headword', 'ev', '--translation', 'household'])
            with self.assertRaises(SystemExit):     # only the builtin Turkish engine exists
                run.main(common + ['extract', '--source', 'hoca', '--text', text, '--engine', 'spacy'])
        store = CandidateStore(db)
        try:
            self.assertEqual({r['direction'] for r in store.candidates()}, {'tr-en'})
            self.assertEqual(store.candidates(kind='sense')[0]['compare_result'], 'possible_new_sense')
        finally:
            store.close()
        self.assertEqual((sha256(self.dict_path), sha256(self.tr_en_path)), self.hashes)


class SentenceSplitterTests(unittest.TestCase):
    """Behaviour and known limits of the dependency-free splitter."""

    def split(self, text):
        return split_sentences(text)

    def test_abbreviations_and_initials(self):
        self.assertEqual(self.split('Mr. Smith met Dr. Brown at St. Paul. They talked.'),
                         ['Mr. Smith met Dr. Brown at St. Paul.', 'They talked.'])
        self.assertEqual(self.split('J. K. Rowling wrote it. Then she left.'),
                         ['J. K. Rowling wrote it.', 'Then she left.'])
        self.assertEqual(self.split('Prof. Dr. Ayşe Kaya geldi. Kalem, defter vb. aldı. Sonra gitti.'),
                         ['Prof. Dr. Ayşe Kaya geldi.', 'Kalem, defter vb. aldı.', 'Sonra gitti.'])

    def test_turkish_capitals_start_sentences(self):
        self.assertEqual(self.split("Şu an İstanbul'dayız. Çok güzel! Öyle mi? Ümit geldi… Işık yandı."),
                         ["Şu an İstanbul'dayız.", 'Çok güzel!', 'Öyle mi?', 'Ümit geldi…', 'Işık yandı.'])

    def test_numbers_quotes_and_dialogue(self):
        self.assertEqual(self.split('It costs 3.5 dollars. He said "Go!" Then he went.'),
                         ['It costs 3.5 dollars.', 'He said "Go!"', 'Then he went.'])
        self.assertEqual(self.split("'Oh dear!' said the Rabbit. 'I shall be late!' The Rabbit ran."),
                         ["'Oh dear!' said the Rabbit.", "'I shall be late!'", 'The Rabbit ran.'])
        self.assertEqual(self.split('Wait... what? No!'), ['Wait... what?', 'No!'])

    def test_known_limits_are_flagged(self):
        # Known limit: Turkish dash dialogue followed by a capitalised repetition is cut in two.
        parts = self.split('– Ver elini! Ver elini! diye seslenmişler. Ama oralı olmamış.')
        self.assertEqual(parts, ['– Ver elini!', 'Ver elini! diye seslenmişler.', 'Ama oralı olmamış.'])
        self.assertIn('short', sentence_flags(parts[0]))
        self.assertIn('speech_inside', sentence_flags(parts[1]))
        self.assertEqual(sentence_flags(parts[2]), [])
        # Known limit: an abbreviation at the true end of a sentence joins it with the next one.
        joined = self.split('He bought apples, pears etc. Then he left.')
        self.assertEqual(len(joined), 1)
        self.assertIn('abbreviation', sentence_flags(joined[0]))
        self.assertIn('starts_lowercase', sentence_flags('e.g. this is odd.'))
        self.assertIn('no_final_punctuation', sentence_flags('The end of a heading'))
        self.assertIn('unbalanced_quotes', sentence_flags('He said "Go and see.'))
        self.assertEqual(sentence_flags('She went home early.'), [])

    def test_headings_and_blank_lines(self):
        self.assertEqual(self.split('# Chapter I\n\nFirst one. Second one.\n\n\nThird one'),
                         ['First one.', 'Second one.', 'Third one'])


class LowConfidenceTests(Base):
    def test_flagged_sentences_give_low_confidence_candidates(self):
        extract(self.store, BuiltinTurkishAnalyzer(self.tr), self.tr, self.pd_tr,
                '– Zıpla! Zıpla! diye bağırmışlar. Bir gün kedisi geldi.', 'tr-en')
        flagged = self.store.candidates(headword='zıpla')[0]
        self.assertEqual(flagged['confidence'], 0.1)
        self.assertIn('short', json.loads(flagged['compare_detail'])['sentence_flags'])
        clean = self.store.candidates(headword='kedisi')[0]
        self.assertEqual(clean['confidence'], 0.2)
        self.assertNotIn('sentence_flags', json.loads(clean['compare_detail']))


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
        approved = self.store.add_source('checked-pd', 'public_domain_text', 'Public domain', 'en')
        self.store.approve_source(approved, 'Hamit', 'https://www.gutenberg.org/ebooks/11')
        expect = {
            # kind, declared licence, licence class, usage permission, scope
            self.pd_en: ('public_domain_text', 'public-domain', 'permissive', 'pending_verification', 'private'),
            approved: ('public_domain_text', 'public-domain', 'permissive', 'allowed', 'shared'),
            sa: ('open_license_text', 'cc-by-sa-4.0', 'needs_approval', 'needs_approval', 'private'),
            unk: ('open_license_text', 'unknown', 'unknown', 'unknown', 'private'),
            book: ('user_book', 'all-rights-reserved', 'private_only', 'private_only', 'private'),
        }
        for sid, (kind, lic, cls, perm, scope) in expect.items():
            src = self.store.source(sid)
            self.assertEqual((src['kind'], src['licence'], src['licence_class'], src['permission']),
                             (kind, lic, cls, perm))
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
    def _accepted(self, sid, head):
        cid = self.store.add_candidate(kind='word', direction='en-tr', headword=head, source_id=sid, engine='t')
        self.store.review(cid, 'accepted', 'Hamit')
        return cid

    def _exported(self):
        out = os.path.join(self.tmp.name, 'out', 'reviewed.jsonl')
        n = self.store.export_reviewed_shared(out)
        with open(out, encoding='utf-8') as f:
            heads = [json.loads(l)['headword'] for l in f]
        self.assertEqual(n, len(heads))
        return heads

    def test_only_reviewed_verified_permissive_candidates_are_exported(self):
        sa = self.store.add_source('wiki', 'open_license_text', 'CC BY-SA 4.0', 'en')
        nc = self.store.add_source('nc', 'open_license_text', 'CC BY-NC-SA 4.0', 'en')
        unk = self.store.add_source('blog', 'open_license_text', 'my own terms', 'en')
        book = self.store.add_source('my-novel', 'user_book', 'Public domain', 'en')  # claim ignored for books
        mit = self.store.add_source('mit-unverified', 'open_license_text', 'MIT', 'en')
        self.store.approve_source(self.pd_en, 'Hamit', 'gutenberg.org licence page')
        for name, sid in [('pd', self.pd_en), ('sa', sa), ('nc', nc), ('unk', unk), ('book', book), ('mit', mit)]:
            self._accepted(sid, name)
        self.store.add_candidate(kind='word', direction='en-tr', headword='pd-unreviewed', source_id=self.pd_en,
                                 engine='t')
        self.assertEqual(self._exported(), ['pd'])

    def test_declared_mit_alone_is_not_shareable(self):
        sid = self.store.add_source('says-mit', 'open_license_text', '--licence MIT'.split()[1], 'en')
        self.assertEqual(self.store.source(sid)['permission'], 'pending_verification')
        self._accepted(sid, 'x')
        self.assertEqual(self._exported(), [])
        self.store.approve_source(sid, 'Hamit', 'https://example.org/LICENSE checked')
        self.assertEqual(self._exported(), ['x'])
        self.store.revoke_source(sid, 'Hamit', 'licence page changed')
        self.assertEqual(self._exported(), [])
        log = self.store.db.execute('SELECT decision, approver FROM source_approval WHERE source_id = ? ORDER BY id',
                                    [sid]).fetchall()
        self.assertEqual([tuple(r) for r in log], [('approve', 'Hamit'), ('revoke', 'Hamit')])

    def test_approval_needs_person_evidence_and_permissive_licence(self):
        sa = self.store.add_source('wiki', 'open_license_text', 'CC BY-SA 4.0', 'en')
        book = self.store.add_source('my-novel', 'user_book', 'MIT', 'en')
        unk = self.store.add_source('blog', 'open_license_text', '', 'en')
        for sid in (sa, book, unk):
            with self.assertRaises(ValueError):
                self.store.approve_source(sid, 'Hamit', 'looks fine')
            with self.assertRaises(sqlite3.IntegrityError):        # direct SQL is refused as well
                self.store.db.execute("INSERT INTO source_approval(source_id, decision, approver, evidence, at) "
                                      "VALUES (?, 'approve', 'x', 'y', 'now')", [sid])
        for approver, evidence in (('', 'url'), ('Hamit', ''), ('  ', '  ')):
            with self.assertRaises(ValueError):
                self.store.approve_source(self.pd_en, approver, evidence)
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.db.execute("INSERT INTO source_approval(source_id, decision, approver, evidence, at) "
                                  "VALUES (?, 'approve', ' ', ' ', 'now')", [self.pd_en])

    def test_source_fields_cannot_be_changed_with_sql(self):
        book = self.store.add_source('my-novel', 'user_book', '', 'en')
        attacks = [
            "UPDATE source SET licence = 'mit', licence_class = 'permissive', kind = 'open_license_text' WHERE id = ?",
            "UPDATE source SET kind = 'public_domain_text' WHERE id = ?",
            "UPDATE source SET licence_class = 'permissive' WHERE id = ?",
            "UPDATE source SET lang = 'tr' WHERE id = ?",
            "UPDATE source SET licence = 'public-domain' WHERE id = ?",
            "DELETE FROM source WHERE id = ?",
        ]
        for sql in attacks:
            with self.assertRaises(sqlite3.IntegrityError, msg=sql):
                self.store.db.execute(sql, [book])
        for sql in ("UPDATE source SET permission = 'allowed'", "UPDATE source SET shareable = 1",
                    "UPDATE candidate SET scope = 'shared'", "UPDATE candidate SET permission = 'allowed'"):
            with self.assertRaises(sqlite3.OperationalError, msg=sql):   # derived, not stored: no such column
                self.store.db.execute(sql)
        self.assertEqual(self.store.source(book)['permission'], 'private_only')

    def test_forged_sources_are_refused(self):
        forged = [
            ('book-as-permissive', 'user_book', 'mit', 'permissive'),
            ('sa-as-permissive', 'open_license_text', 'cc-by-sa-4.0', 'permissive'),
            ('unknown-as-permissive', 'open_license_text', 'whatever', 'permissive'),
            ('mit-as-unknown', 'open_license_text', 'mit', 'unknown'),   # would hide a class mismatch
            ('pd-as-private', 'public_domain_text', 'public-domain', 'private_only'),
        ]
        for name, kind, lic, cls in forged:
            with self.assertRaises(sqlite3.IntegrityError, msg=name):
                self.store.db.execute("INSERT INTO source(name, kind, licence, licence_class, lang, added_at) "
                                      "VALUES (?, ?, ?, ?, 'en', 'now')", [name, kind, lic, cls])

    def test_candidates_cannot_drift_from_their_source(self):
        book = self.store.add_source('my-novel', 'user_book', '', 'en')
        self.store.approve_source(self.pd_en, 'Hamit', 'checked')
        cid = self._accepted(book, 'x')
        for sql in ("UPDATE candidate SET source_id = %d WHERE id = ?" % self.pd_en,
                    "UPDATE candidate SET licence = 'public-domain' WHERE id = ?",
                    "UPDATE candidate SET direction = 'tr-en' WHERE id = ?",
                    "UPDATE candidate SET headword = 'y' WHERE id = ?"):
            with self.assertRaises(sqlite3.IntegrityError, msg=sql):
                self.store.db.execute(sql, [cid])
        with self.assertRaises(sqlite3.IntegrityError):            # licence snapshot must match the source
            self.store.db.execute("INSERT INTO candidate(kind, direction, headword, source_id, licence, engine, "
                                  "created_at, updated_at) VALUES ('word', 'en-tr', 'z', ?, 'mit', 't', 'n', 'n')",
                                  [book])
        with self.assertRaises(sqlite3.IntegrityError):            # direction must match the source language
            self.store.db.execute("INSERT INTO candidate(kind, direction, headword, source_id, licence, engine, "
                                  "created_at, updated_at) VALUES ('word', 'tr-en', 'z', ?, 'public-domain', 't', "
                                  "'n', 'n')", [self.pd_en])
        self.assertEqual(self._exported(), [])

    def test_accepted_by_sql_without_reviewer_is_refused(self):
        self.store.approve_source(self.pd_en, 'Hamit', 'checked')
        cid = self.store.add_candidate(kind='word', direction='en-tr', headword='x', source_id=self.pd_en, engine='t')
        for sql in ("UPDATE candidate SET status = 'accepted' WHERE id = ?",
                    "UPDATE candidate SET status = 'accepted', reviewer = '   ' WHERE id = ?"):
            with self.assertRaises(sqlite3.IntegrityError, msg=sql):
                self.store.db.execute(sql, [cid])
        self.assertEqual(self._exported(), [])

    def test_logs_are_append_only(self):
        cid = self._accepted(self.pd_en, 'x')
        self.store.approve_source(self.pd_en, 'Hamit', 'checked')
        for sql in ("UPDATE review_log SET reviewer = 'someone'", "DELETE FROM review_log",
                    "UPDATE source_approval SET approver = 'someone'", "DELETE FROM source_approval"):
            with self.assertRaises(sqlite3.IntegrityError, msg=sql):
                self.store.db.execute(sql)
        self.assertEqual(self.store.get(cid)['reviewer'], 'Hamit')

    def test_dropped_trigger_blocks_export_and_reopen(self):
        book = self.store.add_source('my-novel', 'user_book', '', 'en')
        self._accepted(book, 'x')
        self.store.db.execute('DROP TRIGGER source_no_update')
        self.store.db.commit()
        with self.assertRaises(IntegrityError):
            self.store.export_reviewed_shared(os.path.join(self.tmp.name, 'out', 'e.jsonl'))
        path = self.store.path
        self.store.close()
        self.store = CandidateStore(path)        # a missing trigger is put back on open ...
        self.store.db.execute("DROP TRIGGER approval_insert_check")
        self.store.db.execute("CREATE TRIGGER approval_insert_check BEFORE INSERT ON source_approval "
                              "BEGIN SELECT 1; END")    # ... and a rewritten one is detected
        with self.assertRaises(IntegrityError):
            self.store.verify_integrity()

    def test_python_recheck_catches_bypassed_sql(self):
        # Even with the triggers dropped and put back, the export re-checks the rules in Python.
        self.store.db.execute('DROP TRIGGER source_insert_check')
        self.store.db.execute('DROP TRIGGER approval_insert_check')
        self.store.db.execute("INSERT INTO source(name, kind, licence, licence_class, lang, added_at) "
                              "VALUES ('forged', 'open_license_text', 'cc-by-sa-4.0', 'permissive', 'en', 'now')")
        sid = self.store.db.execute("SELECT id FROM source WHERE name = 'forged'").fetchone()[0]
        self.store.db.execute("INSERT INTO source_approval(source_id, decision, approver, evidence, at) "
                              "VALUES (?, 'approve', 'x', 'y', 'now')", [sid])
        self.store.db.execute(TRIGGERS['source_insert_check'])
        self.store.db.execute(TRIGGERS['approval_insert_check'])
        self.assertEqual(self.store.source(sid)['permission'], 'allowed')     # SQL view was fooled ...
        self._accepted(sid, 'x')
        self.assertEqual(self._exported(), [])                                # ... the export was not

    def test_user_book_extraction_stays_private(self):
        book = self.store.add_source('my-novel', 'user_book', '', 'en')
        extract(self.store, BuiltinEnglishAnalyzer(self.en), self.en, book, EN_TEXT, 'en-tr')
        self.assertEqual({r['scope'] for r in self.store.candidates(source_id=book)}, {'private'})

    def test_existing_source_name_cannot_be_reused_with_other_licence(self):
        self.store.add_source('my-novel', 'user_book', '', 'en')
        with self.assertRaises(ValueError):
            self.store.add_source('my-novel', 'public_domain_text', 'Public domain', 'en')

    def test_query_filter_rejects_unknown_columns(self):
        with self.assertRaises(ValueError):
            self.store.candidates(**{"1=1 OR status": 'x'})


class ExportEndToEndTests(Base):
    """A full run over a private book and a verified public-domain text: the export must not carry any
    sentence, word or name from the private book, and nothing may be written anywhere else."""

    BOOK = 'The zorblax glimmered over Nimbleford. Zorblaxes never sleep, she whispered. They ran away.'
    PD = 'A quokka hopped up. The quokka ran away.'

    def test_private_book_sentences_never_leave(self):
        book = self.store.add_source('my-private-novel', 'user_book', 'MIT', 'en')   # claimed licence ignored
        extract(self.store, BuiltinEnglishAnalyzer(self.en), self.en, book, self.BOOK, 'en-tr', locator='novel.epub')
        extract(self.store, BuiltinEnglishAnalyzer(self.en), self.en, self.pd_en, self.PD, 'en-tr', locator='pd.txt')
        self.store.approve_source(self.pd_en, 'Hamit', 'Project Gutenberg, US public domain, 1865 text')
        with self.assertRaises(ValueError):
            self.store.approve_source(book, 'Hamit', 'I own it')
        for r in self.store.candidates():          # a reviewer accepts everything, even the private rows
            self.store.review(r['id'], 'accepted', 'Hamit')
        self.assertTrue(self.store.candidates(source_id=book))
        out_dir = os.path.join(self.tmp.name, 'export')
        os.makedirs(out_dir)
        out = os.path.join(out_dir, 'reviewed.jsonl')
        n = self.store.export_reviewed_shared(out)
        self.assertEqual(os.listdir(out_dir), ['reviewed.jsonl'])      # nothing else written
        with open(out, encoding='utf-8') as f:
            text = f.read()
        rows = [json.loads(l) for l in text.splitlines()]
        self.assertEqual(len(rows), n)
        self.assertTrue(rows)
        self.assertEqual({r['source_id'] for r in rows}, {self.pd_en})
        for needle in ('zorblax', 'Zorblax', 'Nimbleford', 'whispered', 'glimmered', 'my-private-novel', 'novel.epub'):
            self.assertNotIn(needle, text)
        # The private rows are still there locally, unchanged and private.
        self.assertEqual({r['scope'] for r in self.store.candidates(source_id=book)}, {'private'})

    def test_tool_has_no_network_code(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        banned = ('socket', 'urllib', 'http', 'requests', 'smtplib', 'ftplib', 'ssl', 'subprocess')
        import re
        for dirpath, _, files in os.walk(root):
            if os.path.basename(dirpath) in ('tests', '__pycache__'):
                continue
            for name in files:
                if name.endswith('.py'):
                    with open(os.path.join(dirpath, name), encoding='utf-8') as f:
                        src = f.read()
                    for mod in banned:
                        self.assertIsNone(re.search(rf'^\s*(import|from)\s+{mod}\b', src, re.M), f'{name}: {mod}')


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

    def test_word_after_leading_dash_or_quote_is_not_a_proper_noun(self):
        tr = BuiltinTurkishAnalyzer(self.tr).analyze('– Eve gitti.')[0]
        self.assertEqual({t.text: t.pos for t in tr.tokens}['Eve'], 'noun')
        en = BuiltinEnglishAnalyzer(self.en).analyze("'Rabbit,' said Alice.")[0]
        pos = {t.text: t.pos for t in en.tokens}
        self.assertEqual((pos['Rabbit'], pos['Alice']), ('', 'PROPN'))

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
