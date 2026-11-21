"""Tests for the context sense suggestion (senses.py) and the optional wordfreq signal (frequency.py).

Run from the repository root:  python3 -m unittest discover -s tools/lexicon/tests -t tools
The wordfreq, spaCy and embedding tests are skipped when those are not set up (setup_spacy.sh --with-wordfreq,
setup_embeddings.sh).
"""
import json
import os
import sqlite3
import unittest

from lexicon.tests.helpers import REPO, sha256  # noqa: F401 (sets sys.path)
from lexicon.tests.test_phase2 import HAVE_SPACY, REAL_DICT, Base, sent
from lexicon import embeddings, frequency
from lexicon.compare import EnTrDictionary
from lexicon.senses import SenseRanker, content_words, stem

BANK = [
    {'pos': 'isim', 'tr': 'banka', 'en': 'I need to go to the bank today to deposit money.'},
    {'pos': 'isim', 'tr': 'kıyı, yamaç', 'note': 'nehir için', 'en': 'We sat on the grassy bank of the river.'},
    {'pos': 'fiil', 'tr': 'yan yatmak', 'en': 'The plane banked sharply before landing.'},
]


def add_senses(path):
    """Synthetic multi-sense entry plus a WordNet synset that is linked through its Turkish translation."""
    db = sqlite3.connect(path)
    db.execute("INSERT INTO own_word VALUES ('bank', ?, '[]', 'contrib', 1, NULL, NULL, NULL)",
               [json.dumps(BANK, ensure_ascii=False)])
    db.execute("INSERT INTO syn VALUES (900, 'n', 'sloping land beside a body of water', ?, ?, ?, NULL)",
               [json.dumps(['they pulled the canoe up on the bank']), json.dumps(['bank']), json.dumps(['kıyı'])])
    db.execute("INSERT INTO sense VALUES ('bank', 'n', 0, 900)")
    db.commit()
    db.close()


class SenseRankerTests(Base):
    def setUp(self):
        super().setUp()
        self.en.close()
        add_senses(self.dict_path)
        self.en = EnTrDictionary(self.dict_path)
        self.ranker = SenseRanker(self.en)

    def test_stem_and_content_words(self):
        self.assertEqual(stem('banks'), 'bank')
        self.assertEqual(stem('rowed'), 'row')
        self.assertEqual(content_words('The rivers were near the bank', exclude=['bank']), {'river', 'near'})

    def test_context_picks_the_sense(self):
        self.assertEqual(self.ranker.suggest('bank', 'He paid the money into the bank.')['index'], 0)
        hint = self.ranker.suggest('bank', 'The boat drifted to the bank of the river.')
        self.assertEqual((hint['index'], hint['tr'], hint['basis'], hint['confidence']),
                         (1, 'kıyı, yamaç', 'context', 0.5))

    def test_linked_wordnet_synset_adds_words(self):
        # "canoe" only appears in the WordNet example of the synset whose Turkish is "kıyı"
        self.assertEqual(self.ranker.suggest('bank', 'They pulled the canoe onto the bank.')['index'], 1)

    def test_word_class_filter_and_order_fallback(self):
        hint = self.ranker.suggest('bank', 'It banked.', upos='VERB')
        self.assertEqual((hint['index'], hint['basis'], hint['confidence']), (2, 'order', 0.3))
        self.assertEqual(self.ranker.suggest('bank', 'Nothing else here.')['index'], 0)   # first sense on a tie

    def test_no_curated_senses(self):
        self.assertIsNone(self.ranker.suggest('quokka', 'A quokka smiled.'))
        self.assertEqual(self.ranker.rank('quokka', 'x'), [])

    def test_works_without_frequency_table(self):
        self.assertIsNotNone(self.ranker.suggest('bank', 'river bank'))    # the test dict has no wfreq table

    def test_example_candidates_get_a_hint_not_a_translation(self):
        self.run_stub([sent('The boat drifted to the bank of the river.',
                            [('boat', 'boat', 'NOUN'), ('bank', 'bank', 'NOUN'), ('river', 'river', 'NOUN')])])
        ex = self.rows('example')['bank']
        self.assertEqual(ex['translation'], '')                            # never filled automatically
        self.assertEqual(ex['status'], 'unverified')
        hint = json.loads(ex['compare_detail'])['sense_hint']
        self.assertEqual((hint['index'], hint['tr']), (1, 'kıyı, yamaç'))

    def test_single_sense_words_and_turkish_get_no_hint(self):
        self.run_stub([sent('They run home.', [('They', 'they', 'PRON'), ('run', 'run', 'VERB')])])
        self.assertNotIn('sense_hint', json.loads(self.rows('example')['run']['compare_detail']))


class StubFrequency:
    lang = 'en'
    table = {'unaccounted': 2.5, 'unaccount': 0.0, 'quokka': 1.2}

    def zipf(self, word):
        return self.table.get(word.lower(), 0.0)

    annotate = frequency.Frequency.annotate


