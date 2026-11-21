"""Runs a full extraction over whole public-domain books and writes what it found, for manual checking.

  python3 tools/lexicon/eval/corpus.py --engine spacy library/books/pg-55.md.gz library/books/pg-120.md.gz ...
  python3 tools/lexicon/eval/corpus.py --lang tr --engine zemberek library/books/trb-*.md.gz

Writes build/lexicon/eval/<lang>-<engine>/candidates.db (a throw-away candidate store) and candidates.tsv
(kind, headword, pos, confidence, occurrences, compare result, book, example). dict.db is opened read-only.
Each book is a separate public-domain source; nothing is approved, so nothing here is exportable.
"""
import argparse
import csv
import gzip
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))

from lexicon.adapters.english import make_english  # noqa: E402
from lexicon.adapters.turkish import make_turkish  # noqa: E402
from lexicon.compare import EnTrDictionary, TrEnDictionary  # noqa: E402
from lexicon.extract import extract  # noqa: E402
from lexicon.safety import check_writable_target, repo_root  # noqa: E402
from lexicon.store import CandidateStore  # noqa: E402


def read_book(path):
    opener = gzip.open if path.endswith('.gz') else open
    with opener(path, 'rt', encoding='utf-8') as f:
        text = f.read()
    # Markdown markup is not prose: drop headings' hashes, emphasis marks and image/link syntax.
    text = re.sub(r'!\[[^\]]*\]\([^)]*\)', ' ', text)
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'^#+\s*', '', text, flags=re.M)
    return text.replace('_', '').replace('*', '')


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('books', nargs='+')
    p.add_argument('--lang', default='en', choices=['en', 'tr'])
    p.add_argument('--engine', default='builtin', choices=['builtin', 'spacy', 'zemberek'])
    p.add_argument('--dict-db', default=os.path.join(repo_root(), 'assets', 'dict.db'))
    p.add_argument('--tr-en-db', default=os.path.join(repo_root(), 'assets', 'tr_en.db'))
    p.add_argument('--wordfreq', action='store_true', help='add wordfreq Zipf values (frequency.py)')
    p.add_argument('--out', default=os.path.join(repo_root(), 'build', 'lexicon', 'eval'))
    a = p.parse_args(argv)
    out = os.path.join(a.out, f'{a.lang}-{a.engine}' + ('-wordfreq' if a.wordfreq else ''))
    os.makedirs(out, exist_ok=True)
    db_path = check_writable_target(os.path.join(out, 'candidates.db'))
    if os.path.exists(db_path):
        os.remove(db_path)
    if a.lang == 'en':
        dictionary = EnTrDictionary(a.dict_db)
        analyzer = make_english(a.engine, dictionary)
    else:
        dictionary = TrEnDictionary(a.tr_en_db)
        analyzer = make_turkish(a.engine, dictionary)
    direction = 'en-tr' if a.lang == 'en' else 'tr-en'
    frequency = None
    if a.wordfreq:
        from lexicon.frequency import Frequency
        frequency = Frequency(a.lang)
    store = CandidateStore(db_path)
    totals = {}
    for path in a.books:
        name = os.path.basename(path).split('.')[0]
        sid = store.add_source(name, 'public_domain_text', 'Public domain', a.lang)
        t0 = time.time()
        counts = extract(store, analyzer, dictionary, sid, read_book(path), direction, locator=name,
                         frequency=frequency)
        counts['seconds'] = round(time.time() - t0, 1)
        print(name, json.dumps(counts))
        for k, v in counts.items():
            totals[k] = round(totals.get(k, 0) + v, 1)
    print('total', json.dumps(totals))
    tsv = os.path.join(out, 'candidates.tsv')
    rows = store.db.execute('''SELECT c.kind, c.headword, c.pos, c.confidence, c.occurrences, c.compare_result,
                                      s.name AS book, c.example, c.compare_detail
                               FROM candidate c JOIN source s ON s.id = c.source_id
                               WHERE c.kind != 'example' ORDER BY c.kind, c.headword''').fetchall()
    with open(check_writable_target(tsv), 'w', encoding='utf-8', newline='') as f:
        w = csv.writer(f, delimiter='\t')
        w.writerow(['kind', 'headword', 'pos', 'confidence', 'occurrences', 'compare_result', 'book', 'example',
                    'detail'])
        for r in rows:
            w.writerow(list(r))
    store.close()
    dictionary.close()
    print('wrote', tsv)


if __name__ == '__main__':
    main()
