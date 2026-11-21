#!/usr/bin/env bash
# Creates build/lexicon/venv with spaCy 3.8.18 and en_core_web_sm 3.8.0 (both MIT) at pinned versions.
# Nothing is installed system-wide and the Flutter app is not touched. Re-running is safe.
#   bash tools/lexicon/setup_spacy.sh                  # spaCy only
#   bash tools/lexicon/setup_spacy.sh --with-wordfreq  # also wordfreq 3.1.1 (code Apache-2.0, data CC BY-SA 4.0)
#   build/lexicon/venv/bin/python tools/lexicon/run.py extract --engine spacy ...
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
venv="${LEXICON_VENV:-$root/build/lexicon/venv}"
python="${PYTHON:-python3}"
if [ ! -x "$venv/bin/python" ]; then
  "$python" -m venv "$venv"
fi
"$venv/bin/python" -m pip install --quiet --upgrade pip
"$venv/bin/python" -m pip install --quiet -r "$here/requirements-spacy.txt" -c "$here/constraints-spacy.txt"
"$venv/bin/python" - <<'PY'
import spacy
nlp = spacy.load('en_core_web_sm')
lic = nlp.meta.get('license')
assert lic == 'MIT', f'unexpected model licence: {lic}'
print(f'spaCy {spacy.__version__}, en_core_web_sm {nlp.meta["version"]} ({lic}) ready')
PY
if [ "${1:-}" = "--with-wordfreq" ]; then
  "$venv/bin/python" -m pip install --quiet -r "$here/requirements-wordfreq.txt"
  "$venv/bin/python" -c "from wordfreq import zipf_frequency as z; assert z('house', 'en') > 4 and z('ev', 'tr') > 4; print('wordfreq ready')"
fi
echo "Use: $venv/bin/python tools/lexicon/run.py ... --engine spacy"
