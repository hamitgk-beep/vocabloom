"""Task 6A: put the checked Turkish of WordNet meanings that had none into assets/dict.db.

usage: python3 -I tools/library_audit_6a/apply_tr_6a.py assets/dict.db [--dry-run]

Reads tools/data/syn-claude-6a.jsonl.gz ({"id": <syn id>, "tr": [...], "ex": []}, the format of tools/pretranslate.py
results, so build_dict.load_syn reads the same file in a full rebuild). A meaning is written only where the dictionary
has no Turkish for it (tr NULL or '[]'); nothing else in the dictionary changes. Each line passed every check of
tools/library_audit_6a/data/syn_tr_6a_evidence.jsonl:
  * its Turkish words are also given for the word by the open dictionaries in `ft` (Wiktionary, damdafayton), the rule
    tools/main_meanings.py applies to every WordNet meaning, and the draft's first (main) Turkish is among them;
  * the meaning was found in at least two different sentences of the library (stories and books), each judged blind;
  * a second, separate check kept only the Turkish that fits those sentences.
Prints how many rows changed and the SHA-256 of the file before and after. Standard library only.
"""
import gzip, hashlib, json, os, sqlite3, sys

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'syn-claude-6a.jsonl.gz')


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


def main(db_path, dry=False):
    before = sha(db_path)
    rows = [json.loads(l) for l in gzip.open(DATA, 'rt', encoding='utf-8') if l.strip()]
    db = sqlite3.connect(db_path)
    changed = skipped = 0
    for r in rows:
        tr = [t for t in r['tr'] if t][:4]
        if not tr:
            continue
        n = db.execute("UPDATE syn SET tr=? WHERE id=? AND (tr IS NULL OR tr='[]')",
                       (json.dumps(tr, ensure_ascii=False), int(r['id']))).rowcount
        changed += n
        skipped += 1 - n
    if dry:
        db.rollback()
    else:
        db.commit()
        db.execute('VACUUM')
    db.close()
    print(f'meanings in file {len(rows)}, written {changed}, already had Turkish {skipped}{" (dry run)" if dry else ""}')
    print(f'sha256 before {before}')
    print(f'sha256 after  {sha(db_path)}')


if __name__ == '__main__':
    main(sys.argv[1], '--dry-run' in sys.argv)
