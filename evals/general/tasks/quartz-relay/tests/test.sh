#!/bin/bash
# Verifier for quartz-relay: checks the visible deliverables are present and
# correct against an independent reference relabel of the shipped fixtures,
# ENFORCES the no-modify rule on /app/data/feeds, and RE-RUNS the deliverable
# script /app/apply_relabel.vim headless on hidden feed files, comparing each
# output byte-for-byte. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the shipped fixtures (the instruction forbids modifying
# or deleting them; tampering defeats the visible-case check).
sha_of() {
  case "$1" in
    station-a) echo "4296f2ee32b56b9f9409a5b885dfd5bd21afda2a5296224955e30fd044cb2ede" ;;
    station-b) echo "00fbfcffa1970ee4a43d5ed3c62c96d96953cdd4c2eb7b2a0c14fd21f58348c4" ;;
    station-c) echo "420a38b6651b525808d1df6eb32c8c9c86f061664ab3c0f5d1a93132d19b9274" ;;
    station-d) echo "5e9cfa9f493ee14cc84d49f363190b7ab10f808c8665a0ca515e6bd91d8f51eb" ;;
  esac
}

no_modify_broken=0
for name in station-a station-b station-c station-d; do
  src="/app/data/feeds/$name.txt"
  if [ ! -f "$src" ]; then
    echo "no-modify: $src missing" >&2
    no_modify_broken=1
    continue
  fi
  actual="$(sha256sum "$src" | awk '{print $1}')"
  if [ "$actual" != "$(sha_of "$name")" ]; then
    echo "no-modify: $src was modified" >&2
    no_modify_broken=1
  fi
done

if [ ! -f /app/apply_relabel.vim ]; then
  echo "missing /app/apply_relabel.vim" >&2
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

python3 - "$no_modify_broken" <<'PY'
import os
import re
import shutil
import subprocess
import sys
import tempfile

failures = []
if sys.argv[1] == "1":
    failures.append("fixtures modified or missing (no-modify rule)")

VIMSCRIPT = "/app/apply_relabel.vim"
OUTDIR = "/app/transformed"

ROW = re.compile(r"^(\d{4})-(\d{2})-(\d{2});([A-Z]{3});([^;]+)$")


def reference_transform(line):
    m = ROW.match(line)
    if m:
        yyyy, mm, dd, code, label = m.groups()
        return "%s [%s] %s.%s.%s" % (label, code, dd, mm, yyyy)
    return line


def read_lines(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read().split("\n")


def norm(lines):
    lines = list(lines)
    while lines and lines[-1] == "":
        lines.pop()
    return lines


def run_vim(sources):
    cmd = ["vim", "-es", "-N", "-u", "NONE", "-i", "NONE", "-n",
           "-S", VIMSCRIPT] + list(sources)
    return subprocess.run(cmd, capture_output=True, text=True, cwd="/app",
                          stdin=subprocess.DEVNULL)


def check_pair(src, dst, label):
    if not os.path.exists(dst):
        failures.append("missing %s (%s)" % (dst, label))
        return
    want = norm([reference_transform(l) for l in read_lines(src)])
    got = norm(read_lines(dst))
    if got != want:
        failures.append("%s mismatch (%s):\n  got:  %r\n  want: %r"
                        % (dst, label, got, want))


# --- visible fixtures: transformed outputs must match the reference relabel.
for name in ("station-a", "station-b", "station-c", "station-d"):
    src = "/app/data/feeds/%s.txt" % name
    dst = os.path.join(OUTDIR, name + ".txt")
    check_pair(src, dst, "visible")

# The visible outputs must also survive a fresh re-run of the script on the
# same sources (idempotence of the documented invocation). Exit status is not
# scored; correctness of the rewritten outputs is.
r = run_vim([])
for name in ("station-a", "station-b", "station-c", "station-d"):
    src = "/app/data/feeds/%s.txt" % name
    dst = os.path.join(OUTDIR, name + ".txt")
    check_pair(src, dst, "visible re-run")

# --- hidden cases: fresh feeds replayed through the script with explicit args.
hidden_root = "/tests/hidden"
if os.path.isdir(hidden_root):
    cases = sorted(os.listdir(hidden_root))
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        case_dir = os.path.join(hidden_root, case)
        if not os.path.isdir(case_dir):
            failures.append("hidden '%s' malformed" % case)
            continue
        files = sorted(f for f in os.listdir(case_dir) if f.endswith(".txt"))
        if not files:
            failures.append("hidden '%s' has no .txt files" % case)
            continue
        # copy to a scratch dir with writable paths, then replay the script
        tmp = tempfile.mkdtemp(prefix="qr_")
        try:
            sources = []
            for f in files:
                s = os.path.join(tmp, f)
                shutil.copyfile(os.path.join(case_dir, f), s)
                sources.append(s)
            r = run_vim(sources)
            for s in sources:
                dst = os.path.join(OUTDIR, os.path.basename(s))
                check_pair(s, dst, "hidden '%s'" % case)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
else:
    failures.append("no hidden cases present")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ $rc -ne 0 ]; then reward=0; else reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
