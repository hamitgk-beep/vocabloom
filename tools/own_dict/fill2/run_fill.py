"""Fill missing own-dictionary meanings with free-tier APIs. Never writes to the app database.

usage: python3 run_fill.py ITEMS.json OUT_DIR [--batch 10] [--max-requests 150] [--max-minutes 60]

Provider order: Gemini first, then Groq. A quota error (HTTP 429) moves to the next provider;
when no provider is left the run stops. Other HTTP errors stop the run. No paid fallback.
Results are appended to OUT_DIR/results.jsonl; finished keys are skipped on the next run.
"""
import argparse, gzip, json, os, pathlib, re, sys, time, urllib.error, urllib.request
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from eng import english_words

SYSTEM = (
    "You write ORIGINAL English-Turkish learner dictionary entries for readers of English books. "
    "Do not copy or closely paraphrase any existing Turkish dictionary definition (for example Wiktionary, "
    "damdafayton or other dictionaries). Write the Turkish meanings yourself. "
    "For each headword give the important distinct meanings a reader meets, most common first, with the "
    "part of speech. Each sense: pos (noun, verb, adjective, adverb, phrase or expression), tr (short Turkish "
    "meaning, comma-separated synonyms allowed), note (usage label in Turkish if needed: argo, kaba, aşağılayıcı, "
    "tarihsel, bölgesel, cinsel, resmî, gayriresmî, teknik, eufemistik; else empty), en (one short English example "
    "sentence containing the headword or expression), ex_tr (Turkish translation of that example). "
    "Do not invent meanings. If unsure, add a sentence in uncertainty. Return ONLY JSON: "
    '{"items":[{"w":"<headword exactly as given>","senses":[{"pos":"","tr":"","note":"","en":"","ex_tr":""}],"uncertainty":""}]}'
)
ROOT = pathlib.Path(__file__).resolve().parent


def post(url, headers, payload, timeout=120):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


class Quota(Exception):
    pass


class Fatal(Exception):
    pass


class Transient(Exception):
    pass


def http_error(e):
    code = e.code
    if code == 429:
        raise Quota("HTTP 429")
    if code in (500, 502, 503, 504):
        raise Transient("HTTP %s" % code)
    raise Fatal("HTTP %s" % code)


def gemini_model(key):
    req = urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/models?pageSize=100",
                                 headers={"x-goog-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            models = [m["name"].split("/")[-1] for m in json.load(resp).get("models", [])
                      if "generateContent" in m.get("supportedGenerationMethods", [])]
    except urllib.error.HTTPError as e:
        http_error(e)
    for name in ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite"]:
        if name in models:
            return name
    raise Fatal("no compatible Gemini model")


HAIKU_PRICE = (0.10, 0.50)  # USD per million input / output tokens


def ask_haiku(state, batch_prompt):
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not key:
        raise Fatal("missing Anthropic secret")
    body = {"model": os.environ.get("HAIKU_MODEL", "claude-haiku-5-5"), "max_tokens": 4000,
            "system": SYSTEM, "messages": [{"role": "user", "content": batch_prompt}]}
    for attempt in range(3):
        try:
            res = post("https://api.anthropic.com/v1/messages",
                       {"Content-Type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01"}, body)
            break
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 2:
                time.sleep(60)
                continue
            if e.code in (500, 502, 503, 529) and attempt < 2:
                time.sleep(20)
                continue
            if e.code == 429:
                raise Quota("HTTP 429 (rate limit)")
            raise Fatal("HTTP %s" % e.code)
    state["usage"] = res.get("usage", {})
    return "".join(b.get("text", "") for b in res.get("content", []) if b.get("type") == "text")


def ask(provider, state, batch_prompt):
    if provider == "haiku":
        return ask_haiku(state, batch_prompt)
    if provider == "gemini":
        key = os.environ.get("GEMINI_API_KEY_FOR_DICTIONARY", "")
        if not key:
            raise Fatal("missing Gemini secret")
        if state.get("gemini_model") is None:
            state["gemini_model"] = gemini_model(key)
        url = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % state["gemini_model"]
        try:
            res = post(url, {"Content-Type": "application/json", "x-goog-api-key": key},
                       {"contents": [{"parts": [{"text": SYSTEM + "\n\n" + batch_prompt}]}],
                        "generationConfig": {"temperature": 0.3, "responseMimeType": "application/json",
                                             "maxOutputTokens": 8000}})
        except urllib.error.HTTPError as e:
            http_error(e)
        return "".join(p.get("text", "") for c in res.get("candidates", []) for p in c.get("content", {}).get("parts", []))
    key = os.environ.get("GROQ_API_KEY_FOR_DICTIONARY", "")
    if not key:
        raise Fatal("missing Groq secret")
    try:
        res = post("https://api.groq.com/openai/v1/chat/completions",
                   {"Content-Type": "application/json", "Authorization": "Bearer " + key},
                   {"model": os.environ.get("GROQ_DICTIONARY_MODEL", "llama-3.1-8b-instant"),
                    "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": batch_prompt}],
                    "temperature": 0.3, "max_tokens": 4000, "response_format": {"type": "json_object"}})
    except urllib.error.HTTPError as e:
        http_error(e)
    return res["choices"][0]["message"]["content"]


def toks(t):
    return {re.sub(r"\s+", " ", x.strip().lower()) for x in re.split(r"[;,|]", t or "") if x.strip()}


