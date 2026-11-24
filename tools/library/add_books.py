#!/usr/bin/env python3
"""Adds new Project Gutenberg books from books.tsv to the library without rebuilding it (Task 6A).

build_library.py rebuilds every story and book, and a book's pictures come from its GITenberg HTML clone; without
those clones it would remove the pictures of the books already there. This script only makes the books whose ids are
given: their text in library/books/pg-<id>.md.gz and their entry in assets/library/catalog.json, the same way
build_library.py does for a book without an HTML edition (no pictures). Other entries and files stay as they are.

  python3 tools/library/add_books.py --books-cache /tmp/gut 708 54 486 ...
  (books missing from --books-cache are downloaded from the GITenberg mirror given in books.tsv)
"""
import argparse
import gzip
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_library as bl  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--books-cache', required=True)
    ap.add_argument('ids', nargs='+')
    a = ap.parse_args()
    bl.load_ranks()
    rows = {r[0]: r for r in bl.read_books_tsv()}
    path = os.path.join(bl.ROOT, 'assets', 'library', 'catalog.json')
    catalog = json.load(open(path, encoding='utf-8'))
    out_books = os.path.join(bl.ROOT, 'library', 'books')
    for gid in a.ids:
        gid, repo, fname, title, author, lvl, how = rows[gid]
        bid = f'pg-{gid}'
        raw = bl.fetch_book(a.books_cache, gid, repo, fname)
        md, chapters = bl.book_markdown(raw, title, author, how)
        _, _, _, words = bl.stats(re.sub(r'^!\[.*$', '', md, flags=re.M))
        data = gzip.compress(md.encode('utf-8'), 9, mtime=0)
        open(os.path.join(out_books, f'{bid}.md.gz'), 'wb').write(data)
        item = {
            'id': bid, 'kind': 'book', 'title': title, 'author': author, 'level': lvl,
            'words': words, 'chapters': chapters, 'size': len(data), 'license': 'Public domain',
            'credit': 'Project Gutenberg', 'source': f'https://www.gutenberg.org/ebooks/{gid}',
        }
        catalog = [c for c in catalog if c['id'] != bid] + [item]
        print(f'{bid}: {chapters} chapters, {words} words, {len(data) // 1024}KB {title}', file=sys.stderr)
    catalog.sort(key=lambda c: (bl.LEVELS.index(c['level']), c['kind'] != 'book', c['words']))
    json.dump(catalog, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=0)


if __name__ == '__main__':
    main()
