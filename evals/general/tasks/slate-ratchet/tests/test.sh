#!/bin/bash
# Verifier for slate-ratchet: checksums /app/src/vault.c against the release
# manifest, RECOMPILES the recorded validation logic from source at three
# optimization levels, and grades /app/codes.txt against the freshly built
# checkers (plus a negative control that must be REJECTed). Writes REWARD
# (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_VAULT_SHA="50983bb6518aa14895c0d17597255ec8e0962dd1b75f8e774d9748ca5f7cf81e"

fail=0
if [ ! -f /app/src/vault.c ]; then
    echo "no-modify: /app/src/vault.c missing" >&2
    fail=1
else
    actual="$(sha256sum /app/src/vault.c | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_VAULT_SHA" ]; then
        echo "no-modify: /app/src/vault.c was modified" >&2
        fail=1
    fi
fi

# Recompile the recorded logic from (checksum-verified) source. If the agent
# tampered with the source the checksum above already failed; recompiling from
# the pristine source proves the answer does not depend on any patched binary.
gcc -O0 -o /tmp/vault_O0 /app/src/vault.c 2>/dev/null || fail=1
gcc -O2 -o /tmp/vault_O2 /app/src/vault.c 2>/dev/null || fail=1
gcc -Os  -o /tmp/vault_Os /app/src/vault.c 2>/dev/null || fail=1

python3 - "$fail" <<'PY'
import json, os, re, subprocess, sys

fail = int(sys.argv[1])
failures = []

CODES = "/app/codes.txt"
LINE_RE = re.compile(r"^([A-Z])=([A-Za-z0-9]{16})$")
ALPH = set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

BINARIES = ["/tmp/vault_O0", "/tmp/vault_O2", "/tmp/vault_Os"]


def run_bin(binary, profile, code):
    try:
        r = subprocess.run([binary, profile, code],
                           capture_output=True, text=True, timeout=60)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    return r.stdout.strip()


# negative control: hidden probe codes (one symbol off each true code) must be
# REJECTed by every fresh build, so a checker that accepts anything cannot pass.
try:
    with open("/tests/hidden/negative.json") as fh:
        NEG = {k: v for k, v in json.load(fh).items() if k != "note"}
except Exception:
    NEG = {}
    failures.append("negative-control config unreadable")
for prof, bad in sorted(NEG.items()):
    for b in BINARIES:
        if run_bin(b, prof, bad) != "REJECT":
            failures.append("negative control not rejected (%s, %s)" % (b, prof))

if fail:
    failures.append("source checksum or recompile step failed (no-modify rule)")

# parse the deliverable
entries = {}
if not os.path.isfile(CODES):
    failures.append("missing /app/codes.txt")
else:
    try:
        with open(CODES, encoding="utf-8") as fh:
            raw = fh.read()
    except Exception:
        raw = None
        failures.append("codes.txt unreadable")
    if raw is not None:
        for ln, line in enumerate(raw.splitlines(), 1):
            line = line.strip()
            if not line:
                continue
            m = LINE_RE.match(line)
            if not m:
                failures.append("codes.txt line %d malformed" % ln)
                continue
            prof, code = m.group(1), m.group(2)
            if prof in entries:
                failures.append("duplicate profile %s" % prof)
                continue
            if not set(code) <= ALPH:
                failures.append("code for %s uses symbols outside the alphabet" % prof)
                continue
            entries[prof] = code

if not failures:
    # hidden expectation: exactly the profiles enabled in this build
    try:
        with open("/tests/hidden/expected.json") as fh:
            want = json.load(fh)
    except Exception:
        want = None
        failures.append("verifier config unreadable")
    if want is not None:
        required = set(want.get("profiles", []))
        for prof in sorted(required):
            if prof not in entries:
                failures.append("no code shipped for profile %s" % prof)
                continue
            code = entries[prof]
            for b in BINARIES:
                if run_bin(b, prof, code) != "ACCEPT %s" % prof:
                    failures.append("profile %s code not ACCEPTed by %s" % (prof, b))
        for prof, code in sorted(entries.items()):
            if prof not in required:
                failures.append("shipped profile %s is not enabled in this build" % prof)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
