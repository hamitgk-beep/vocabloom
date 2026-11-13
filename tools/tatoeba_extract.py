"""English-Turkish sentence pairs from Tatoeba (CC BY 2.0 FR).

usage: python3 tools/tatoeba_extract.py eng_sentences.tsv tur_sentences.tsv links.csv out.tsv.gz
Writes "english<TAB>turkish" lines, short natural sentences only.
"""
import gzip
import sys


def load(path):
    out = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 3:
                out[parts[0]] = parts[2]
    return out


def main():
    eng, tur = load(sys.argv[1]), load(sys.argv[2])
    pairs = {}
    with open(sys.argv[3], encoding='utf-8') as f:
        for line in f:
            a, _, b = line.rstrip('\n').partition('\t')
            if a in eng and b in tur:
                e, t = eng[a], tur[b]
                if 3 <= len(e.split()) <= 25 and e not in pairs:
                    pairs[e] = t
    with gzip.open(sys.argv[4], 'wt', encoding='utf-8') as f:
        for e, t in pairs.items():
            f.write(f'{e}\t{t}\n')
    print('pairs', len(pairs))


if __name__ == '__main__':
    main()
