#!/bin/bash
# Predict with the retrained AMALGrAM model (scripts/amalgram_docker.sh) on every WORKDIR/*.wdpos not yet predicted.
set -u
W=$(cd "$1" && pwd)
SRC=$(cd "$(dirname "$0")/../external/pysupersensetagger" && pwd)
CA=/root/.ccr/ca-bundle.crt
docker run --rm --network host -e HTTPS_PROXY -e https_proxy -e PIP_CERT=/ca.crt -v "$CA":/ca.crt:ro -v "$SRC":/src:ro -v "$W":/w python:2.7 bash -c '
cp -r /src /amalgram && cd /amalgram
pip install -q --disable-pip-version-check "Cython==0.29.36" "nltk==3.4.5" && python2.7 -c "import nltk; nltk.download(\"wordnet\", quiet=True); nltk.download(\"punkt\", quiet=True)"
for f in /w/*.wdpos; do o=${f%.wdpos}.pred.tags; [ -s $o ] && continue
  s=$(date +%s.%N); python2.7 src/main.py --mwe --YY tagsets/bio2g --defaultY O --predict $f --load /w/mwe_streusle_train.model --bio NO_SINGLETON_B > $o 2> ${f%.wdpos}.pred.log; echo EXIT_PREDICT_$(basename $f)=$? seconds=$(echo "$(date +%s.%N) - $s" | bc 2>/dev/null || python2.7 -c "import time;print(time.time()-$s)"); done
'
