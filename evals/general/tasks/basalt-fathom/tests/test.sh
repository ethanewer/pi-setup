#!/bin/bash
# Verifier for basalt-fathom: ENFORCES no-modify on the shipped artifacts,
# EXECUTES the deliverable (/app/solve.py attest) on hidden binary inputs,
# compares against an independent implementation of the documented chain, and
# checks /app/answer.json. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the shipped artifacts (instruction forbids modification).
# The blob hash is recomputed from its deterministic generator; the ledger and
# manifest hashes are fixed constants of the shipped fixture content.
PRISTINE_BLOB_SHA="$(python3 - <<'PY'
import random, hashlib
rng = random.Random(470211)
blob = bytes(rng.randrange(256) for _ in range(512))
print(hashlib.sha256(blob).hexdigest())
PY
)"
PRISTINE_LEDGER_SHA="$(printf 'ledger entry 0001: manifest seal scheduled\nledger entry 0002: chain must reproduce byte-exact\nledger entry 0003: verifier holds the reference implementation\n' | sha256sum | awk '{print $1}')"
PRISTINE_MANIFEST_SHA="$(printf 'blob.bin\nledger.txt\n' | sha256sum | awk '{print $1}')"

no_modify_broken=0
for spec in "/app/artifacts/blob.bin:$PRISTINE_BLOB_SHA" "/app/artifacts/ledger.txt:$PRISTINE_LEDGER_SHA" "/app/artifacts/manifest.txt:$PRISTINE_MANIFEST_SHA"; do
    path="${spec%%:*}"; want="${spec##*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$path" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $path was modified" >&2
            no_modify_broken=1
        fi
    fi
done

python3 - "$no_modify_broken" <<'PY'
import hashlib
import json
import os
import subprocess
import sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("shipped artifacts modified or missing")


def attest(P: bytes) -> str:
    h1 = hashlib.md5(P).digest()
    h2 = hashlib.sha512(h1[:8]).digest()
    h3 = hashlib.blake2b(h2[:24] + h1[6:14], digest_size=20).digest()
    return hashlib.sha3_256(h3 + P).hexdigest()


def run_attest(path):
    """Run the deliverable's attest subcommand; return the digest or None."""
    r = subprocess.run([sys.executable, SOLVE, "attest", path],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        return None
    lines = [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
    if len(lines) != 1:
        return None
    return lines[0]


if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- hidden cases: genuinely distinct binary inputs, expected computed here ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            files = [os.path.join(base, f) for f in sorted(os.listdir(base))
                     if os.path.isfile(os.path.join(base, f))]
            if not files:
                failures.append("hidden '%s' has no input files" % c)
                continue
            for f in files:
                with open(f, "rb") as fh:
                    want = attest(fh.read())
                got = run_attest(f)
                if got is None:
                    failures.append("hidden case '%s' (%s): attest failed" % (c, os.path.basename(f)))
                elif got != want:
                    failures.append("hidden case '%s' (%s): digest mismatch" % (c, os.path.basename(f)))
    else:
        failures.append("no hidden cases directory")

    # --- visible deliverable: /app/answer.json ---
    if os.path.isfile("/app/answer.json"):
        try:
            with open("/app/answer.json") as fh:
                got = json.load(fh)
            with open("/tests/expected.json") as fh:
                want = json.load(fh)
            if not isinstance(got, dict) or got != want:
                failures.append("/app/answer.json does not match expected attestations")
            else:
                # recompute one attestation live to prove the program computes it
                live = run_attest("/app/artifacts/blob.bin")
                if live is None or live != want["attestations"]["blob.bin"]:
                    failures.append("live attest on blob.bin disagrees with answer.json")
        except Exception:
            failures.append("/app/answer.json unreadable")
    else:
        failures.append("missing /app/answer.json")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
