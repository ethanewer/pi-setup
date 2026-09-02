#!/bin/bash
# Verifier for anchor-quill: executes the deliverable /app/apply_lists.py on
# the visible spec and on hidden spec files, and inspects ONLY the canonical
# Postfix configuration (/etc/postfix/virtual + rebuilt .db + main.cf).
# Writes the reward to /logs/verifier/reward.txt on every exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

export PATH="/usr/sbin:/usr/local/sbin:$PATH"
TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

overall=1
msgs=""

[ -f /app/apply_lists.py ] || { overall=0; msgs="$msgs missing:apply_lists.py"; }

res=$("$TIMEOUT_CMD" 280 python3 - "$overall" <<'PYEOF'
import json, os, re, subprocess, sys

overall = sys.argv[1] == "1"
failures = []

VIRTUAL = "/etc/postfix/virtual"
MAINCF = "/etc/postfix/main.cf"
PROG = "/app/apply_lists.py"


def find_bin(name):
    for d in ("/usr/sbin", "/usr/bin", "/usr/local/sbin"):
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    return name


def run_prog(spec):
    r = subprocess.run(
        [sys.executable, PROG, spec],
        capture_output=True, text=True, timeout=120,
    )
    return r.returncode


def read_map(path):
    """Parse a postfix map file into {key: sorted[dests]}, ignoring comments."""
    m = {}
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            parts = s.split()
            if len(parts) < 2:
                return None
            key = parts[0]
            dests = sorted(t for t in re.split(r"[,\s]+", " ".join(parts[1:])) if t)
            m[key] = dests
    return m


def check_applied(expected, label):
    """expected: {addr: sorted[dests]}. Checks the canonical file, the rebuilt
    .db (postmap -q) and the main.cf declaration."""
    got = read_map(VIRTUAL)
    if got is None:
        failures.append("%s: canonical map %s missing" % (label, VIRTUAL))
        return
    if got != expected:
        failures.append("%s: canonical map content mismatch" % label)
        return
    if not os.path.isfile(VIRTUAL + ".db"):
        failures.append("%s: map database .db not rebuilt" % label)
        return
    for addr, dests in expected.items():
        q = subprocess.run(
            ["timeout", "30", find_bin("postmap"), "-q", addr,
             "hash:" + VIRTUAL],
            capture_output=True, text=True, timeout=40,
        )
        if q.returncode != 0:
            failures.append("%s: postmap -q failed for %s" % (label, addr))
            continue
        got_dests = sorted(t for t in re.split(r"[,\s]+", q.stdout.strip()) if t)
        if got_dests != dests:
            failures.append("%s: rebuilt map wrong value for %s" % (label, addr))
    # main.cf must declare virtual_alias_maps pointing at the canonical file
    declared = False
    if os.path.isfile(MAINCF):
        with open(MAINCF, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if "virtual_alias_maps" in line and "/etc/postfix/virtual" in line:
                    declared = True
    if not declared:
        failures.append("%s: main.cf does not declare virtual_alias_maps "
                        "for the canonical map" % label)


def run_case(spec_path, expected_path, label):
    try:
        expected = json.load(open(expected_path))
    except Exception as exc:
        failures.append("%s: expected unreadable (%s)" % (label, exc))
        return
    r = subprocess.run(
        [sys.executable, PROG, spec_path],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        failures.append("%s: program exited %d" % (label, r.returncode))
        return
    check_applied(expected, label)


# ---- visible case -----------------------------------------------------------
if overall:
    if not os.path.isfile("/app/fixtures/lists.spec"):
        failures.append("visible: fixture lists.spec missing")
    else:
        run_case("/app/fixtures/lists.spec", "/tests/expected.json",
                 "visible")
        # idempotency: applying the same spec twice must not change anything
        run_case("/app/fixtures/lists.spec", "/tests/expected.json",
                 "visible-repeat")

# ---- hidden cases -----------------------------------------------------------
hidden_dir = "/tests/hidden"
cases = sorted(d for d in os.listdir(hidden_dir)
               if os.path.isdir(os.path.join(hidden_dir, d))) \
    if os.path.isdir(hidden_dir) else []
if not cases:
    failures.append("hidden: no cases present")
for case in cases:
    base = os.path.join(hidden_dir, case)
    spec = os.path.join(base, "spec.txt")
    exp = os.path.join(base, "expected.json")
    if not (os.path.isfile(spec) and os.path.isfile(exp)):
        failures.append("hidden %s: malformed fixture" % case)
        continue
    run_case(spec, exp, "hidden %s" % case)

if failures or not overall:
    print("anchor-quill verifier FAIL: %s" % "; ".join(failures),
          file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PYEOF
)

if [ $? -eq 0 ] && [ "$overall" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
else
    printf 0 > /logs/verifier/reward.txt
fi
exit 0