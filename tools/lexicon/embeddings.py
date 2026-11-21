"""Optional sentence embeddings for the lexicon tool: a Sentence Transformers model run through ONNX Runtime.

Model: sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2 (Apache-2.0 on its model card), revision
e8f8c211226b894fcb81acc59f3b34ba3efd5f42, file onnx/model_qint8_avx512.onnx (8-bit, 118 MB) and tokenizer.json,
both SHA-256 pinned in embeddings.lock. It maps English and Turkish sentences into the same 384-number space, so an
English sentence can be compared with a sense's English examples and with its Turkish meaning.

Why not the sentence-transformers package itself: it needs PyTorch (several GB). The same model is published in
ONNX form; onnxruntime (MIT) + tokenizers (Apache-2.0) + numpy run it with mean pooling, which is what the model's
1_Pooling/config.json specifies. Nothing here opens a network connection: setup_embeddings.sh downloads and checks
the files once into build/lexicon/embeddings (git-ignored). Developer machines only; the app never uses this and
the model is never bundled with it.
"""
import importlib.util
import os

from .safety import repo_root

MODEL_NAME = 'paraphrase-multilingual-MiniLM-L12-v2'
MODEL_FILE = os.path.join('onnx', 'model_qint8_avx512.onnx')
INSTALL_HINT = 'sentence embeddings are not set up: bash tools/lexicon/setup_embeddings.sh'


def default_home():
    return os.path.join(repo_root(), 'build', 'lexicon', 'embeddings', MODEL_NAME)


def available(home=None):
    home = home or default_home()
    return (all(importlib.util.find_spec(m) for m in ('onnxruntime', 'tokenizers', 'numpy'))
            and os.path.exists(os.path.join(home, MODEL_FILE)) and os.path.exists(os.path.join(home, 'tokenizer.json')))


class SentenceEncoder:
    engine_id = f'{MODEL_NAME}@e8f8c21/onnx-qint8'

    def __init__(self, home=None, max_tokens=128):
        home = home or default_home()
        if not available(home):
            raise RuntimeError(INSTALL_HINT)
        import numpy as np
        import onnxruntime as ort
        from tokenizers import Tokenizer
        self.np = np
        self.tok = Tokenizer.from_file(os.path.join(home, 'tokenizer.json'))
        self.tok.enable_truncation(max_tokens)
        self.tok.enable_padding()
        opts = ort.SessionOptions()
        opts.log_severity_level = 3
        self.sess = ort.InferenceSession(os.path.join(home, MODEL_FILE), opts, providers=['CPUExecutionProvider'])
        self.inputs = {i.name for i in self.sess.get_inputs()}
        self._cache = {}

    def encode(self, texts):
        """L2-normalised embeddings (numpy array, one row per text). Results are cached per text."""
        np = self.np
        todo = [t for t in dict.fromkeys(texts) if t not in self._cache]
        for i in range(0, len(todo), 32):
            batch = todo[i:i + 32]
            enc = self.tok.encode_batch(batch)
            ids = np.array([e.ids for e in enc], dtype=np.int64)
            mask = np.array([e.attention_mask for e in enc], dtype=np.int64)
            feed = {'input_ids': ids, 'attention_mask': mask}
            if 'token_type_ids' in self.inputs:
                feed['token_type_ids'] = np.zeros_like(ids)
            out = self.sess.run(None, feed)[0]                       # (batch, tokens, 384)
            m = mask[:, :, None].astype(out.dtype)
            vec = (out * m).sum(1) / np.clip(m.sum(1), 1e-9, None)     # mean pooling
            vec /= np.clip(np.linalg.norm(vec, axis=1, keepdims=True), 1e-12, None)
            for t, v in zip(batch, vec):
                self._cache[t] = v
        return np.stack([self._cache[t] for t in texts]) if texts else np.zeros((0, 384))

    def similarity(self, a, b):
        """Cosine similarity of two texts."""
        va, vb = self.encode([a, b])
        return float(va @ vb)
