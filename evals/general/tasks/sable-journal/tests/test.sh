#!/bin/bash
#
# sable-journal verifier.
# Executes the deliverables: (1) reads /app/diagnosis.md and checks it names
# the exact read/await/write lines of the pristine original and a valid fix
# class; (2) repairs-check: runs the pristine load generator, UNMODIFIED,
# against the fixed /app/svc/wordcount_service.py under the documented load
# (40 workers x 6 requests, seed 2718) and independently recomputes the true
# counts from the corpus + deterministic schedule rule; (3) bug-repro: runs
# the pristine ORIGINAL service under that same load and requires it to still
# corrupt; (4) hidden cases: 3 hidden corpus/load configs with different
# worker counts, expected counts recomputed independently for each.
# Also hash-checks the fixtures (/opt/pristine, /app/data/corpus.txt,
# /app/svc/loadgen.py) so the load cannot be weakened or short-circuited.
# Writes REWARD (0/1) to /logs/verifier/reward.txt on EVERY exit path.
set -u

mkdir -p /logs/verifier

overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt

log() { echo "sable-journal verify: $*" >&2; }

python3 - <<'PY'
import hashlib
import json
import os
import random
import re
import subprocess
import sys

failures = []

# ---------------------------------------------------------------------------
# Fixture integrity: pristine reference copies and the visible fixtures must
# stay byte-identical (agent cannot weaken the load or the bug substrate).
# ---------------------------------------------------------------------------
FIXTURE_SHAS = {
    "/opt/pristine/wordcount_service.py":
        "5958e8b2dc0f7d6b6a06ccfbb5a6a181baf61843259797c20ecc9070bb3b977c",
    "/opt/pristine/loadgen.py":
        "4744b02974f4c6b0cae0a10c73a62b354d620d1db34c7fc4de0e38053e19647f",
    "/opt/pristine/corpus.txt":
        "1ad31638b213297980998eef7e01f83119cd817ea3f1240c1abc7028246a9732",
    "/app/svc/loadgen.py":
        "4744b02974f4c6b0cae0a10c73a62b354d620d1db34c7fc4de0e38053e19647f",
    "/app/data/corpus.txt":
        "1ad31638b213297980998eef7e01f83119cd817ea3f1240c1abc7028246a9732",
}
for path, want in FIXTURE_SHAS.items():
    try:
        with open(path, "rb") as fh:
            got = hashlib.sha256(fh.read()).hexdigest()
    except OSError as exc:
        failures.append("fixture unreadable %s: %s" % (path, exc))
        continue
    if got != want:
        failures.append("fixture integrity mismatch: %s (load may have been "
                        "weakened or a pristine copy tampered with)" % path)

# ---------------------------------------------------------------------------
# Deliverable presence.
# ---------------------------------------------------------------------------
if not os.path.isfile("/app/diagnosis.md") or os.path.getsize("/app/diagnosis.md") == 0:
    failures.append("missing/empty /app/diagnosis.md")
if not os.path.isfile("/app/svc/wordcount_service.py"):
    failures.append("missing /app/svc/wordcount_service.py")

# ---------------------------------------------------------------------------
# Diagnosis writeup: must name the exact read/await/write lines of the
# SHIPPED original (extracted from the pristine copy) and a valid fix class.
# ---------------------------------------------------------------------------
def find_line(path, needle):
    with open(path, "r", encoding="utf-8") as fh:
        for i, line in enumerate(fh, 1):
            if needle in line:
                return i
    return None

pristine_svc = "/opt/pristine/wordcount_service.py"
if os.path.isfile(pristine_svc) and os.path.isfile("/app/diagnosis.md"):
    read_line = find_line(pristine_svc, "old = self.counts.get(word, 0)")
    await_line = find_line(pristine_svc, "# simulated slow I/O step")
    write_line = find_line(pristine_svc, "self.counts[word] = old + inc")
    if not (read_line and await_line and write_line
            and await_line == read_line + 1 and write_line == read_line + 2):
        failures.append("pristine service no longer shows the seeded "
                        "read/await/write triad (structure drift)")
    else:
        try:
            with open("/app/diagnosis.md", "r", encoding="utf-8") as fh:
                md = fh.read()
        except OSError as exc:
            failures.append("cannot read /app/diagnosis.md: %s" % exc)
            md = ""
        if len(md) < 250:
            failures.append("diagnosis too short to be a root-cause writeup")
        num_ok = all(
            re.search(r"(?<![0-9])%d(?!\\d)" % n, md)
            for n in (read_line, await_line, write_line)
        )
        token_ok = (
            md.find("self.counts.get") >= 0
            and md.find("await asyncio.sleep") >= 0
            and md.find("self.counts[word] = old + inc") >= 0
        )
        if not (num_ok or token_ok):
            failures.append("diagnosis does not name the read/await/write "
                            "lines (%d/%d/%d) of the original service" % (
                                read_line, await_line, write_line))
        if not re.search(r"lock|atomic|no await|without await|critical "
                         r"section|synchronous", md, re.I):
            failures.append("diagnosis states no fix class")
        if not re.search(r"stale|interleav|race|concurrent|lost", md, re.I):
            failures.append("diagnosis describes no interleaving")

