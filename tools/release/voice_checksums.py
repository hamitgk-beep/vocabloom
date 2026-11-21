#!/usr/bin/env python3
"""voice-models.json for the "voice-models" release: the SHA-256 and size of
every voice pack zip given, keyed by pack id (the file name without .zip).
The app checks a downloaded pack against it (lib/tts/voice_checksum.dart).

  python3 -I tools/release/voice_checksums.py dist/*.zip > dist/voice-models.json
"""
import hashlib
import json
import os
import sys


def main(paths):
    packs = {}
    for path in sorted(paths):
        h = hashlib.sha256()
        with open(path, 'rb') as f:
            for chunk in iter(lambda: f.read(1 << 20), b''):
                h.update(chunk)
        packs[os.path.basename(path)[:-4]] = {'sha256': h.hexdigest(), 'size': os.path.getsize(path)}
    json.dump({'schema': 1, 'packs': packs}, sys.stdout, indent=1, sort_keys=True)
    print()


if __name__ == '__main__':
    main([p for p in sys.argv[1:] if p.endswith('.zip')])
