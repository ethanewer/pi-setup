#!/bin/bash
# Verifier for tasks/prism-atlas (executes-deliverable).
#
# Re-invokes each deliverable and independently recomputes the expected results:
#   * /app/rank_callsites.py on the visible calls corpus AND hidden corpora
#     (incl. an empty dir) vs. an independent frequency/rank recomputation;
#   * /app/callsite_rank.txt against that recompute;
#   * /app/stateful_cli.py across repeated calls (positive/negative deltas, a
#     missing state file, and reading a prior value) to prove it accumulates
#     rather than resets, and that its default /app/state/state.txt persists;
#   * /app/out.txt as the integer produced by replaying the documented
#     transaction sequence from the fixture initial value;
#   * /app/apply_macros.vim re-run on freshly inserted hidden rows, plus the
#     produced /app/transformed/depot-*.txt checked byte-for-byte.
# Writes a numeric reward to /logs/verifier/reward.txt. Never consults the oracle.
set -u
mkdir -p /logs/verifier

[ -x /app/rank_callsites.py ] || { echo "missing/not-executable /app/rank_callsites.py" >&2; echo 0 > /logs/verifier/reward.txt; exit 0; }
[ -x /app/stateful_cli.py ]   || { echo "missing/not-executable /app/stateful_cli.py" >&2; echo 0 > /logs/verifier/reward.txt; exit 0; }
[ -f /app/apply_macros.vim ]  || { echo "missing /app/apply_macros.vim"; echo 0 > /logs/verifier/reward.txt; exit 0; }
[ -f /app/callsite_rank.txt ] || { echo "missing /app/callsite_rank.txt"; echo 0 > /logs/verifier/reward.txt; exit 0; }
[ -f /app/out.txt ]           || { echo "missing /app/out.txt"; echo 0 > /logs/verifier/reward.txt; exit 0; }

python3 - <<'PYEOF'
import collections
import os
import re
import subprocess
import sys

failures = []
HALL = "/tests/hidden"

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

def read_text(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()

def interesting_lines(path):
    """Non-empty, whitespace-stripped lines of a file (callsite rule)."""
    out = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                line = raw.rstrip("\r\n").strip()
                if line:
                    out.append(line)
    except OSError:
        pass
    return out

def reference_rank(directory, top_n=10):
    """Independent recompute of part-1 ranking (count desc, then byte order)."""
    items = []
    try:
        names = [n for n in os.listdir(directory)
                 if os.path.isfile(os.path.join(directory, n))]
    except OSError:
        names = []
    names.sort()
    for name in names:
        items += interesting_lines(os.path.join(directory, name))
    counts = collections.Counter(items)
    return [k for k, _ in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:top_n]]

def reference_transform(line):
    m = re.fullmatch(r"[^|]+\|[^|]+\|[^|]+", line)
    if m:
        f1, f2, f3 = line.split("|")
        return f2 + " (" + f1 + ") " + f3
    return line

def check_output_lines(path, expected):
    """Compare the file content, split on newlines, to an expected list."""
    if not os.path.exists(path):
        failures.append("missing output %s" % path)
        return
    got = read_text(path).split("\n")
    while got and got[-1] == "":   # tolerate differing trailing newline counts
        got.pop()
    exp = list(expected)
    while exp and exp[-1] == "":
        exp.pop()
    if got != exp:
        failures.append("%s mismatch:\n  got: %r\n  want: %r" % (path, got, exp))

# ============================================================================
# A. Call-site ranking: visible deliverable + hidden corpora.
# ============================================================================
ref_fixture = reference_rank("/app/data/calls", 10)
check_output_lines("/app/callsite_rank.txt", ref_fixture)

r = run(["python3", "/app/rank_callsites.py", "/app/data/calls", "/tmp/rk_a.txt", "10"])
if r.returncode != 0:
    failures.append("rank(visible) rc=%s: %s" % (r.returncode, (r.stderr or "")[-200:]))
else:
    check_output_lines("/tmp/rk_a.txt", reference_rank("/app/data/calls", 10))

r = run(["python3", "/app/rank_callsites.py", os.path.join(HALL, "calls_1"),
         "/tmp/rk_b.txt", "10"])
if r.returncode != 0:
    failures.append("rank(hidden) rc=%s: %s" % (r.returncode, (r.stderr or "")[-200:]))
else:
    check_output_lines("/tmp/rk_b.txt", reference_rank(os.path.join(HALL, "calls_1"), 10))

r = run(["python3", "/app/rank_callsites.py", os.path.join(HALL, "calls_2"),
         "/tmp/rk_c.txt", "10"])
if r.returncode != 0:
    failures.append("rank(empty) rc=%s: %s" % (r.returncode, (r.stderr or "")[-200:]))
elif not os.path.exists("/tmp/rk_c.txt"):
    failures.append("rank(empty) did not create output file")