# ---------------------------------------------------------------------------
# Independent reference: true counts = sum over the deterministic schedule.
# ---------------------------------------------------------------------------
def expected_counts(corpus_path, workers, requests, seed):
    with open(corpus_path, "r", encoding="utf-8") as fh:
        docs = fh.read().splitlines()
    num_docs = len(docs)
    rng = random.Random(seed)
    total = workers * requests
    exp = {}
    for _k in range(total):
        doc_id = rng.randrange(num_docs)
        for token in docs[doc_id].lower().split():
            exp[token] = exp.get(token, 0) + 1
    return exp

def run_loadgen(service, corpus, workers, requests, seed, port, out):
    cmd = [sys.executable, "/opt/pristine/loadgen.py",
           "--service", service, "--corpus", corpus,
           "--workers", str(workers), "--requests", str(requests),
           "--seed", str(seed), "--port", str(port), "--out", out]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        failures.append("loadgen timeout (service=%s workers=%d)" % (service, workers))
        return None
    if res.returncode != 0:
        failures.append("loadgen failed rc=%d (service=%s workers=%d): %s" % (
            res.returncode, service, workers, (res.stderr or "")[-200:]))
        return None
    try:
        with open(out, "r", encoding="utf-8") as fh:
            counts = json.load(fh)
    except Exception as exc:
        failures.append("loadgen out unreadable: %s" % exc)
        return None
    return counts

def same_counts(a, b):
    return isinstance(a, dict) and a == b

DOC_LOAD = dict(workers=40, requests=6, seed=2718)

# ---------------------------------------------------------------------------
# Visible case (documented load) through the FIXED deliverable.
# ---------------------------------------------------------------------------
if os.path.isfile("/app/svc/wordcount_service.py"):
    counts = run_loadgen(
        "/app/svc/wordcount_service.py", "/app/data/corpus.txt",
        DOC_LOAD["workers"], DOC_LOAD["requests"], DOC_LOAD["seed"],
        8642, "/tmp/tl_vis_fixed.json")
    exp_vis = expected_counts(
        "/app/data/corpus.txt",
        DOC_LOAD["workers"], DOC_LOAD["requests"], DOC_LOAD["seed"])
    if counts is not None and not same_counts(counts, exp_vis):
        failures.append("visible documented-load run: fixed service counts "
                        "differ from independently recomputed truth")

# ---------------------------------------------------------------------------
# Bug repro: the ORIGINAL shipped service must still CORRUPT under the same
# documented load (proves the agent did not dodge the load).
# ---------------------------------------------------------------------------
counts_buggy = run_loadgen(
    "/opt/pristine/wordcount_service.py", "/app/data/corpus.txt",
    DOC_LOAD["workers"], DOC_LOAD["requests"], DOC_LOAD["seed"],
    8643, "/tmp/tl_vis_buggy.json")
if counts_buggy is not None:
    if same_counts(counts_buggy, exp_vis):
        failures.append("bug-repro: pristine original service did NOT corrupt "
                        "under the documented load (expected lost updates)")

# ---------------------------------------------------------------------------
# Hidden cases: different corpora + worker counts, recomputed independently.
# ---------------------------------------------------------------------------
hidden_root = "/tests/hidden"
if os.path.isdir(hidden_root):
    cases = sorted(
        d for d in os.listdir(hidden_root)
        if os.path.isdir(os.path.join(hidden_root, d)))
    if not cases:
        failures.append("no hidden cases present")
    for idx, case in enumerate(cases):
        cdir = os.path.join(hidden_root, case)
        try:
            with open(os.path.join(cdir, "config.json"), "r", encoding="utf-8") as fh:
                cfg = json.load(fh)
        except Exception as exc:
            failures.append("hidden case %s: bad config: %s" % (case, exc))
            continue
        corpus = os.path.join(cdir, "corpus.txt")
        port = int(cfg.get("port", 8650 + idx))
        workers = int(cfg["workers"])
        requests = int(cfg["requests"])
        seed = int(cfg["seed"])
        out = "/tmp/tl_hidden_%d.json" % idx
        counts = run_loadgen(
            "/app/svc/wordcount_service.py", corpus,
            workers, requests, seed, port, out)
        if counts is None:
            continue
        exp = expected_counts(corpus, workers, requests, seed)
        if not same_counts(counts, exp):
            failures.append("hidden case %s (workers=%d requests=%d): counts "
                            "differ from independently recomputed truth"
                            % (case, workers, requests))
else:
    failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then
  overall=1
  log "all checks passed"
else
  overall=0
  msgs="$msgs python-verifier-failed"
  log "FAIL${msgs:+:${msgs}}"
fi

finalize_reward
exit 0