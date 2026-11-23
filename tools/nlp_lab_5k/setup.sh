#!/bin/bash
# Task 5K NLP lab: development-only setup. Network is used HERE only; the runners and tests work offline after it.
# Never touches the system Python, Flutter dependencies, assets/dict.db or assets/tr_en.db.
#   tools/nlp_lab_5k/setup.sh            # main venv + spaCy sm/md + Stanza en + UDPipe 1 models
#   tools/nlp_lab_5k/setup.sh --external # also clone AMALGrAM, DISC, STREUSLE at the pinned commits
set -euo pipefail
L=$(cd "$(dirname "$0")" && pwd); cd "$L"
mkdir -p models logs external
command -v uv >/dev/null || { echo "uv is required (https://docs.astral.sh/uv/)"; exit 1; }
[ -d .venv ] || uv venv -p python3.12 .venv
. .venv/bin/activate
uv pip install "spacy==3.8.7" "stanza==1.10.1" "ufal.udpipe==1.3.1.1" "click" "psutil" "scipy" "pytest"

fetch() { # url file sha256
  [ -f "models/$2" ] || curl -fsSL -o "models/$2" "$1"
  echo "$3  models/$2" | sha256sum -c -
}
fetch https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl en_core_web_sm-3.8.0-py3-none-any.whl 1932429db727d4bff3deed6b34cfc05df17794f4a52eeb26cf8928f7c1a0fb85
fetch https://github.com/explosion/spacy-models/releases/download/en_core_web_md-3.8.0/en_core_web_md-3.8.0-py3-none-any.whl en_core_web_md-3.8.0-py3-none-any.whl 5e6329fe3fecedb1d1a02c3ea2172ee0fede6cea6e4aefb6a02d832dba78a310
uv pip install models/en_core_web_sm-3.8.0-py3-none-any.whl models/en_core_web_md-3.8.0-py3-none-any.whl
# UDPipe 1 models. lindat.mff.cuni.cz (the official host) was unreachable from the 5K sandbox; these are byte copies:
#  * UD 2.5 EWT, CC BY-NC-SA 4.0 (RESEARCH ONLY), mirrored by the udpipe R package author (jwijffels/udpipe.models.ud.2.5)
#  * UD 2.1 English, CC BY-SA 4.0 (commercial use allowed with attribution + share-alike), bnosac/udpipe.models.ud
fetch https://raw.githubusercontent.com/jwijffels/udpipe.models.ud.2.5/master/inst/udpipe-ud-2.5-191206/english-ewt-ud-2.5-191206.udpipe english-ewt-ud-2.5-191206.udpipe 784bd0fa85e3d831fd02a55290d0acfd05c953159dc38cc33d52e1b28add9957
fetch https://raw.githubusercontent.com/bnosac/udpipe.models.ud/master/models/english-ud-2.1-20180111.udpipe english-ud-2.1-20180111.udpipe 20432a6f87b1f258927207b8fbd2dc21ebff9722b381b7a36cef34c8c9a380dc
python -c "import stanza; stanza.download('en', model_dir='$L/models/stanza', processors='tokenize,mwt,pos,lemma,depparse', package='default')"

if [ "${1:-}" = "--external" ]; then
  clone() { [ -d "external/$2" ] || git clone -q "$1" "external/$2"; git -C "external/$2" checkout -q "$3"; }
  clone https://github.com/nschneid/pysupersensetagger pysupersensetagger 4783c54a28d8e439beb9d115508abb2dc305fbf3
  clone https://github.com/zzeng13/DISC DISC 7542fcd67dfbea448c0cfa76ac34353ae6ab171d
  clone https://github.com/nert-nlp/streusle streusle 8ba61fe4f216e7967500a862554a4fff79d25f5d
fi
echo "setup done; run: tools/nlp_lab_5k/run_lab.sh"
