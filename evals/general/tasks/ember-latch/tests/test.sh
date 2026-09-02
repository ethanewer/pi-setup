#!/bin/bash
# Verifier for tasks/ember-latch (executes-deliverable).
#
# Checks the visible deliverables (/app/apply_macros.vim plus the four
# /app/normalized/feed-*.txt) against an independent recomputation of the
# documented transformation from the pristine fixtures in /app/data/feeds,
# ENFORCES the no-modify rule on those fixtures, and RE-RUNS the macro script
# headlessly on freshly inserted hidden row files, comparing its outputs
# byte-for-byte to the recomputation. Writes 0/1 to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

[ -f /app/apply_macros.vim ] || { echo "missing /app/apply_macros.vim" >&2; echo 0 > /logs/verifier/reward.txt; exit 0; }

python3 - <<'PYEOF'
import os
import re
import subprocess
import sys

failures = []
HALL = "/tests/hidden"

# Strict, zero-padded shape: lowercase level | \d{4}-\d{2}-\d{2} | message
# without '|'. Anchored on both ends; nothing is stripped.
SHAPE = re.compile(r"^([a-z]+)\|(\d{4}-\d{2}-\d{2})\|([^|]+)$")


def transform_line(line):
    m = SHAPE.match(line)
    if not m:
        return line
    level, date, message = m.groups()
    return "%s [%s] %s" % (date, level.upper(), message)


def reference_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return [transform_line(ln) for ln in fh.read().split("\n")]
    except OSError:
        return None


def read_text(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def check_file(path, expected_lines, tag):
    if not os.path.isfile(path):
        failures.append("missing output %s (%s)" % (path, tag))
        return
    got = read_text(path).split("\n")
    want = list(expected_lines)
    while got and got[-1] == "":
        got.pop()
    while want and want[-1] == "":
        want.pop()
    if got != want:
        failures.append("%s mismatch (%s):\n  got:  %r\n  want: %r"
                        % (path, tag, got, want))


def vim_run(sources):
    cmd = ["vim", "-es", "-N", "-u", "NONE", "-i", "NONE", "-n",
           "-S", "/app/apply_macros.vim"] + list(sources)
    return subprocess.run(cmd, capture_output=True, text=True, cwd="/app",
                          stdin=subprocess.DEVNULL, timeout=120)


# ---------------------------------------------------------------------------
# A. Visible deliverables: /app/normalized/feed-*.txt vs the fixtures.
# ---------------------------------------------------------------------------
VISIBLE = ["/app/normalized/feed-north.txt", "/app/normalized/feed-south.txt",
           "/app/normalized/feed-east.txt", "/app/normalized/feed-west.txt"]
for dst in VISIBLE:
    src = os.path.join("/app/data/feeds", os.path.basename(dst))
    if not os.path.isfile(src):
        failures.append("fixture %s missing (was /app/data modified?)" % src)
        continue
    check_file(dst, reference_lines(src), "visible")

# ---------------------------------------------------------------------------
# B. Hidden cases: re-run the macro script on fresh row files.
# ---------------------------------------------------------------------------
hidden_dir = HALL
cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
if not cases:
    failures.append("no hidden cases present")
for case in cases:
    base = os.path.join(hidden_dir, case)
    if not os.path.isdir(base):
        continue
    rows = sorted(f for f in os.listdir(base) if f.endswith(".txt"))
    if not rows:
        failures.append("hidden case '%s' has no .txt rows" % case)
        continue
    srcs = [os.path.join(base, f) for f in rows]
    try:
        r = vim_run(srcs)
    except Exception as exc:
        failures.append("hidden case '%s': vim re-run failed: %r" % (case, exc))
        continue
    for src in srcs:
        dst = os.path.join("/app/normalized", os.path.basename(src))
        if not os.path.isfile(dst):
            failures.append("hidden case '%s': macro wrote no %s (rc=%s)"
                            % (case, dst, r.returncode))
            continue
        check_file(dst, reference_lines(src), "hidden/%s" % case)

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PYEOF
exit 0
