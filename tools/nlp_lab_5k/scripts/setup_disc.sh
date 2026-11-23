#!/bin/bash
# DISC (github.com/zzeng13/DISC) in its own venv. Development only. The repo has no requirements.txt (the README
# names one) and no LICENSE file; dependencies are taken from its imports.
set -x
L=$(cd "$(dirname "$0")/.." && pwd); cd "$L"
uv venv -p python3.12 .venv_disc
. .venv_disc/bin/activate
uv pip install "torch==$(.venv/bin/python -c 'import torch;print(torch.__version__.split("+")[0])')" "transformers==4.46.3" nltk scikit-learn tqdm matplotlib numpy tensorboard; echo EXIT_PIP=$?
python -c "import nltk; nltk.download('punkt', quiet=True); nltk.download('punkt_tab', quiet=True); nltk.download('averaged_perceptron_tagger', quiet=True); nltk.download('averaged_perceptron_tagger_eng', quiet=True)"; echo EXIT_NLTK=$?
mkdir -p external/DISC/checkpoints
# the only published checkpoint (README): Google Drive file 1pGX1F03FYWymXcZ0hjJ7kYi3fySW5n54
curl -sS -L -m 60 -o external/DISC/checkpoints/drive_download.bin "https://drive.google.com/uc?export=download&id=1pGX1F03FYWymXcZ0hjJ7kYi3fySW5n54"; echo EXIT_CHECKPOINT_DRIVE=$?
curl -sS -L -m 60 -o external/DISC/checkpoints/drive_download2.bin "https://drive.usercontent.google.com/download?id=1pGX1F03FYWymXcZ0hjJ7kYi3fySW5n54&export=download&confirm=t"; echo EXIT_CHECKPOINT_USERCONTENT=$?
ls -la external/DISC/checkpoints
python -c "from huggingface_hub import snapshot_download; p=snapshot_download('bert-base-uncased', allow_patterns=['*.json','*.txt','*.safetensors']); print(p)"; echo EXIT_BERT=$?
