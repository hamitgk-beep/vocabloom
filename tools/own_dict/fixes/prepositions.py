"""Puts the missing preposition senses of 'through' and 'except' first
in own_word (the AI draft followed WordNet, which has no prepositions).
Approved by Hamit on 2026-11-21. Running it again changes nothing.
usage: python3 tools/own_dict/fixes/prepositions.py path/to/dict.db"""
import json, sqlite3, sys
NEW = {
  'through': [
    {"pos": "edat", "tr": "boyunca, baştan sona", "note": "", "en": "from the beginning to the end of a period or activity",
     "ex": "It rained all through the night.", "ex_tr": "Bütün gece boyunca yağmur yağdı."},
    {"pos": "edat", "tr": "içinden, arasından (geçerek)", "note": "", "en": "in at one side or end and out at the other",
     "ex": "The train went through the tunnel.", "ex_tr": "Tren tünelin içinden geçti."},
    {"pos": "edat", "tr": "aracılığıyla, sayesinde", "note": "", "en": "by means of; because of",
     "ex": "I got the job through a friend.", "ex_tr": "İşi bir arkadaşım aracılığıyla buldum."},
  ],
  'except': [
    {"pos": "edat", "tr": "hariç, dışında", "note": "", "en": "not including; other than",
     "ex": "Everyone came except Tom.", "ex_tr": "Tom hariç herkes geldi."},
  ],
}
db = sqlite3.connect(sys.argv[1])
for w, add in NEW.items():
    old = json.loads(db.execute('SELECT senses FROM own_word WHERE word=?', (w,)).fetchone()[0])
    have = {s['tr'] for s in old}
    db.execute('UPDATE own_word SET senses=? WHERE word=?',
               (json.dumps([s for s in add if s['tr'] not in have] + old, ensure_ascii=False), w))
    print(w, len(old), '->', len(json.loads(db.execute('SELECT senses FROM own_word WHERE word=?', (w,)).fetchone()[0])))
db.commit()
