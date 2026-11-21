#!/usr/bin/env python3
"""Windows update manifest for file-by-file updates.

Writes, for the Windows build folder --dir:
  * one gzip blob per file into --blobs, named after the file's SHA-256
    ("<sha256>.gz"), uploaded to the release next to the full zip;
  * the manifest (--out, and a copy as storilex-manifest.json inside --dir so
    the installed app knows which files it came with).

The app compares each file's SHA-256 with the manifest and downloads only the
blobs of changed or new files. Files in the old manifest but not the new one
are removed. The manifest itself is not listed in its own files.

--compare OLD_DIR prints how much a file-by-file update from OLD_DIR to --dir
would download (used by CI to measure the real gain) and writes nothing else
unless --blobs/--out are given too.
"""
import argparse
import gzip
import hashlib
import json
import os
import sys

MANIFEST_NAME = 'storilex-manifest.json'
SCHEMA = 1


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def list_files(root):
    out = []
    for d, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            full = os.path.join(d, name)
            rel = os.path.relpath(full, root).replace(os.sep, '/')
            if rel == MANIFEST_NAME or os.path.islink(full):
                continue
            out.append((rel, full))
    return out


def gz_bytes(path):
    with open(path, 'rb') as f:
        # mtime=0 and no file name: the same file always gives the same blob.
        return gzip.compress(f.read(), compresslevel=9, mtime=0)


def build(root, blobs=None):
    files = []
    for rel, full in list_files(root):
        digest = sha256_of(full)
        data = gz_bytes(full)
        if blobs:
            target = os.path.join(blobs, digest + '.gz')
            if not os.path.exists(target):
                with open(target, 'wb') as f:
                    f.write(data)
        files.append({'path': rel, 'size': os.path.getsize(full), 'sha256': digest, 'gz': len(data)})
    return files


def compare(old_root, files):
    old = {rel: (os.path.getsize(full), full) for rel, full in list_files(old_root)}
    changed, new, removed, dl = [], [], [], 0
    for f in files:
        o = old.get(f['path'])
        if o is None:
            new.append(f)
        elif o[0] != f['size'] or sha256_of(o[1]) != f['sha256']:
            changed.append(f)
        else:
            continue
        dl += f['gz']
    paths = {f['path'] for f in files}
    removed = sorted(p for p in old if p not in paths)
    return changed, new, removed, dl


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', required=True)
    ap.add_argument('--build', type=int, default=0)
    ap.add_argument('--version', default='')
    ap.add_argument('--blobs')
    ap.add_argument('--out')
    ap.add_argument('--compare', help='an older build folder to measure the update from')
    a = ap.parse_args()

    if a.blobs:
        os.makedirs(a.blobs, exist_ok=True)
    files = build(a.dir, a.blobs)
    if a.out:
        manifest = {'schema': SCHEMA, 'build': a.build, 'version': a.version, 'files': files}
        text = json.dumps(manifest, indent=1, sort_keys=True) + '\n'
        with open(a.out, 'w', encoding='utf-8') as f:
            f.write(text)
        with open(os.path.join(a.dir, MANIFEST_NAME), 'w', encoding='utf-8') as f:
            f.write(text)
    total = sum(f['size'] for f in files)
    total_gz = sum(f['gz'] for f in files)
    print(f'{len(files)} files, {total / 1e6:.1f} MB, {total_gz / 1e6:.1f} MB as gzip blobs')
    if a.compare:
        changed, new, removed, dl = compare(a.compare, files)
        for f in sorted(changed + new, key=lambda f: -f['gz']):
            kind = 'new' if f in new else 'changed'
            print(f'  {kind:8} {f["gz"] / 1e6:8.2f} MB  {f["path"]}')
        for p in removed:
            print(f'  removed            {p}')
        print(f'UPDATE_DOWNLOAD_BYTES={dl}')
        print(f'File-by-file update: {dl / 1e6:.1f} MB of {total_gz / 1e6:.1f} MB '
              f'({len(changed)} changed, {len(new)} new, {len(removed)} removed)')


if __name__ == '__main__':
    sys.exit(main())
