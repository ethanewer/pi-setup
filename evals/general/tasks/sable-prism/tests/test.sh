#!/bin/bash
# Verifier for sable-prism: installs nothing, EXECUTES the deliverable driver
# (/app/run_eval.sh) with the deliverable config (/app/task_cfg.json) on the
# visible fixture and on every hidden case, and recomputes every accuracy
# independently from the shipped lexicon model + each dataset's codebook.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, re, subprocess, sys

CFG = "/app/task_cfg.json"
DRIVER = "/app/run_eval.sh"
BASELINE = "/app/results/tone_triage/baseline.json"
MODEL = "/app/model/lexicon.json"
OUT = "/tmp/sable_prism_verify_out.json"
WINDOW = 0.02

failures = []

# ---------- independent recomputation of the documented scoring rules ----------
try:
    model = json.load(open(MODEL))
except Exception as exc:
    print("cannot load model: %r" % (exc,))
    sys.exit(1)
CLASSES = model["classes"]
BIAS = [float(b) for b in model["bias"]]
WEIGHTS = model["weights"]
TOKEN_RE = re.compile(r"[a-z0-9']+")


def predict(text):
    toks = TOKEN_RE.findall(str(text).lower())
    scores = list(BIAS)
    for t in toks:
        w = WEIGHTS.get(t)
        if w:
            for k in range(len(CLASSES)):
                scores[k] += float(w[k])
    best = 0
    for k in range(1, len(CLASSES)):
        if scores[k] > scores[best]:
            best = k
    return CLASSES[best]


def recompute(data_path, gold_path):
    docs = []
    with open(data_path) as fh:
        for line in fh:
            if line.strip():
                docs.append(json.loads(line))
    gold_raw = json.load(open(gold_path))
    codebook = gold_raw["codebook"]
    labels = gold_raw["labels"]
    scored, skipped = [], []
    for d in docs:
        did = str(d.get("id"))
        code = labels.get(did)
        if not isinstance(code, int) or isinstance(code, bool) or str(code) not in codebook:
            skipped.append({"id": did, "reason": "invalid-label"})
            continue
        gold = codebook[str(code)]
        pred = predict(d.get("text", ""))
        scored.append({"id": did, "pred": pred, "gold": gold, "correct": pred == gold})
    n = len(scored)
    correct = sum(1 for s in scored if s["correct"])
    acc = (correct / n) if n else 0.0
    return {"accuracy": acc, "n": n, "correct": correct,
            "skipped": skipped}


def norm_result(obj):
    """Structural check + normalized (accuracy, n, correct, skipped) tuple."""
    if not isinstance(obj, dict):
        raise ValueError("result is not an object")
    for key in ("task", "metric", "accuracy", "n", "correct", "scored", "skipped"):
        if key not in obj:
            raise ValueError("result missing key %r" % key)
    if obj["task"] != "tone_triage":
        raise ValueError("wrong task name %r" % obj["task"])
    n = int(obj["n"])
    scored = obj["scored"]
    if not isinstance(scored, list) or len(scored) != n:
        raise ValueError("scored length != n")
    skipped = sorted((str(s["id"]), str(s["reason"])) for s in obj["skipped"])
    return (float(obj["accuracy"]), n, int(obj["correct"]), skipped)


def check_case(out_path, data_path, gold_path, expected_path, label):
    try:
        want = recompute(data_path, gold_path)
    except Exception as exc:
        failures.append("%s: verifier recompute failed: %r" % (label, exc))
        return
    # cross-check the shipped static expected (authoring guard)
    try:
        stat = json.load(open(expected_path))
        if (abs(stat["accuracy"] - want["accuracy"]) > 1e-9
                or stat["n"] != want["n"] or stat["correct"] != want["correct"]):
            failures.append("%s: static expected.json disagrees with recompute" % label)
    except Exception as exc:
        failures.append("%s: unreadable expected.json: %r" % (label, exc))
        return
    if os.path.exists(out_path):
        os.remove(out_path)
    r = subprocess.run(["bash", DRIVER, "eval", CFG, data_path, gold_path, out_path],
                       capture_output=True, text=True, timeout=120)
    try:
        got = norm_result(json.load(open(out_path)))
    except Exception as exc:
        failures.append("%s: driver output unusable: %r" % (label, exc))
        return
    acc, n, correct, skipped = got
    if abs(acc - want["accuracy"]) > WINDOW:
        failures.append("%s: accuracy %.4f outside window of %.4f (wrong choice order/gold mapping?)"
                        % (label, acc, want["accuracy"]))
    if n != want["n"]:
        failures.append("%s: n=%d expected %d" % (label, n, want["n"]))
    if correct != want["correct"]:
        failures.append("%s: correct=%d expected %d" % (label, correct, want["correct"]))
    if sorted(skipped) != sorted((s["id"], s["reason"]) for s in want["skipped"]):
        failures.append("%s: skipped set mismatch" % label)


# ---------- 0. the harness package must actually be installed ----------
r = subprocess.run([sys.executable, "-c", "import prismval"],
                   capture_output=True, text=True)
if r.returncode != 0:
    failures.append("harness package prismval is not importable (not installed)")

# ---------- 1. the task config deliverable ----------
cfg = None
if not os.path.isfile(CFG):
    failures.append("missing %s" % CFG)
else:
    try:
        cfg = json.load(open(CFG))
        if cfg.get("task_name") != "tone_triage":
            failures.append("task_cfg.json: task_name must be tone_triage")
        choices = cfg.get("choices")
        if (not isinstance(choices, list) or sorted(choices) !=
                sorted(["negative", "neutral", "positive"])):
            failures.append("task_cfg.json: choices must contain exactly the three class names")
        gm = cfg.get("gold_map")
        if not isinstance(gm, dict) or set(map(str, gm)) != {"0", "1", "2"}:
            failures.append("task_cfg.json: gold_map must map codes '0','1','2'")
        else:
            for k, v in gm.items():
                if not isinstance(v, int) or isinstance(v, bool) or not (0 <= v < len(choices or [])):
                    failures.append("task_cfg.json: gold_map['%s'] is not a valid choice index" % k)
    except Exception as exc:
        failures.append("task_cfg.json unreadable: %r" % exc)

# ---------- 2. run the driver on the visible fixture ----------
if os.path.isfile(DRIVER):
    if os.path.exists(OUT):
        os.remove(OUT)
    r = subprocess.run(["bash", DRIVER], capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        failures.append("run_eval.sh visible run failed: %s" % r.stderr[-300:])
    if not os.path.isfile(BASELINE):
        failures.append("driver did not produce %s" % BASELINE)
    else:
        try:
            got = norm_result(json.load(open(BASELINE)))
            want = recompute("/app/data/reviews.jsonl", "/app/data/gold.json")
            if abs(got[0] - want["accuracy"]) > WINDOW or got[1] != want["n"] or got[2] != want["correct"]:
                failures.append("baseline.json does not match recomputed visible accuracy")
        except Exception as exc:
            failures.append("baseline.json unusable: %r" % exc)
        check_case(OUT, "/app/data/reviews.jsonl", "/app/data/gold.json",
                   "/tests/expected.json", "visible-rerun")
else:
    failures.append("missing %s" % DRIVER)

# ---------- 3. hidden cases ----------
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        data = os.path.join(base, "reviews.jsonl")
        gold = os.path.join(base, "gold.json")
        exp = os.path.join(base, "expected.json")
        if not all(os.path.isfile(p) for p in (data, gold, exp)):
            failures.append("hidden '%s' malformed" % c)
            continue
        check_case(OUT, data, gold, exp, "hidden:%s" % c)
else:
    failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
