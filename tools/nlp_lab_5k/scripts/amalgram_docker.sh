#!/bin/bash
# AMALGrAM 2.0 (github.com/nschneid/pysupersensetagger) in an isolated Python 2.7 container. Development only.
# usage: scripts/amalgram_docker.sh WORKDIR   (WORKDIR holds train.mwe/dev.mwe/test.mwe and *.wdpos inputs)
# Step 1 tries the ORIGINAL pretrained model + MWE lexicons (cs.cmu.edu/~ark/LexSem); step 2 RETRAINS the original,
# unmodified code on STREUSLE train (MWE-only, no lexicon/cluster features) because step 1's resources are unreachable.
set -u
W=$(cd "$1" && pwd)
SRC=$(cd "$(dirname "$0")/../external/pysupersensetagger" && pwd)
CA=/root/.ccr/ca-bundle.crt
docker run --rm --network host -e HTTPS_PROXY -e https_proxy -e PIP_CERT=/ca.crt -e SSL_CERT_FILE=/ca.crt -e REQUESTS_CA_BUNDLE=/ca.crt \
  -v "$CA":/ca.crt:ro -v "$SRC":/src:ro -v "$W":/w python:2.7 bash -c '
set -x
python2.7 --version
cp -r /src /amalgram && cd /amalgram
pip install --disable-pip-version-check "Cython==0.29.36" "nltk==3.4.5"; echo EXIT_PIP=$?
python2.7 -c "import nltk; nltk.download(\"wordnet\", quiet=True); nltk.download(\"punkt\", quiet=True)"; echo EXIT_WORDNET=$?
# step 1: original resources
curl -sS -m 30 -o /w/LexSem.html http://www.cs.cmu.edu/~ark/LexSem/; echo EXIT_ORIG_MODEL_PAGE=$?
curl -sS -m 30 -o /w/sst.model.pickle.gz http://www.cs.cmu.edu/~ark/LexSem/sst.model.pickle.gz; echo EXIT_ORIG_MODEL=$?
# step 2: retrain the original code on STREUSLE train
python2.7 src/mwe2tags.py /w/train.mwe > /w/train.tags 2> /w/train.mwe2tags.err; echo EXIT_TAGS_TRAIN=$?
python2.7 src/mwe2tags.py /w/dev.mwe > /w/dev.tags 2> /w/dev.mwe2tags.err
python2.7 src/mwe2tags.py /w/test.mwe > /w/test.tags 2> /w/test.mwe2tags.err
time python2.7 src/main.py --mwe --YY tagsets/bio2g --defaultY O --train /w/train.tags --test-predict /w/dev.tags --iters 3 --save /w/mwe_streusle_train.model --bio NO_SINGLETON_B > /w/dev.pred.tags 2> /w/train.log; echo EXIT_TRAIN=$?
for f in /w/*.wdpos; do python2.7 src/main.py --mwe --YY tagsets/bio2g --defaultY O --predict $f --load /w/mwe_streusle_train.model --bio NO_SINGLETON_B > ${f%.wdpos}.pred.tags 2> ${f%.wdpos}.pred.log; echo EXIT_PREDICT_$(basename $f)=$?; done
python2.7 src/tags2mwe.py /w/dev.tags > /w/dev.gold.mwe; python2.7 src/tags2mwe.py /w/dev.pred.tags > /w/dev.pred.mwe
python2.7 src/mweval.py --default-strength strong /w/dev.gold.mwe /w/dev.pred.mwe > /w/dev.mweval.txt 2>&1; echo EXIT_EVAL_DEV=$?
'
