#!/usr/bin/env python3
"""Adds the lessons for the expression groups (phrasal verbs, collocations,
idioms, ...) from tools/grammar/phrases/*.py to assets/grammar/lessons.json
and lessons_en.json. Each lesson names the dictionary category it explains
("dict_category"), so its page can open the full list of expressions.

Safe to run again: a lesson with the same id is replaced in place."""
import importlib.util, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
LESSONS = os.path.join(ROOT, 'assets', 'grammar', 'lessons.json')
LESSONS_EN = os.path.join(ROOT, 'assets', 'grammar', 'lessons_en.json')

# Existing lessons that explain a dictionary category.
LINKS = {'irregular_verbs': 'irregular_verbs'}


def load_parts():
    out = []
    for name in sorted(os.listdir(os.path.join(HERE, 'phrases'))):
        if not name.endswith('.py'):
            continue
        spec = importlib.util.spec_from_file_location(name[:-3], os.path.join(HERE, 'phrases', name))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        out += mod.TOPICS
    return out


def build(t):
    if len(t['tr']) < 16 or len(t['gaps']) < 12:
        sys.exit('%s: needs 16 translations and 12 gaps' % t['id'])
    ex, notes = [], {}
    for i, (tr, answers, note_tr, note_en) in enumerate(t['tr']):
        eid = '%s-%d' % (t['id'], i + 1)
        ex.append({'id': eid, 'tr': tr, 'answers': answers, 'note': note_tr})
        notes[eid] = note_en
    for i, (gap, tr, answers, note_tr, note_en) in enumerate(t['gaps']):
        eid = '%s-b%d' % (t['id'], i + 1)
        if gap.count('___') != 1:
            sys.exit('%s: one ___ per gap sentence' % eid)
        ex.append({'id': eid, 'gap': gap, 'tr': tr, 'answers': answers, 'note': note_tr})
        notes[eid] = note_en
    lesson = {
        'id': t['id'], 'category': t['category'], 'level': t['level'],
        'title_tr': t['title_tr'], 'title_en': t['title_en'],
        'explanation': t['explanation_tr'], 'structure': t['structure_tr'],
        'examples': [list(e) for e in t['examples']],
        'exercises': ex, 'aliases': t['aliases'], 'dict_category': t['dict_category'],
    }
    en = {'explanation': t['explanation_en'], 'structure': t['structure_en'], 'notes': notes}
    return lesson, en


def main():
    data = json.load(open(LESSONS, encoding='utf-8'))
    data_en = json.load(open(LESSONS_EN, encoding='utf-8'))
    topics = data['topics']
    for t in topics:
        if t['id'] in LINKS:
            t['dict_category'] = LINKS[t['id']]
    for t in load_parts():
        lesson, en = build(t)
        ids = [x['id'] for x in topics]
        if lesson['id'] in ids:
            topics[ids.index(lesson['id'])] = lesson
        else:
            anchor = t.get('after') or t.get('before')
            if anchor not in ids:
                sys.exit('%s: unknown anchor %s' % (t['id'], anchor))
            at = ids.index(anchor) + (1 if t.get('after') else 0)
            topics.insert(at, lesson)
        data_en['topics'][lesson['id']] = en
    with open(LESSONS, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')
    with open(LESSONS_EN, 'w', encoding='utf-8') as f:
        json.dump(data_en, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('%d lessons, %d exercises' % (len(topics), sum(len(t['exercises']) for t in topics)))


if __name__ == '__main__':
    main()
