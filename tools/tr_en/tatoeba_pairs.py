"""Joins Tatoeba exports into id <TAB> turkish <TAB> english lines.

usage: python3 tatoeba_pairs.py tur_sentences.tsv eng_sentences.tsv tur-eng_links.tsv OUT.tsv
"""
import sys


def read(path):
    d = {}
    for line in open(path, encoding='utf-8'):
        p = line.rstrip('\n').split('\t')
        if len(p) >= 3:
            d[p[0]] = p[2]
    return d


tur, eng = read(sys.argv[1]), read(sys.argv[2])
done = set()
with open(sys.argv[4], 'w', encoding='utf-8') as f:
    for line in open(sys.argv[3], encoding='utf-8'):
        p = line.split()
        if len(p) >= 2 and p[0] in tur and p[1] in eng and p[0] not in done:
            done.add(p[0])
            f.write(p[0] + '\t' + tur[p[0]] + '\t' + eng[p[1]] + '\n')
