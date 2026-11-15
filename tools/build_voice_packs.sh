#!/usr/bin/env bash
# Builds the offline voice packs the app downloads (Settings > Read aloud):
#   kokoro-en-fp32-v1.zip   Kokoro-82M v1.0 (hexgrad, Apache 2.0), natural English voices (US and UK)
#   piper-en-libritts-v1.zip  Piper LibriTTS-R (CC BY 4.0), light English voices for slow phones
#   ema-tr-v1.zip           EMA Lightning (canberk7, Apache 2.0), natural Turkish voice, as ONNX
#   piper-tr-fahrettin.zip  Piper Turkish voice, CC0 recordings (NabuCasa voice-datasets)
# Sources: sherpa-onnx "tts-models" release; EMA from Hugging Face via tools/ema_export.py
# (needs Python with torch, ema-lightning, onnx, onnxruntime). Usage: tools/build_voice_packs.sh <out_dir>
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
out=$(realpath -m "${1:-voice-packs}")
mkdir -p "$out"
work=$(mktemp -d)
cd "$work"
src=https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models

# eSpeak NG data with only the English and Turkish dictionaries (Piper uses it to
# turn text into sounds). sherpa-onnx loads eSpeak once per process from the first
# model's folder, so every pack carries both.
slim_espeak() { # <from> <to>
  mkdir -p "$2"
  for f in phondata phonindex phontab intonations lang voices en_dict tr_dict; do cp -r "$1/$f" "$2/"; done
}

# English, natural: Kokoro-82M v1.0 in full precision (int8 slurred words in tests).
curl -sSfL "$src/kokoro-multi-lang-v1_0.tar.bz2" | tar xj
k=kokoro-multi-lang-v1_0
mkdir kokoro-en-fp32-v1
cp $k/model.onnx $k/voices.bin $k/tokens.txt $k/lexicon-us-en.txt $k/lexicon-gb-en.txt $k/LICENSE kokoro-en-fp32-v1/
slim_espeak $k/espeak-ng-data kokoro-en-fp32-v1/espeak-ng-data
printf 'Kokoro-82M v1.0 by hexgrad, Apache 2.0 (https://huggingface.co/hexgrad/Kokoro-82M).\n' > kokoro-en-fp32-v1/NOTICE
zip -qr -9 "$out/kokoro-en-fp32-v1.zip" kokoro-en-fp32-v1

# English, light and fast: Piper trained on LibriTTS-R (CC BY 4.0), for slow phones.
curl -sSfL "$src/vits-piper-en_US-libritts_r-medium.tar.bz2" | tar xj
t=vits-piper-en_US-libritts_r-medium
grep -q "License: CC BY 4.0" $t/MODEL_CARD || { echo "unexpected license for libritts_r"; exit 1; }
mkdir piper-en-libritts-v1
cp $t/en_US-libritts_r-medium.onnx piper-en-libritts-v1/model.onnx
cp $t/tokens.txt $t/MODEL_CARD piper-en-libritts-v1/
slim_espeak $t/espeak-ng-data piper-en-libritts-v1/espeak-ng-data
zip -qr -9 "$out/piper-en-libritts-v1.zip" piper-en-libritts-v1

# Turkish, natural: EMA Lightning, exported to ONNX and checked against the original.
python "$repo/tools/ema_export.py" ema-tr-v1
cat > ema-tr-v1/NOTICE <<'TXT'
EMA Lightning by Canberk (https://github.com/canberk7/ema-lightning,
https://huggingface.co/canberkkkkkk/ema-lightning), Apache License 2.0 for the code
and the weights. Converted to ONNX for VocaBloom; the model itself is unchanged.
TXT
zip -qr -9 "$out/ema-tr-v1.zip" ema-tr-v1

for v in fahrettin; do
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
