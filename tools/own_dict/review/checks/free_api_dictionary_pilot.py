"""Manual, bounded dictionary draft pilot. No production DB writes or paid fallback."""
import argparse
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[4]
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

def choose_gemini_model(key):
    """Discover an available text generation model; never assume an old model ID exists."""
    preferred = os.environ.get("GEMINI_DICTIONARY_MODEL", "").strip()
    req = urllib.request.Request(
        "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100",
        headers={"x-goog-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as exc:
        raise RuntimeError("Gemini model discovery HTTP " + str(exc.code)) from None
    models = [m["name"].split("/")[-1] for m in data.get("models", [])
              if "generateContent" in m.get("supportedGenerationMethods", [])]
    candidates = ([preferred] if preferred else []) + [
        "gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-3.6-flash"]
    for name in candidates:
        if name and name in models:
            print("Gemini model selected: " + name)
            return name
    raise RuntimeError("No compatible Gemini model listed; available: " +
                       ", ".join(models[:12]))


def generate(word, provider, gemini_model=None):
    prompt = "English headword: " + word + "\n" + SYSTEM
    if provider == "gemini":
        key = os.environ.get("GEMINI_API_KEY_FOR_DICTIONARY", "")
        if not key:
            raise RuntimeError("Missing Gemini secret")
        model = gemini_model or choose_gemini_model(key)
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
    if not (1 <= args.count <= 26) or args.offset < 0:
        ap.error("Pilot limited to 1-26 words per run")
    words = json.loads(SOURCE.read_text(encoding="utf-8")) if SOURCE.exists() else ["toad","trader","trainee","troy","tweet","twist","tyrant","unapproachable","unpack","aerial","affluent","afterlife","airliner","alchemist","ale","alexandria","alleviate","chink","tourniquet","tout","toxicity","trachea","tracheitis","tracker","traduce","tragacanth"]
    selected = words[args.offset:args.offset + args.count]
    if not selected:
        ap.error("Offset beyond missing words")
    OUT.mkdir(parents=True, exist_ok=True)
    success, errors = [], []
    prior = pathlib.Path(os.environ.get("PILOT_PREVIOUS_DRAFTS", "/nonexistent"))
    if prior.is_file():
        for line in prior.read_text(encoding="utf-8").splitlines():
            try:
                record = json.loads(line)
                if record.get("w") in selected and record.get("senses"):
                    success.append(record)
            except (ValueError, TypeError):
                continue
    already = {row["w"] for row in success}
    print("Existing draft words reused: " + str(len(already)))
    gemini_model = None
    if args.provider == "gemini":
        key = os.environ.get("GEMINI_API_KEY_FOR_DICTIONARY", "")
        if not key:
            ap.error("Missing Gemini secret")
        gemini_model = choose_gemini_model(key)
    for word in selected:
        if word in already:
            continue
        try:
            for attempt in range(3):
                try:
                    draft = generate(word, args.provider, gemini_model)
                    break
                except RuntimeError as transient:
                    if "HTTP 503" not in str(transient) or attempt == 2:
                        raise
                    time.sleep(2 * (attempt + 1))
            success.append(draft)
            print(word + ": draft generated")
        except Exception as exc:
            errors.append({"w": word, "error": str(exc)[:120]})
            print(word + ": failed (" + type(exc).__name__ + ": " + str(exc)[:120] + ")")
            if any("HTTP " + str(code) in str(exc) for code in (400, 401, 402, 403, 404, 429)):
                print("Provider configuration, access, or quota error; stopping immediately.")
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