else:
    if read_text("/tmp/rk_c.txt").strip() != "":
        failures.append("rank(empty) output not empty")

# ============================================================================
# B. stateful_cli: accumulation without reset + /app/out.txt completeness.
# ============================================================================
def run_counter(delta, state=None):
    cmd = ["python3", "/app/stateful_cli.py", str(delta)]
    if state:
        cmd.append(state)
    return run(cmd)

def read_int(path):
    try:
        return int(read_text(path).strip())
    except Exception:
        return None

# B1. Missing initial file -> start from 0; accumulate; handle negatives; print.
s1 = "/tmp/cli_state1.txt"
if os.path.exists(s1):
    os.remove(s1)
r = run_counter(4, s1)
if r.returncode != 0 or read_int(s1) != 4 or r.stdout.strip() != "4":
    failures.append("counter-miss-start(4): rc=%s file=%r out=%r"
                    % (r.returncode, read_int(s1), r.stdout.strip()))
run_counter(9, s1)
if read_int(s1) != 13:
    failures.append("counter 4+9: got %r" % read_int(s1))
run_counter(-20, s1)
if read_int(s1) != -7:
    failures.append("counter 13-20: got %r" % read_int(s1))

# B2. Must READ the prior value (100+6 -> 106), not reset to a fixed initial.
s = "/tmp/cli_state2.txt"
with open(s, "w") as fh:
    fh.write("100\n")
run_counter(6, s)
if read_int(s) != 106:
    failures.append("counter must read prior (100+6): got %r" % read_int(s))

# B3. Default state file persists across separate invocations.
DEF = "/app/state/state.txt"
base = read_int(DEF) if os.path.exists(DEF) else 0
run_counter(13)      # no state path -> default file
run_counter(-8)
if read_int(DEF) != base + 5:
    failures.append("default-state persistence: base=%r want %r got %r"
                    % (base, base + 5, read_int(DEF)))

# B4. /app/out.txt == integer reached by replaying the documented sequence from
#     the fixture's initial value.
documented = [5, 9, -2, 11, 8, 14, 0]
s = "/tmp/cli_state3.txt"
with open(s, "w") as fh:
    fh.write("17\n")
for d in documented:
    run_counter(d, s)
expected_int = read_int(s)
try:
    out_int = int(read_text("/app/out.txt").strip())
except Exception:
    out_int = None
    failures.append("/app/out.txt not an integer")
if expected_int is not None and out_int is not None and out_int != expected_int:
    failures.append("/app/out.txt=%r, want recomputed %r" % (out_int, expected_int))

# ============================================================================
# C. apply_macros.vim: visible transformed files + a fresh hidden re-run.
# ============================================================================
def vim_transform(sources):
    cmd = ["vim", "-es", "-N", "-u", "NONE", "-i", "NONE", "-n",
           "-S", "/app/apply_macros.vim"] + sources
    return subprocess.run(cmd, capture_output=True, text=True, cwd="/app",
                           stdin=subprocess.DEVNULL)

def reference_rows(path):
    return [reference_transform(ln) for ln in read_text(path).split("\n")]

for src, dst in (
    ("/app/data/rows/depot-a.txt", "/app/transformed/depot-a.txt"),
    ("/app/data/rows/depot-b.txt", "/app/transformed/depot-b.txt"),
    ("/app/data/rows/depot-c.txt", "/app/transformed/depot-c.txt"),
    ("/app/data/rows/depot-d.txt", "/app/transformed/depot-d.txt"),
):
    if not os.path.exists(dst):
        failures.append("missing transformed %s" % os.path.basename(dst))
        continue
    exp = reference_rows(src)
    got = read_text(dst).split("\n")
    while got and got[-1] == "":
        got.pop()
    while exp and exp[-1] == "":
        exp.pop()
    if got != exp:
        failures.append("transformed %s mismatch:\n  got: %r\n  want: %r"
                        % (os.path.basename(dst), got, exp))

hid = os.path.join(HALL, "rows_1", "hidden_rows.txt")
if os.path.exists(hid):
    r = vim_transform([hid])
    hin = os.path.join("/app/transformed", "hidden_rows.txt")
    if not os.path.exists(hin):
        failures.append("macro re-run wrote no %s (vim rc=%s %r)"
                        % (hin, r.returncode, (r.stderr or "")[-200:]))
    else:
        exp = [reference_transform(ln) for ln in read_text(hid).split("\n")]
        got = read_text(hin).split("\n")
        while got and got[-1] == "":
            got.pop()
        while exp and exp[-1] == "":
            exp.pop()
        if got != exp:
            failures.append("hidden transform mismatch:\n  got: %r\n  want: %r" % (got, exp))
else:
    failures.append("missing hidden row fixture")

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    raise SystemExit(0)

print("ALL PASS")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PYEOF