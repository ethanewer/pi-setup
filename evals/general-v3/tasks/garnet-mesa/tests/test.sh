#!/bin/bash
# Verifier for garnet-mesa: ENFORCES the no-modify rule on the supplied /app
# fixtures, then EXECUTES the deliverable program (/app/allocate.py) on the
# visible fixture tree and on every hidden tree in /tests/hidden, comparing
# each report to its expected.json. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures (instruction: do not modify
# /app/data; tampering defeats the visible-case check).
PRISTINE_SHA_ROSTER="68c76605ec3b18b0270e0e02a0eaf9522da66b33679f4392be69fbe6d49c20ed"
PRISTINE_SHA_PKL="ebc5ec79dd870bedff4885b2459c0c5171cfba9eff5cddc1761c33f5a9ffab7e"
PRISTINE_SHA_B64="8f38d7ec45aa52ddc23282fb85c5e40b1958818394e3240cb5b453efedd6d518"
PRISTINE_SHA_TXT="58c433b1505bc7615a7b44d9b48757942d1fc81e9562e2c72672339cf70ecfca"

no_modify_broken=0
check_sha() {
    local path="$1" want="$2"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
        return
    fi
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $path was modified" >&2
        no_modify_broken=1
    fi
}
check_sha /app/data/roster.tsv "$PRISTINE_SHA_ROSTER"
check_sha /app/data/ledger/stores.pkl "$PRISTINE_SHA_PKL"
check_sha /app/data/ledger/trellis.b64 "$PRISTINE_SHA_B64"
check_sha /app/data/ledger/almanac.txt "$PRISTINE_SHA_TXT"

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/allocate.py"
OUT = "/tmp/garnet_mesa_verify_out.json"
no_modify_broken = int(sys.argv[1])

failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")


def norm(path):
    """Load and normalize a report; raises on malformed/missing output."""
    with open(path) as fh:
        obj = json.load(fh)
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"allocations", "sources_used", "unassigned"}, obj
    alloc = obj["allocations"]
    assert isinstance(alloc, list), alloc
    for a in alloc:
        assert isinstance(a, dict) and set(a.keys()) == {
            "cultivar_id", "plot", "family", "sown", "water", "shade", "source"
        }, a
        for k in a:
            assert isinstance(a[k], str), (k, a)
    su = obj["sources_used"]
    un = obj["unassigned"]
    assert isinstance(su, list) and all(isinstance(x, str) for x in su), su
    assert isinstance(un, list) and all(isinstance(x, str) for x in un), un
    return {"allocations": alloc, "sources_used": sorted(su), "unassigned": un}


def run_case(input_dir, expected_path):
    if os.path.exists(OUT):
        os.remove(OUT)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, input_dir, OUT],
            capture_output=True, text=True, timeout=120,
        )
    except Exception:
        return False
    if r.returncode != 0 or not os.path.exists(OUT):
        return False
    try:
        return norm(OUT) == norm(expected_path)
    except Exception:
        return False


if not os.path.isfile(SOLVE):
    failures.append("missing /app/allocate.py")
else:
    # --- visible case: EXECUTE allocate.py on the live supplied tree ---
    if not os.path.isdir("/app/data"):
        failures.append("visible input tree missing")
    elif not run_case("/app/data", "/tests/expected/visible.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/allocation.json must match ---
    if os.path.isfile("/app/allocation.json"):
        try:
            if norm("/app/allocation.json") != norm("/tests/expected/visible.json"):
                failures.append("allocation.json does not match visible expected")
        except Exception:
            failures.append("allocation.json unreadable")
    else:
        failures.append("missing /app/allocation.json")

    # --- hidden cases: genuinely distinct fixture trees ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            inp = os.path.join(base, "input")
            exp = os.path.join(base, "expected.json")
            if not os.path.isdir(inp) or not os.path.isfile(exp):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(inp, exp):
                failures.append("hidden case '%s' failed" % c)
    else:
        failures.append("no hidden cases")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
