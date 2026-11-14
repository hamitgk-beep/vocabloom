#!/usr/bin/env bash
# Builds the offline voice packs the app downloads (Settings > Read aloud):
#   kokoro-en-v1.zip        Kokoro-82M v1.0 int8 (Apache 2.0), English lexicons, eSpeak NG English data
#   piper-tr-fahrettin.zip  Piper Turkish voice, CC0 recordings (NabuCasa voice-datasets)
#   piper-tr-fettah.zip     Piper Turkish voice, CC0 recordings (NabuCasa voice-datasets)
# Sources: sherpa-onnx "tts-models" release. Usage: tools/build_voice_packs.sh <out_dir>
set -euo pipefail
out=$(realpath -m "${1:-voice-packs}")
mkdir -p "$out"
work=$(mktemp -d)
cd "$work"
src=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models

# eSpeak NG data with only the English and Turkish dictionaries. sherpa-onnx loads
# eSpeak once per process from the first model's folder, so every pack carries both.
slim_espeak() { # <from> <to>
  mkdir -p "$2"
  for f in phondata phonindex phontab intonations lang voices en_dict tr_dict; do cp -r "$1/$f" "$2/"; done
}

curl -sSfL "$src/kokoro-int8-multi-lang-v1_0.tar.bz2" | tar xj
k=kokoro-int8-multi-lang-v1_0
mkdir kokoro-en-v1
cp $k/model.int8.onnx $k/voices.bin $k/tokens.txt $k/lexicon-us-en.txt $k/lexicon-gb-en.txt $k/LICENSE kokoro-en-v1/
slim_espeak $k/espeak-ng-data kokoro-en-v1/espeak-ng-data
zip -qr -9 "$out/kokoro-en-v1.zip" kokoro-en-v1

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
