#!/bin/bash
# sable-vellum verifier: checks the delivered task wiring, re-runs the agent's
# driver (/app/run_cards.py) over HTTP on hidden corpora, and recomputes every
# metric independently from the shipped model. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -uo pipefail
PY="$(command -v python3)"
reward=1
mkdir -p /logs/verifier
SRV=""
trap 'if [ -n "${SRV:-}" ]; then kill "$SRV" 2>/dev/null || true; fi; echo "${reward:-0}" > /logs/verifier/reward.txt' EXIT

if [ ! -f /app/task_vellum.yaml ]; then echo "VERIFIER: missing /app/task_vellum.yaml" >&2; reward=0; fi
if [ ! -f /app/run_cards.py ]; then echo "VERIFIER: missing /app/run_cards.py" >&2; reward=0; fi
if [ ! -f /app/results/card_sortis/visible.json ]; then echo "VERIFIER: missing /app/results/card_sortis/visible.json" >&2; reward=0; fi

# 0) Task config contract + visible deliverable, checked in one python pass.
if ! "$PY" - <<'PY'
import json, re, sys, yaml

fail = []

# --- task_vellum.yaml contract ---
try:
    cfg = yaml.safe_load(open("/app/task_vellum.yaml"))
except Exception as e:
    print("yaml unreadable:", e); sys.exit(2)
if not isinstance(cfg, dict):
    fail.append("task_vellum.yaml is not a mapping")
else:
    if cfg.get("task_name") != "card_sortis":
        fail.append("task_name must be card_sortis")
    if cfg.get("n_classes") != 3:
        fail.append("n_classes must be 3")
    if list(cfg.get("choices") or []) != ["herb", "tree", "moss"]:
        fail.append("choices must be [herb, tree, moss] in that order")
    if cfg.get("model_path") != "/app/model/vex_nano.json":
        fail.append("model_path wrong")
    if cfg.get("query_column") != "excerpt" or cfg.get("title_column") != "title":
        fail.append("column selection wrong")
    if not cfg.get("doc_to_choice"):
        fail.append("doc_to_choice missing")
    tmpl = str(cfg.get("prompt_template") or "")
    for needle in ["{title}", "{excerpt}", "herb", "tree", "moss"]:
        if needle not in tmpl:
            fail.append(f"prompt_template missing {needle!r}")

# --- independent recompute of vex-nano classification ---
TOKEN_RE = re.compile(r"[a-z0-9]+")
model = json.load(open("/app/model/vex_nano.json"))["tokens"]
CHOICES = ["herb", "tree", "moss"]  # the documented correct order


def recompute(docs_path, labels_path):
    docs = [json.loads(l) for l in open(docs_path) if l.strip()]
    labels = json.load(open(labels_path))
    scored, skipped = [], []
    correct = 0
    for d in docs:
        wid = d.get("id")
        lab = labels.get(wid)
        if not isinstance(lab, str) or lab not in CHOICES:
            skipped.append({"id": wid, "reason": "invalid-label"})
            continue
        gold = CHOICES.index(lab)
        text = f"{d.get('title', '')}\n{d.get('excerpt', '')}"
        scores = [0.0, 0.0, 0.0]
        for tok in TOKEN_RE.findall(text.lower()):
            vec = model.get(tok)
            if vec:
                for k in range(3):
                    scores[k] += float(vec[k])
        pred = 0
        for k in range(1, 3):
            if scores[k] > scores[pred]:
                pred = k
        ok = pred == gold
        correct += ok
        scored.append({"id": wid, "pred": pred, "gold": gold, "correct": ok})
    n = len(scored)
    return {"n": n, "correct": correct,
            "accuracy": (correct / n) if n else None,
            "scored": scored,
            "skipped_ids": sorted(s["id"] for s in skipped)}


def check(result_path, ref, label):
    try:
        got = json.load(open(result_path))
    except Exception as e:
        fail.append(f"{label}: unreadable result ({e})")
        return
    if got.get("n") != ref["n"] or got.get("correct") != ref["correct"]:
        fail.append(f"{label}: n/correct got ({got.get('n')},{got.get('correct')}) "
                    f"ref ({ref['n']},{ref['correct']})")
    acc = got.get("accuracy")
    if acc is None or ref["accuracy"] is None or abs(acc - ref["accuracy"]) > 1e-6:
        fail.append(f"{label}: accuracy got {acc} ref {ref['accuracy']}")
    if not (0.60 <= (acc if acc is not None else 0) <= 0.95):
        fail.append(f"{label}: accuracy {acc} outside the 0.60-0.95 window "
                    f"(choice order / gold mapping likely wrong)")
    ref_by = {r["id"]: r for r in ref["scored"]}
    for r in got.get("scored", []):
        rr = ref_by.get(r.get("id"))
        if rr and (r.get("pred") != rr["pred"] or r.get("gold") != rr["gold"]):
            fail.append(f"{label}: pred/gold mismatch on {r.get('id')}")
    got_skip = sorted(s.get("id") for s in got.get("skipped", []))
    if got_skip != ref["skipped_ids"]:
        fail.append(f"{label}: skipped set mismatch")

