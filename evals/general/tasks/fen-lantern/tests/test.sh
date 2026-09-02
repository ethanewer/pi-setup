#!/bin/bash
# Verifier for fen-lantern: validates the delivered task wiring (choice order,
# gold mapping, prompt template), enforces the accuracy window, then EXECUTES
# the delivered runner (/app/run_task.py) on the visible fixture and on every
# hidden dataset under /tests/hidden, comparing against independently
# recomputed expected results. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, subprocess, sys

CFG = "/app/tasks/wetland_calls.yaml"
RUNNER = "/app/run_task.py"
BASE = "/app/results/wetland_calls/baseline.json"
CHOICES = ["bittern", "crake", "grebe", "warbler"]
WINDOW_LO, WINDOW_HI = 0.55, 1.00
failures = []

# --- 1. The task configuration must be wired exactly right. ---
try:
    import yaml
    with open(CFG) as fh:
        cfg = yaml.safe_load(fh)
    assert isinstance(cfg, dict), "config is not a mapping"
    assert cfg.get("task_name") == "wetland_calls", cfg.get("task_name")
    assert cfg.get("model_path") == "/app/model/fen_scout.json", cfg.get("model_path")
    assert list(cfg.get("choices") or []) == CHOICES, cfg.get("choices")
    dc = cfg.get("doc_to_choice")
    assert isinstance(dc, dict), "doc_to_choice missing"
    assert {str(k): int(v) for k, v in dc.items()} == {c: i for i, c in enumerate(CHOICES)}, dc
    tmpl = str(cfg.get("prompt_template") or "")
    assert "{note}" in tmpl, "prompt_template lacks {note}"
    assert all(s in tmpl for s in CHOICES), "prompt_template lacks species literals"
except Exception as e:
    failures.append("task config invalid or miswired: %r" % (e,))

# --- 2. The runner must drive the installed harness package. ---
if not os.path.isfile(RUNNER):
    failures.append("missing /app/run_task.py")
else:
    try:
        src = open(RUNNER).read()
        if "fen_eval" not in src:
            failures.append("/app/run_task.py does not use the installed fen_eval package")
    except Exception as e:
        failures.append("run_task.py unreadable: %r" % (e,))


def norm(obj):
    """Canonical form of a harness result for exact comparison."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"task", "model", "run", "metric", "accuracy",
                               "n", "correct", "scored", "skipped"}, set(obj.keys())
    assert obj["task"] == "wetland_calls" and obj["metric"] == "accuracy"
    assert obj["model"] == "fen-scout-0.4"
    assert isinstance(obj["n"], int) and isinstance(obj["correct"], int)
    assert abs(float(obj["accuracy"]) - (obj["correct"] / obj["n"] if obj["n"] else 0.0)) < 1e-9
    scored = sorted(({"id": s["id"], "pred": int(s["pred"]),
                      "gold": int(s["gold"]), "correct": bool(s["correct"])}
                     for s in obj["scored"]), key=lambda s: s["id"])
    skipped = sorted(({"id": s["id"], "reason": str(s["reason"])}
                      for s in obj["skipped"]), key=lambda s: s["id"])
    return (obj["n"], obj["correct"], round(float(obj["accuracy"]), 9), scored, skipped)


def run_case(docs, labels, expected_path, tag):
    out = "/tmp/fen_lantern_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, RUNNER, CFG, docs, labels, out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as e:
        failures.append("%s: runner crashed: %r" % (tag, e))
        return
    if r.returncode != 0 or not os.path.exists(out):
        failures.append("%s: runner failed (rc=%s)" % (tag, r.returncode))
        return
    try:
        got = norm(json.load(open(out)))
        want = norm(json.load(open(expected_path)))
    except Exception as e:
        failures.append("%s: unreadable/invalid result: %r" % (tag, e))
        return
    if got != want:
        failures.append("%s: result does not match expected" % tag)
        return
    acc = got[2]
    if not (WINDOW_LO <= acc <= WINDOW_HI):
        failures.append("%s: accuracy %.4f outside window [%.2f, %.2f]"
                        % (tag, acc, WINDOW_LO, WINDOW_HI))


if not failures:
    # --- 3. Visible case: execute the delivered runner live. ---
    run_case("/app/data/wetland_docs.jsonl", "/app/data/wetland_labels.json",
             "/tests/expected.json", "visible")
    # visible-case deliverable file must match too
    try:
        if os.path.isfile(BASE):
            if norm(json.load(open(BASE))) != norm(json.load(open("/tests/expected.json"))):
                failures.append("/app/results/wetland_calls/baseline.json mismatch")
        else:
            failures.append("missing /app/results/wetland_calls/baseline.json")
    except Exception as e:
        failures.append("baseline.json unreadable: %r" % (e,))

    # --- 4. Hidden re-runs on fresh datasets. ---
    for h in sorted(os.listdir("/tests/hidden")):
        base = os.path.join("/tests/hidden", h)
        docs = os.path.join(base, "docs.jsonl")
        labels = os.path.join(base, "labels.json")
        exp = os.path.join(base, "expected.json")
        if not all(os.path.isfile(p) for p in (docs, labels, exp)):
            failures.append("hidden '%s' malformed" % h)
            continue
        run_case(docs, labels, exp, "hidden/%s" % h)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
echo "fen-lantern reward=$reward"
