#!/bin/bash
# Verifier for hinge-lathe (executes-deliverable).
#
#  * Checks /app/bulletin.vim exists.
#  * Checks the visible outputs /app/outbox/batch-*.txt against an
#    independent reference transform of the shipped /appdata/relay corpora.
#  * Re-runs /app/bulletin.vim (no-args mode) after clearing /app/outbox and
#    re-checks regeneration.
#  * Re-runs /app/bulletin.vim in explicit-file mode on hidden corpora and
#    checks the produced /app/outbox/<basename> files (byte-for-byte modulo
#    trailing newline count).
#
# Writes REWARD (0/1) to /logs/verifier/reward.txt. Never consults the oracle.
set -u
mkdir -p /logs/verifier

[ -f /app/bulletin.vim ] || { echo "missing /app/bulletin.vim" >&2; echo 0 > /logs/verifier/reward.txt; exit 0; }

python3 - <<'PY'
import os, re, subprocess, sys

failures = []
VIM = ["vim", "-es", "-N", "-u", "NONE", "-i", "NONE", "-n", "-S", "/app/bulletin.vim"]

TICKET = re.compile(r'^TKT-(\d+)\|([A-Z]+(?: [A-Z]+)*)\|([A-Z]+)$')
METRIC = re.compile(r'^load=(-)?(\d+)\.(\d{1,3})\|([a-z]+)$')


def transform_line(line):
    """Independent reference transform of a single line."""
    m = TICKET.match(line)
    if m:
        return "%s [TKT-%s] %s" % (m.group(2), m.group(1), m.group(3))
    m = METRIC.match(line)
    if m:
        sign = "-" if m.group(1) else "+"
        return "load %s %s%s.%s" % (m.group(4), sign, m.group(2),
                                    m.group(3).ljust(3, "0"))
    return line


def read_lines(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as exc:
        failures.append("unreadable %s: %s" % (path, exc))
        return None
    lines = text.replace("\r\n", "\n").split("\n")
    while lines and lines[-1] == "":
        lines.pop()
    return lines


def check_pair(src, dst):
    src_lines = read_lines(src)
    if src_lines is None:
        failures.append("missing source %s" % src)
        return
    got = read_lines(dst)
    if got is None:
        failures.append("missing output %s" % dst)
        return
    want = [transform_line(l) for l in src_lines]
    if got != want:
        failures.append("%s mismatch:\n  got:  %r\n  want: %r" % (dst, got, want))


def clear_outbox():
    try:
        for f in os.listdir("/app/outbox"):
            p = os.path.join("/app/outbox", f)
            if os.path.isfile(p):
                os.remove(p)
    except OSError:
        pass


def run_vim(files):
    try:
        return subprocess.run(VIM + list(files), capture_output=True,
                              text=True, cwd="/app",
                              stdin=subprocess.DEVNULL, timeout=120)
    except Exception as exc:
        failures.append("vim invocation failed: %s" % exc)
        return None


# ---------------------------------------------------------------- visible
# (src, dst) pairs with explicit paths so every deliverable is checked.
visible = (
    ("/appdata/relay/batch-1.txt", "/app/outbox/batch-1.txt"),
    ("/appdata/relay/batch-2.txt", "/app/outbox/batch-2.txt"),
    ("/appdata/relay/batch-3.txt", "/app/outbox/batch-3.txt"),
)
for src, dst in visible:
    check_pair(src, dst)

# ------------------------------------------------- no-args regeneration ---
clear_outbox()
r = run_vim([])
if r is not None and r.returncode != 0:
    failures.append("no-args vim run rc=%s: %r"
                    % (r.returncode, (r.stderr or "")[-300:]))
for src, dst in visible:
    check_pair(src, dst)

# --------------------------------------------------- hidden corpora -------
hidden = (
    ("/tests/hidden/rows_1/extra-rows.txt", "/app/outbox/extra-rows.txt"),
    ("/tests/hidden/rows_2/edge-rows.txt", "/app/outbox/edge-rows.txt"),
)
for src, dst in hidden:
    if not os.path.isfile(src):
        failures.append("hidden input missing %s" % src)
        continue
    r = run_vim([src])
    if r is not None and r.returncode != 0:
        failures.append("hidden vim run rc=%s for %s: %r"
                        % (r.returncode, src, (r.stderr or "")[-300:]))
    check_pair(src, dst)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ $rc -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