if fail:
    print("CONFIG/VISIBLE FAILURES:", *fail, sep="\n  ")
    sys.exit(2)

ref = recompute("/app/corpus/docs.jsonl", "/app/corpus/labels.json")
check("/app/results/card_sortis/visible.json", ref, "visible")
if fail:
    print("VISIBLE FAILURES:", *fail, sep="\n  ")
    sys.exit(2)
print("config + visible ok, accuracy", ref["accuracy"])
PY
then
  reward=0
fi

# 1) Hidden corpora: serve over HTTP, run the agent's driver, recompute.
if [ -d /tests/hidden ] && [ "$reward" = 1 ]; then
  PORT=8897
  python3 -m http.server "$PORT" --directory /tests/hidden >/dev/null 2>&1 &
  SRV=$!
  sleep 1
  if "$PY" - <<PY
import json, re, subprocess, sys

TOKEN_RE = re.compile(r"[a-z0-9]+")
model = json.load(open("/app/model/vex_nano.json"))["tokens"]
CHOICES = ["herb", "tree", "moss"]
BASE = "http://127.0.0.1:$PORT"
fail = []


def recompute(docs_path, labels_path):
    docs = [json.loads(l) for l in open(docs_path) if l.strip()]
    labels = json.load(open(labels_path))
    scored, skipped, correct = [], [], 0
    for d in docs:
        wid = d.get("id")
        lab = labels.get(wid)
        if not isinstance(lab, str) or lab not in CHOICES:
            skipped.append({"id": wid, "reason": "invalid-label"})
            continue
        gold = CHOICES.index(lab)
        text = f"{d.get('title', '')}\n{d.get('excerpt', '')}"
        scores = [0.0, 0.0, 0.0]
        for tok in TOKEN_RE.findall(text.lower()):
            vec = model.get(tok)
            if vec:
                for k in range(3):
                    scores[k] += float(vec[k])
        pred = 0
        for k in range(1, 3):
            if scores[k] > scores[pred]:
                pred = k
        ok = pred == gold
        correct += ok
        scored.append({"id": wid, "pred": pred, "gold": gold, "correct": ok})
    n = len(scored)
    return {"n": n, "correct": correct,
            "accuracy": (correct / n) if n else None, "scored": scored,
            "skipped_ids": sorted(s["id"] for s in skipped)}


for case in ["h1", "h2", "h3"]:
    out = f"/app/results/_verify_{case}.json"
    r = subprocess.run(
        [sys.executable, "/app/run_cards.py", "/app/task_vellum.yaml",
         f"{BASE}/{case}/docs.jsonl", f"{BASE}/{case}/labels.json", out],
        capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        fail.append(f"{case}: driver failed: {(r.stderr or r.stdout).strip()[-400:]}")
        continue
    ref = recompute(f"/tests/hidden/{case}/docs.jsonl",
                    f"/tests/hidden/{case}/labels.json")
    try:
        got = json.load(open(out))
    except Exception as e:
        fail.append(f"{case}: unreadable output ({e})")
        continue
    if got.get("n") != ref["n"] or got.get("correct") != ref["correct"]:
        fail.append(f"{case}: n/correct got ({got.get('n')},{got.get('correct')}) "
                    f"ref ({ref['n']},{ref['correct']})")
    acc = got.get("accuracy")
    if acc is None or ref["accuracy"] is None or abs(acc - ref["accuracy"]) > 1e-6:
        fail.append(f"{case}: accuracy got {acc} ref {ref['accuracy']}")
    ref_by = {x["id"]: x for x in ref["scored"]}
    for row in got.get("scored", []):
        rr = ref_by.get(row.get("id"))
        if rr and (row.get("pred") != rr["pred"] or row.get("gold") != rr["gold"]):
            fail.append(f"{case}: pred/gold mismatch on {row.get('id')}")
    got_skip = sorted(s.get("id") for s in got.get("skipped", []))
    if got_skip != ref["skipped_ids"]:
        fail.append(f"{case}: skipped set mismatch")
    else:
        print(f"  {case} ok accuracy={ref['accuracy']} n={ref['n']} "
              f"skipped={len(ref['skipped_ids'])}")

if fail:
    print("HIDDEN FAILURES:", *fail, sep="\n  ")
    sys.exit(2)
print("hidden cases ok")
PY
  then
    :
  else
    reward=0
  fi
fi

echo "sable-vellum reward=$reward"
