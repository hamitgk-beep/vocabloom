"""Command line for the lexicon candidate pipeline. Run from the repository root:

  python3 tools/lexicon/run.py add-source --name alice --kind public_domain_text --licence "Public domain" --lang en
  python3 tools/lexicon/run.py extract --source alice --text book.txt [--engine builtin|spacy]
  python3 tools/lexicon/run.py add-sense --source manual-en --headword run --translation "yönetmek"
  python3 tools/lexicon/run.py review --id 12 --status accepted --reviewer Hamit
  python3 tools/lexicon/run.py summary
  python3 tools/lexicon/run.py export --out build/lexicon/reviewed.jsonl

The candidate database defaults to build/lexicon/candidates.db (git-ignored). assets/dict.db and
assets/tr_en.db are only opened read-only.
"""
import argparse
import gzip
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lexicon.compare import EnTrDictionary, TrEnDictionary  # noqa: E402
from lexicon.extract import add_sense, extract  # noqa: E402
from lexicon.safety import repo_root  # noqa: E402
from lexicon.store import CandidateStore  # noqa: E402


def _open_dictionary(args, lang):
    if lang == 'en':
        return EnTrDictionary(args.dict_db)
    return TrEnDictionary(args.tr_en_db)


def _source_id(store, name):
    r = store.db.execute('SELECT id FROM source WHERE name = ?', [name]).fetchone()
    if r is None:
        sys.exit(f'unknown source: {name} (add it with add-source)')
    return r['id']


def _read_text(path):
    opener = gzip.open if path.endswith('.gz') else open
    with opener(path, 'rt', encoding='utf-8') as f:
        return f.read()


def main(argv=None):
    root = repo_root()
    p = argparse.ArgumentParser(description='Storilex lexicon candidate pipeline')
    p.add_argument('--db', default=os.path.join(root, 'build', 'lexicon', 'candidates.db'))
    p.add_argument('--dict-db', default=os.path.join(root, 'assets', 'dict.db'))
    p.add_argument('--tr-en-db', default=os.path.join(root, 'assets', 'tr_en.db'))
    sub = p.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('add-source')
    s.add_argument('--name', required=True)
    s.add_argument('--kind', required=True)
    s.add_argument('--licence', default='')
    s.add_argument('--licence-url', default='')
    s.add_argument('--lang', required=True, choices=['en', 'tr'])
    s = sub.add_parser('extract')
    s.add_argument('--source', required=True)
    s.add_argument('--text', required=True)
    s.add_argument('--engine', default='builtin', choices=['builtin', 'spacy'])
    s.add_argument('--include-forms', action='store_true')
    s = sub.add_parser('add-sense')
    s.add_argument('--source', required=True)
    s.add_argument('--headword', required=True)
    s.add_argument('--translation', required=True)
    s.add_argument('--kind', default='sense', choices=['sense', 'phrasal_verb', 'idiom', 'collocation'])
    s.add_argument('--pos', default='')
    s.add_argument('--definition', default='')
    s.add_argument('--example', default='')
    s.add_argument('--example-translation', default='')
    s = sub.add_parser('review')
    s.add_argument('--id', type=int, required=True)
    s.add_argument('--status', required=True, choices=['needs_review', 'accepted', 'rejected', 'unverified'])
    s.add_argument('--reviewer', required=True)
    s.add_argument('--note', default='')
    sub.add_parser('summary')
    s = sub.add_parser('export')
    s.add_argument('--out', required=True)
    args = p.parse_args(argv)

    store = CandidateStore(args.db)
    try:
        if args.cmd == 'add-source':
            sid = store.add_source(args.name, args.kind, args.licence, args.lang, args.licence_url)
            print(json.dumps(dict(store.source(sid)), ensure_ascii=False))
        elif args.cmd in ('extract', 'add-sense'):
            sid = _source_id(store, args.source)
            lang = store.source(sid)['lang']
            direction = 'en-tr' if lang == 'en' else 'tr-en'
            dictionary = _open_dictionary(args, lang)
            try:
                if args.cmd == 'extract':
                    if lang == 'en':
                        from lexicon.adapters.english import make_english
                        analyzer = make_english(args.engine, dictionary)
                    else:
                        if args.engine != 'builtin':
                            sys.exit('only the builtin Turkish engine is available')
                        from lexicon.adapters.turkish import make_turkish
                        analyzer = make_turkish('builtin', dictionary)
                    counts = extract(store, analyzer, dictionary, sid, _read_text(args.text), direction,
                                     locator=os.path.basename(args.text), include_forms=args.include_forms)
                    print(json.dumps(counts, ensure_ascii=False))
                else:
                    cid = add_sense(store, dictionary, sid, direction, args.headword, args.translation,
                                    pos=args.pos, definition=args.definition, example=args.example,
                                    example_translation=args.example_translation, kind=args.kind)
                    print(json.dumps(dict(store.get(cid)), ensure_ascii=False))
            finally:
                dictionary.close()
        elif args.cmd == 'review':
            store.review(args.id, args.status, args.reviewer, args.note)
            print(json.dumps(dict(store.get(args.id)), ensure_ascii=False))
        elif args.cmd == 'summary':
            print(json.dumps(store.summary(), ensure_ascii=False, indent=1))
        elif args.cmd == 'export':
            print(f'{store.export_reviewed_shared(args.out)} reviewed shared candidates written to {args.out}')
    finally:
        store.close()


if __name__ == '__main__':
    main()
