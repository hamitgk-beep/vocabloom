#!/usr/bin/env bash
# Builds the offline voice packs the app downloads (Settings > Read aloud):
#   supertonic-en-v2.zip    Supertonic 2 int8 (Supertone; OpenRAIL-M model, MIT code), 10 English voices
#   piper-tr-fahrettin.zip  Piper Turkish voice, CC0 recordings (NabuCasa voice-datasets)
#   piper-tr-fettah.zip     Piper Turkish voice, CC0 recordings (NabuCasa voice-datasets)
# Sources: sherpa-onnx "tts-models" release. Usage: tools/build_voice_packs.sh <out_dir>
set -euo pipefail
out=$(realpath -m "${1:-voice-packs}")
mkdir -p "$out"
work=$(mktemp -d)
cd "$work"
src=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models

# eSpeak NG data with only the English and Turkish dictionaries (Piper uses it to
# turn text into sounds). sherpa-onnx loads eSpeak once per process from the first
# model's folder, so every Piper pack carries both.
slim_espeak() { # <from> <to>
  mkdir -p "$2"
  for f in phondata phonindex phontab intonations lang voices en_dict tr_dict; do cp -r "$1/$f" "$2/"; done
}

curl -sSfL "$src/sherpa-onnx-supertonic-tts-int8-2026-03-06.tar.bz2" | tar xj
k=sherpa-onnx-supertonic-tts-int8-2026-03-06
mkdir supertonic-en-v2
cp $k/*.onnx $k/tts.json $k/unicode_indexer.bin $k/voice.bin $k/LICENSE supertonic-en-v2/
printf 'Supertonic 2 by Supertone Inc. Model: OpenRAIL-M (https://huggingface.co/Supertone/supertonic-2/blob/main/LICENSE). Code: MIT.\n' > supertonic-en-v2/NOTICE
# the app checks for tokens.txt to know a pack is complete
echo supertonic > supertonic-en-v2/tokens.txt
zip -qr -9 "$out/supertonic-en-v2.zip" supertonic-en-v2

for v in fahrettin fettah; do
  curl -sSfL "$src/vits-piper-tr_TR-$v-medium.tar.bz2" | tar xj
  d=vits-piper-tr_TR-$v-medium
  grep -q "License: CC0" $d/MODEL_CARD || { echo "unexpected license for $v"; exit 1; }
  mkdir piper-tr-$v
  cp $d/tr_TR-$v-medium.onnx piper-tr-$v/model.onnx
  cp $d/tokens.txt $d/MODEL_CARD piper-tr-$v/
  slim_espeak $d/espeak-ng-data piper-tr-$v/espeak-ng-data
  zip -qr -9 "$out/piper-tr-$v.zip" piper-tr-$v
done
ls -la "$out"
