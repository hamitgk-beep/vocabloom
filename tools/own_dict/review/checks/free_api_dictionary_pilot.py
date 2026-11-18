"""Manual, bounded dictionary draft pilot. No production DB writes or paid fallback."""
import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = ROOT / "tools/own_dict/gap/missing_words.json"
OUT = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "vocabloom_dictionary_pilot"
SYSTEM = (
    "Write ORIGINAL English-Turkish learner dictionary meanings for English book readers. "
    "Do not copy Turkish definitions from any dictionary. Include important distinct meanings, "
    "part of speech, short original example and Turkish example translation. "
    "Mark uncertainty; do not invent meanings. Return ONLY a JSON object with keys "
    "word, senses (array of objects with pos,tr,note,en,ex_tr), uncertainty (string). "
    "Include sensitive/archaic meanings when important and label them in note."
)

def call(url, key, payload):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json",
        "Authorization": "Bearer " + key} if "groq.com" in url else {"Content-Type": "application/json", "x-goog-api-key": key}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        # Never print a request body, key, or provider response.
        raise RuntimeError("Provider HTTP " + str(e.code)) from None

def generate(word, provider):
    prompt = "English headword: " + word + "\n" + SYSTEM
    if provider == "gemini":
        key = os.environ.get("GEMINI_API_KEY_FOR_DICTIONARY", "")
        if not key:
            raise RuntimeError("Missing Gemini secret")
        model = os.environ.get("GEMINI_DICTIONARY_MODEL", "gemini-2.5-flash-lite")
        result = call("https://generativelanguage.googleapis.com/v1beta/models/" + model + ":generateContent", key,
            {"contents": [{"parts": [{"text": prompt}]}],
             "generationConfig": {"temperature": 0.2, "responseMimeType": "application/json", "maxOutputTokens": 2000}})
        raw = "".join(p.get("text", "") for c in result.get("candidates", []) for p in c.get("content", {}).get("parts", []))
    else:
        key = os.environ.get("GROQ_API_KEY_FOR_DICTIONARY", "")
        if not key:
            raise RuntimeError("Missing Groq secret")
        model = os.environ.get("GROQ_DICTIONARY_MODEL", "llama-3.1-8b-instant")
        result = call("https://api.groq.com/openai/v1/chat/completions", key,
            {"model": model, "messages": [{"role": "system", "content": SYSTEM},
              {"role": "user", "content": "English headword: " + word}],
             "temperature": 0.2, "max_tokens": 1800, "response_format": {"type": "json_object"}})
        raw = result["choices"][0]["message"]["content"]
    obj = json.loads(raw)
    if obj.get("word", word).casefold() != word.casefold() or not isinstance(obj.get("senses"), list) or not obj["senses"]:
        raise ValueError("Invalid or empty result")
    for s in obj["senses"]:
        if not isinstance(s, dict) or not isinstance(s.get("tr"), str) or not s["tr"].strip() or not isinstance(s.get("pos"), str):
            raise ValueError("Invalid sense")
    return {"w": word, "kind": "word", "senses": obj["senses"], "uncertainty": obj.get("uncertainty", ""),
            "status": "draft_ai_unreviewed", "reviewed": False, "provider": provider, "source": "original_model_draft"}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=10)
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--provider", choices=["gemini", "groq"], default="gemini")
    args = ap.parse_args()
    if not (1 <= args.count <= 10) or args.offset < 0:
        ap.error("Pilot limited to 1-10 words per manual run")
    words = json.loads(SOURCE.read_text(encoding="utf-8"))
    selected = words[args.offset:args.offset + args.count]
    if not selected:
        ap.error("Offset beyond missing words")
    OUT.mkdir(parents=True, exist_ok=True)
    success, errors = [], []
    for word in selected:
        try:
            success.append(generate(word, args.provider))
            print(word + ": draft generated")
        except Exception as exc:
            errors.append({"w": word, "error": str(exc)[:120]})
            print(word + ": failed (" + type(exc).__name__ + ")")
            if "HTTP 429" in str(exc) or "HTTP 402" in str(exc):
                print("Quota/billing limit encountered; stopping immediately.")
                break
    with (OUT / "drafts.jsonl").open("w", encoding="utf-8") as f:
        for row in success:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    (OUT / "failures.json").write_text(json.dumps(errors, ensure_ascii=False, indent=2), encoding="utf-8")
    (OUT / "summary.json").write_text(json.dumps({"requested": len(selected), "generated_drafts": len(success),
        "failures": len(errors), "provider": args.provider, "reviewed_by_human": 0,
        "production_db_changed": False}, indent=2), encoding="utf-8")
    print("Drafts: " + str(len(success)) + "; failures: " + str(len(errors)))
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