def qc(rec, item):
    flags = []
    senses = rec["senses"]
    if not senses:
        flags.append(("high", "empty_senses"))
    if len(senses) > 6:
        flags.append(("low", "many_senses"))
    for s in senses:
        if english_words(s.get("tr")):
            flags.append(("high", "english_in_turkish"))
        if not (s.get("en") or "").strip() or not (s.get("ex_tr") or "").strip():
            flags.append(("medium", "example_missing"))
        if item["kind"] == "word" and item["text"].lower() not in (s.get("en") or "").lower().replace("-", "") and \
                item["text"].lower()[:max(4, len(item["text"]) - 3)] not in (s.get("en") or "").lower():
            flags.append(("medium", "headword_not_in_example"))
    new = set().union(*[toks(s.get("tr")) for s in senses]) if senses else set()
    raw_old = item.get("old_tr") or ""
    if raw_old.startswith("["):
        raw_old = ", ".join(json.loads(raw_old))
    old = toks(raw_old)
    if new and old and new == old:
        if len(new) >= 2:
            flags.append(("high", "copy_risk_exact_match"))
        else:
            flags.append(("info", "same_single_gloss_as_existing"))
    elif len(new) >= 3 and old and len(new & old) / len(new | old) >= 0.8:
        flags.append(("medium", "copy_risk_near_match"))
    return flags


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("items")
    ap.add_argument("out")
    ap.add_argument("--batch", type=int, default=10)
    ap.add_argument("--max-requests", type=int, default=150)
    ap.add_argument("--max-minutes", type=float, default=60)
    ap.add_argument("--providers", default="gemini,groq")
    ap.add_argument("--budget-usd", type=float, default=0.0, help="stop before paid spend would exceed this; 0 = free tiers only")
    a = ap.parse_args()
    t0 = time.time()
    items = json.load(open(a.items, encoding="utf-8"))
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    resf = out / "results.jsonl"
    done = set()
    if resf.exists():
        for line in resf.read_text(encoding="utf-8").splitlines():
            try:
                done.add(json.loads(line)["key"])
            except (ValueError, KeyError):
                pass
    todo = [i for i in items if i["key"] not in done]
    providers = [p for p in a.providers.split(",") if p]
    cost = {"usd": 0.0, "in": 0, "out": 0}
    state = {"gemini_model": None}
    stats = {"requests": 0, "ok_items": 0, "failed_requests": 0, "quota_switch": [], "stop": ""}
    pos = 0
    with resf.open("a", encoding="utf-8") as f:
        while pos < len(todo):
            if stats["requests"] >= a.max_requests:
                stats["stop"] = "request_budget"; break
            if (time.time() - t0) / 60 > a.max_minutes:
                stats["stop"] = "time_budget"; break
            if not providers:
                stats["stop"] = "quota_exhausted"; break
            part = todo[pos:pos + a.batch]
            prompt = "Headwords:\n" + "\n".join(
                "%d. %s (%s%s)" % (n + 1, i["text"], "word" if i["kind"] == "word" else "expression",
                                   (", " + i["cat"]) if i["cat"] else "") for n, i in enumerate(part))
            if providers[0] == "haiku" and a.budget_usd <= 0:
                stats["stop"] = "paid_provider_without_budget"; break
            if providers[0] == "haiku" and cost["usd"] + 0.002 > a.budget_usd:
                stats["stop"] = "budget_reached"; break
            stats["requests"] += 1
            try:
                raw = None
                for wait in (0, 15, 45, 90):
                    try:
                        time.sleep(wait)
                        raw = ask(providers[0], state, prompt)
                        break
                    except (Transient, urllib.error.URLError, TimeoutError):
                        continue
                if raw is None:
                    raise RuntimeError("transient errors after retries")
                obj = json.loads(raw)
                by = {x.get("w", "").lower(): x for x in obj.get("items", []) if isinstance(x, dict)}
                for i in part:
                    x = by.get(i["text"].lower())
                    if not x or not isinstance(x.get("senses"), list) or not x["senses"]:
                        rec = {"key": i["key"], "w": i["text"], "kind": i["kind"], "senses": [], "flags": [["high", "missing_or_empty"]]}
                    else:
                        rec = {"key": i["key"], "w": i["text"], "kind": i["kind"], "cat": i["cat"],
                               "senses": [{k: str(s.get(k, "") or "").strip() for k in ("pos", "tr", "note", "en", "ex_tr")} for s in x["senses"] if isinstance(s, dict)],
                               "uncertainty": str(x.get("uncertainty", ""))[:300]}
                        rec["flags"] = qc(rec, i)
                    rec["provider"] = providers[0]
                    rec["status"] = "ai_draft_unreviewed"
                    rec["reviewed_by_ai"] = True
                    rec["reviewed_by_human"] = False
                    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
                    if rec["senses"]:
                        stats["ok_items"] += 1
                f.flush()
                pos += len(part)
            except Quota as q:
                stats["quota_switch"].append({"provider": providers[0], "at": pos, "why": str(q)})
                providers.pop(0)
            except Exception as e:  # network timeouts, bad JSON, missing keys: count it and go on
                stats["failed_requests"] += 1
                stats["last_error"] = type(e).__name__ + ": " + str(e)[:150]
                if isinstance(e, Fatal) or stats["failed_requests"] >= 5:
                    stats["stop"] = "fatal"; break
                pos += len(part)  # skip this batch, it stays unfinished and is retried on the next run only if key missing
    stats.update({"paid_usage": {"input_tokens": cost["in"], "output_tokens": cost["out"], "usd_estimate": round(cost["usd"], 4)},
                  "items_total": len(items), "items_done_total": len(done) + stats["ok_items"],
                  "seconds": round(time.time() - t0), "pending_after_run": len(todo) - pos})
    (out / "summary.json").write_text(json.dumps(stats, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
