#!/usr/bin/env bash
# Prepares the optional sentence embeddings (embeddings.py) for the lexicon tool:
#   1. installs onnxruntime, tokenizers and numpy (pinned, --no-deps) into the lexicon venv,
#   2. downloads the model files listed in embeddings.lock (118 MB ONNX model + tokenizer) into
#      build/lexicon/embeddings/<model> and verifies each SHA-256,
#   3. runs a smoke test (an English sentence is closer to its Turkish translation than to an unrelated one).
# Nothing is installed system-wide, nothing is committed, the Flutter app is not touched. Re-running is safe.
#   bash tools/lexicon/setup_spacy.sh && bash tools/lexicon/setup_embeddings.sh
#   build/lexicon/venv/bin/python tools/lexicon/eval/evaluate_senses.py --embeddings
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
venv="${LEXICON_VENV:-$root/build/lexicon/venv}"
dest="${EMBEDDINGS_HOME:-$root/build/lexicon/embeddings/paraphrase-multilingual-MiniLM-L12-v2}"
python="${PYTHON:-python3}"
if [ ! -x "$venv/bin/python" ]; then
  "$python" -m venv "$venv"
fi
"$venv/bin/python" -m pip install --quiet --no-deps -r "$here/requirements-embeddings.txt"

grep -v '^#' "$here/embeddings.lock" | while IFS=$'\t' read -r file sha licence url; do
  [ -n "$file" ] || continue
  target="$dest/$file"
  mkdir -p "$(dirname "$target")"
  if [ ! -f "$target" ] || ! echo "$sha  $target" | sha256sum -c --quiet - 2>/dev/null; then
    tmp="$target.part"
    curl -sSfL --retry 4 --retry-delay 2 -o "$tmp" "$url"
    if ! echo "$sha  $tmp" | sha256sum -c --quiet -; then
      rm -f "$tmp"
      echo "checksum mismatch for $file: refusing to use it" >&2
      exit 1
    fi
    mv "$tmp" "$target"
  fi
  echo "ok $file ($licence)"
done

cd "$root/tools"
EMBEDDINGS_HOME="$dest" "$venv/bin/python" - <<'PY'
import os
from lexicon.embeddings import SentenceEncoder
e = SentenceEncoder(os.environ['EMBEDDINGS_HOME'])
s = 'We sat on the grassy bank of the river.'
near, far = e.similarity(s, 'Nehrin çimenli kıyısında oturduk.'), e.similarity(s, 'Bugün bankaya gitmem gerekiyor.')
assert near > far + 0.2, (near, far)
print(f'embeddings ready ({e.engine_id}): {near:.2f} > {far:.2f}')
PY
