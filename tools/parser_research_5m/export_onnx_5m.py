"""Task 5M (research): export a trained neural MWE tagger to ONNX, quantize it to int8, check that the int8 model
gives the same B/I/O labels as PyTorch, and time it on one CPU thread (a rough stand-in for a phone core).

  python export_onnx_5m.py MODEL_DIR OUT_DIR GOLD.jsonl
"""
import json
import os
import sys
import time

import numpy as np
import onnxruntime as ort
import torch
from onnxruntime.quantization import QuantType, quantize_dynamic
from transformers import AutoModelForTokenClassification, AutoTokenizer

src, out, gold = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
tok = AutoTokenizer.from_pretrained(src)
model = AutoModelForTokenClassification.from_pretrained(src).eval()
ex = tok(["Blacky", "was", "on", "hand", "."], is_split_into_words=True, return_tensors="pt")
fp32 = os.path.join(out, "model.onnx")
torch.onnx.export(model, (ex["input_ids"], ex["attention_mask"]), fp32, input_names=["input_ids", "attention_mask"],
                  output_names=["logits"], dynamic_axes={"input_ids": {0: "b", 1: "t"}, "attention_mask": {0: "b", 1: "t"}, "logits": {0: "b", 1: "t"}},
                  opset_version=17, dynamo=False)
int8 = os.path.join(out, "model.int8.onnx")
quantize_dynamic(fp32, int8, weight_type=QuantType.QInt8)
so = ort.SessionOptions()
so.intra_op_num_threads = 1
sess = ort.InferenceSession(int8, so, providers=["CPUExecutionProvider"])
rows = [json.loads(l) for l in open(gold, encoding="utf-8")][:300]
same = total = 0
ms = []
for r in rows:
    if not r["words"]:
        continue
    enc = tok(r["words"], is_split_into_words=True, truncation=True, max_length=160, return_tensors="pt")
    with torch.no_grad():
        a = model(**enc).logits[0].argmax(-1).numpy()
    t0 = time.perf_counter()
    b = sess.run(None, {"input_ids": enc["input_ids"].numpy(), "attention_mask": enc["attention_mask"].numpy()})[0][0].argmax(-1)
    ms.append(1000 * (time.perf_counter() - t0))
    same += int((a == b).sum())
    total += len(a)
print(json.dumps({"fp32_MB": round(sum(os.path.getsize(os.path.join(out, f)) for f in os.listdir(out) if not f.startswith("model.int8")) / 1e6, 1), "int8_MB": round(os.path.getsize(int8) / 1e6, 1),
                  "int8_label_agreement": round(same / total, 4), "int8_ms_per_sentence_1thread_median": round(float(np.median(ms)), 2),
                  "sentences": len(ms)}))