class FrequencyTests(Base):
    def test_lemma_suspect_lowers_confidence(self):
        self.run_stub([sent('It was unaccounted and a quokka.',
                            [('unaccounted', 'unaccount', 'ADJ'), ('quokka', 'quokka', 'NOUN')])],
                      frequency=StubFrequency())
        rows = self.rows('word')
        d = json.loads(rows['unaccount']['compare_detail'])
        self.assertTrue(d['lemma_suspect'])
        self.assertEqual(d['suggested_headword'], 'unaccounted')
        self.assertEqual(rows['unaccount']['confidence'], 0.1)
        q = json.loads(rows['quokka']['compare_detail'])
        self.assertEqual(q['zipf'], 1.2)
        self.assertNotIn('lemma_suspect', q)
        self.assertEqual(rows['quokka']['confidence'], 0.4)

    def test_without_frequency_nothing_is_added(self):
        self.run_stub([sent('A quokka.', [('quokka', 'quokka', 'NOUN')])])
        self.assertNotIn('zipf', json.loads(self.rows('word')['quokka']['compare_detail']))

    def test_missing_package_message(self):
        if frequency.available():
            self.skipTest('package present')
        with self.assertRaises(RuntimeError):
            frequency.Frequency('en')

    @unittest.skipUnless(frequency.available(), 'wordfreq not installed')
    def test_real_wordfreq(self):
        f = frequency.Frequency('en')
        self.assertGreater(f.zipf('house'), 4)
        self.assertEqual(f.zipf('qzxqzx'), 0.0)
        self.assertTrue(f.annotate('unaccounted', 'unaccount').get('lemma_suspect'))
        self.assertTrue(f.source_id.startswith('wordfreq-3.1.1/'))
        tr = frequency.Frequency('tr')
        self.assertGreater(tr.zipf('ev'), 4)
        self.assertNotIn('lemma_suspect', tr.annotate('küflenmiş', 'küflenmek'))


class StubEncoder:
    """Bag-of-words vectors: enough to test how the ranker combines similarities, without the model."""
    engine_id = 'stub-encoder'
    vocab = ['para', 'banka', 'money', 'kıyı', 'nehir', 'river', 'water', 'yatmak', 'plane']

    def encode(self, texts):
        import numpy as np
        rows = []
        for t in texts:
            v = np.array([float(w in t.lower()) for w in self.vocab]) + 1e-6
            rows.append(v / np.linalg.norm(v))
        return np.stack(rows)


class EmbeddingRankerTests(SenseRankerTests):
    def setUp(self):
        try:
            import numpy  # noqa: F401
        except ImportError:
            self.skipTest('numpy not installed')
        super().setUp()
        self.ranker = SenseRanker(self.en, StubEncoder())

    def test_meaning_text_is_compared(self):
        # "kıyı, yamaç (nehir için)" shares "nehir"/"kıyı" with nothing English; the WordNet gloss has "water"
        hint = self.ranker.suggest('bank', 'The water rose over the bank.')
        self.assertEqual((hint['index'], hint['basis'], hint['encoder']), (1, 'context', 'stub-encoder'))

    def test_context_picks_the_sense(self):
        self.assertEqual(self.ranker.suggest('bank', 'banka para').get('index'), 0)

    def test_linked_wordnet_synset_adds_words(self):
        self.assertEqual(self.ranker.suggest('bank', 'the river and the water')['index'], 1)

    def test_word_class_filter_and_order_fallback(self):
        hint = self.ranker.suggest('bank', 'It banked.', upos='VERB')     # one verb sense: no choice to make
        self.assertEqual((hint['index'], hint['basis'], hint['confidence']), (2, 'order', 0.3))

    def test_example_candidates_get_a_hint_not_a_translation(self):
        pass                                        # covered by SenseRankerTests (same code path)


@unittest.skipUnless(embeddings.available(), 'embeddings not set up')
class SentenceEncoderTests(unittest.TestCase):
    def test_cross_lingual_similarity(self):
        e = embeddings.SentenceEncoder()
        s = 'We sat on the grassy bank of the river.'
        self.assertGreater(e.similarity(s, 'Nehrin çimenli kıyısında oturduk.'),
                           e.similarity(s, 'Bugün bankaya gitmem gerekiyor.') + 0.2)
        v = e.encode([s, s])
        self.assertEqual(v.shape, (2, 384))
        self.assertAlmostEqual(float(v[0] @ v[0]), 1.0, places=4)

    def test_lock_file_matches_code(self):
        with open(os.path.join(REPO, 'tools', 'lexicon', 'embeddings.lock'), encoding='utf-8') as f:
            rows = [l.split('\t') for l in f if l.strip() and not l.startswith('#')]
        self.assertIn(embeddings.MODEL_FILE.replace(os.sep, '/'), [r[0] for r in rows])
        self.assertTrue(all(r[3].strip().split('/resolve/')[1].startswith('e8f8c211226b') for r in rows))


class SenseEvaluationThresholdTests(unittest.TestCase):
    """Guards the measured quality on eval/sense_gold.jsonl (99 public-domain sentences, real dict.db read-only)."""

    def _run(self, engine, encoder=None):
        from lexicon.eval.evaluate_senses import evaluate, load_gold
        d = EnTrDictionary(REAL_DICT)
        try:
            before = sha256(REAL_DICT)
            r = evaluate(engine, d, load_gold(), encoder)
            self.assertEqual(sha256(REAL_DICT), before)
            return r
        finally:
            d.close()

    def test_builtin_beats_first_sense(self):
        r = self._run('builtin')
        self.assertGreaterEqual(r['accuracy'], 0.45)
        self.assertGreater(r['accuracy'], r['first_sense'])

    @unittest.skipUnless(HAVE_SPACY, 'spaCy not installed')
    def test_spacy(self):
        r = self._run('spacy')
        self.assertGreaterEqual(r['accuracy'], 0.55)
        self.assertGreater(r['accuracy'], r['pos_only'])
        self.assertGreaterEqual(r['context_precision'], 0.75)

    @unittest.skipUnless(HAVE_SPACY and embeddings.available(), 'spaCy or embeddings not set up')
    def test_spacy_with_embeddings(self):
        r = self._run('spacy', embeddings.SentenceEncoder())
        self.assertGreaterEqual(r['accuracy'], 0.6)
        self.assertGreaterEqual(r['context_coverage'], 0.5)


if __name__ == '__main__':
    unittest.main()
