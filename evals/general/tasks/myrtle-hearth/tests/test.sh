#!/bin/bash
# myrtle-hearth verifier: executes /app/derive.py on the visible pair and
# on every hidden (rules.json, lexicon.txt) pair, compares each output
# byte-for-byte against an independent recomputation of the documented
# sound-change semantics, checks /app/derived.tsv against the visible
# recompute, and checks the exit-code contract. Writes reward to
# /logs/verifier/reward.txt on EVERY exit path via an EXIT trap.
set -u
mkdir -p /logs/verifier
overall=1
finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt

if python3 - <<'PY'
import json, os, subprocess, sys

failures = []

def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kw)
    except Exception as exc:
        failures.append("running %r raised: %s" % (cmd, exc))
        return None

# --- independent reference implementation of the documented semantics ------
EDGE = "#"
ZERO = "0"

def ctx_left(w, i, left):
    if left == EDGE:
        return i == 0
    if left == "":
        return True
    return i >= 1 and w[i - 1] == left

def ctx_right(w, i, right):
    if right == EDGE:
        return i == len(w) - 1
    if right == "":
        return True
    return i + 1 < len(w) and w[i + 1] == right

def ctx_before(w, b, left):
    if left == EDGE:
        return b == 0
    if left == "":
        return False
    return b >= 1 and w[b - 1] == left

def ctx_after(w, b, right):
    if right == EDGE:
        return b == len(w)
    if right == "":
        return False
    return b < len(w) and w[b] == right

def rewrite(w, change):
    target = change["target"]
    result = change["result"]
    left = change.get("left", "")
    right = change.get("right", "")
    if target == ZERO:
        hits = [b for b in range(len(w) + 1)
                if ctx_before(w, b, left) and ctx_after(w, b, right)]
        for b in sorted(hits, reverse=True):
            w = w[:b] + [result] + w[b:]
        return w
    hits = [i for i in range(len(w))
            if w[i] == target and ctx_left(w, i, left) and ctx_right(w, i, right)]
    if result == ZERO:
        for i in sorted(hits, reverse=True):
            w = w[:i] + w[i + 1:]
        return w
    for i in hits:
        w[i] = result
    return w

def derive_word(tokens, changes):
    w = list(tokens)
    for change in changes:
        w = rewrite(w, change)
    return w

def expected_rows(rules_path, lexicon_path):
    with open(rules_path, "r", encoding="utf-8") as fh:
        changes = json.load(fh)["changes"]
    out = []
    with open(lexicon_path, "r", encoding="utf-8") as fh:
        for raw in fh.read().splitlines():
            line = raw.strip()
            if not line or line.startswith(EDGE):
                continue
            tokens = line.split()
            out.append(line + "\t" + " ".join(derive_word(tokens, changes)))
    return out

def tsv_text(rules_path, lexicon_path):
    rows = expected_rows(rules_path, lexicon_path)
    return "\n".join(rows) + ("\n" if rows else "")

def check_tsv(got_path, rules_path, lexicon_path, label):
    want = tsv_text(rules_path, lexicon_path)
    try:
        with open(got_path, "r", encoding="utf-8") as fh:
            got = fh.read()
    except OSError as exc:
        failures.append("%s: output unreadable: %s" % (label, exc))
        return
    if got != want:
        gl, wl = got.split("\n"), want.split("\n")
        n = next((i for i in range(max(len(gl), len(wl)))
                  if i >= len(gl) or i >= len(wl) or gl[i] != wl[i]), -1) + 1
        failures.append("%s: TSV mismatch at line %d\n  got : %r\n  want: %r"
                        % (label, n, got[:160], want[:160]))

DERIVE = "/app/derive.py"

def run_case(rules_path, lexicon_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    return run(["python3", DERIVE, rules_path, lexicon_path, out_path])

# --- 1. visible pair through the deliverable engine ------------------------
r = run_case("/app/rules.json", "/app/lexicon.txt", "/tmp/birch_visible.tsv")
if r is None or r.returncode != 0:
    failures.append("visible derive.py run failed (exit=%s)" % (r.returncode if r else "?"))
else:
    check_tsv("/tmp/birch_visible.tsv", "/app/rules.json", "/app/lexicon.txt", "visible")

# --- 2. derived.tsv deliverable equals the visible recompute ----------------
check_tsv("/app/derived.tsv", "/app/rules.json", "/app/lexicon.txt", "deliverable derived.tsv")

# --- 3. hidden (rules, lexicon) pairs ---------------------------------------
hidden = "/tests/hidden"
if os.path.isdir(hidden):
    cases = sorted(c for c in os.listdir(hidden)
                   if os.path.isfile(os.path.join(hidden, c, "rules.json"))
                   and os.path.isfile(os.path.join(hidden, c, "lexicon.txt")))
    if not cases:
        failures.append("no hidden cases found")
    for case in cases:
        r = run_case(os.path.join(hidden, case, "rules.json"),
                     os.path.join(hidden, case, "lexicon.txt"),
                     "/tmp/birch_hidden.tsv")
        if r is None:
            continue
        if r.returncode != 0:
            failures.append("hidden '%s' derive.py run failed (exit=%s, stderr=%r)"
                            % (case, r.returncode, (r.stderr or "")[:120]))
            continue
        check_tsv("/tmp/birch_hidden.tsv",
                  os.path.join(hidden, case, "rules.json"),
                  os.path.join(hidden, case, "lexicon.txt"),
                  "hidden '%s'" % case)
else:
    failures.append("no /tests/hidden directory")

# --- 4. exit-code contract --------------------------------------------------
def expect_exit(args, want, label):
    r = run(["python3", DERIVE] + args)
    if r is None:
        return
    if r.returncode != want:
        failures.append("%s: expected exit %d, got %d (stderr=%r)"
                        % (label, want, r.returncode, (r.stderr or "")[:120]))

expect_exit(["/app/rules.json", "/app/lexicon.txt"], 2, "wrong argument count")
expect_exit(["/app/rules.json", "/tmp/birch_missing_lex.txt", "/tmp/birch_x.tsv"],
            1, "missing lexicon file")
with open("/tmp/birch_bad_rules.json", "w") as fh:
    fh.write("this is not json at all")
expect_exit(["/tmp/birch_bad_rules.json", "/app/lexicon.txt", "/tmp/birch_x.tsv"],
            1, "unparseable rules.json")
with open("/tmp/birch_bad_lex.txt", "w") as fh:
    fh.write("a # b\n")
expect_exit(["/app/rules.json", "/tmp/birch_bad_lex.txt", "/tmp/birch_x.tsv"],
            1, "reserved token in lexicon word")
open("/tmp/birch_empty_lex.txt", "w").close()
r = run_case("/app/rules.json", "/tmp/birch_empty_lex.txt", "/tmp/birch_empty_out.tsv")
if r is None or r.returncode != 0:
    failures.append("empty lexicon run should succeed with exit 0")
else:
    try:
        size = os.path.getsize("/tmp/birch_empty_out.tsv")
    except OSError:
        size = -1
    if size != 0:
        failures.append("empty lexicon must produce a zero-byte out.tsv (size=%d)" % size)

print("birch verify failures: %d" % len(failures))
for f in failures:
    print("  - %s" % f)
sys.exit(1 if failures else 0)
PY
then
  overall=1
else
  overall=0
fi

finalize_reward
exit 0