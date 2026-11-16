#!/usr/bin/env python3
"""Writes the body of the 'latest' GitHub release, with a "what's new" list
the app shows in its update banner.

    release_notes.py --version 1.4 --build 212 --prev-body prev.md \
        --commits commits.txt > body.md

* release_notes.json (repo root) holds hand-written entries, newest first.
  An entry gets the build number of the first release that contains it;
  entries already in the previous release keep their build.
* commits.txt holds the subjects of the commits since the previous release.
  Nightly dictionary commits ("Dictionary: 1424 new Turkish meanings") are
  added up into one dictionary entry for this build.

The body has a readable list (GitHub page) and the same entries as JSON in
an HTML comment that the app reads (lib/online/update_check.dart). The first
line keeps "Sürüm X · Build: N", which older app versions look for."""
import argparse, json, os, re

KEEP = 40
MARK = 'vocabloom-notes'
AREAS = {
    'dictionary': 'Sözlük', 'grammar': 'Gramer', 'reader': 'Okuyucu', 'words': 'Kelimelerim',
    'review': 'Tekrar', 'ai': 'Yapay zekâ', 'voice': 'Sesli okuma', 'app': 'Uygulama',
}


def old_entries(body):
    m = re.search(r'<!--\s*%s\s*(\{.*?\})\s*-->' % MARK, body or '', re.S)
    if not m:
        return []
    try:
        return json.loads(m.group(1)).get('entries', [])
    except ValueError:
        return []


def dictionary_entry(subjects, build):
    n = 0
    for s in subjects:
        m = re.match(r'Dictionary:\s*([\d,.]+)\s+new Turkish meanings', s.strip())
        if m:
            n += int(re.sub(r'[,.]', '', m.group(1)))
    if not n:
        return None
    tr_n = '{:,}'.format(n).replace(',', '.')
    en_n = '{:,}'.format(n)
    return {
        'id': 'dictionary-nightly-%d' % build, 'area': 'dictionary', 'build': build,
        'tr': 'Sözlüğe %s yeni Türkçe anlam eklendi.' % tr_n,
        'en': '%s new Turkish meanings in the dictionary.' % en_n,
    }


def build_body(version, build, prev_body, subjects, notes):
    old = {e['id']: e for e in old_entries(prev_body) if 'id' in e}
    entries = []
    for e in notes['entries']:
        x = {k: e[k] for k in ('id', 'area', 'tr', 'en')}
        x['build'] = old[e['id']]['build'] if e['id'] in old and old[e['id']].get('build') else build
        entries.append(x)
    d = dictionary_entry(subjects, build)
    if d:
        entries.append(d)
    # Earlier nightly dictionary entries are not in the file; keep them.
    ids = {e['id'] for e in entries}
    entries += [e for e in old.values() if e['id'] not in ids and e['id'].startswith('dictionary-nightly-')]
    entries.sort(key=lambda e: -int(e.get('build') or 0))
    entries = entries[:KEEP]

    lines = ['Sürüm %s · Build: %d. Windows: zip\'i aç, VocaBloom.exe\'yi çalıştır. Android: APK\'yı kur. '
             'iOS: imzasız IPA, Sideloadly/AltStore ile yükle.' % (version, build), '']
    new = [e for e in entries if e['build'] == build]
    if new:
        lines += ['## Yenilikler', '']
        lines += ['- **%s:** %s' % (AREAS.get(e['area'], e['area']), e['tr']) for e in new]
        lines.append('')
    lines.append('<!-- %s %s -->' % (MARK, json.dumps({'entries': entries}, ensure_ascii=False)))
    return '\n'.join(lines) + '\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--version', required=True)
    ap.add_argument('--build', type=int, required=True)
    ap.add_argument('--prev-body', help='body of the previous release (file)')
    ap.add_argument('--commits', help='commit subjects since the previous release (file)')
    ap.add_argument('--notes', default=os.path.join(os.path.dirname(__file__), '..', '..', 'release_notes.json'))
    a = ap.parse_args()
    prev = open(a.prev_body, encoding='utf-8').read() if a.prev_body and os.path.exists(a.prev_body) else ''
    subjects = open(a.commits, encoding='utf-8').read().splitlines() if a.commits and os.path.exists(a.commits) else []
    notes = json.load(open(a.notes, encoding='utf-8'))
    print(build_body(a.version, a.build, prev, subjects, notes), end='')


if __name__ == '__main__':
    main()
