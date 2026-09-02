#!/bin/bash
# Verifier for tide-ember: checks the visible-case deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app inputs, and EXECUTES
# the deliverable program (/app/flux_select.py) on the visible case and on every
# hidden case in /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction tells
# the agent not to modify these; tampering defeats the visible-case check).
PRISTINE_UNITS_SHA="9af5cf265cb3ddd19a803414a6b95ce03219ab40047b8f48406531e103c30019"
PRISTINE_INSTR_SHA="69d15bfd483136b419d3c9570193b5a1636fc7011e4fa3a0c435656bc82860df"
PRISTINE_TARGET_SHA="373728676262c4bdb437f5a25124976fb85faed591ebfd6ab69051e8dd4b11a2"

no_modify_broken=0
for pair in "/app/units.json:$PRISTINE_UNITS_SHA" \
            "/app/instruments.json:$PRISTINE_INSTR_SHA" \
            "/app/target.json:$PRISTINE_TARGET_SHA"; do
    f="${pair%%:*}"; want="${pair##*:}"
    if [ ! -f "$f" ]; then
        echo "no-modify: $f missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$f" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $f was modified" >&2
            no_modify_broken=1
        fi
    fi
done
export no_modify_broken
cd /tmp
python3 - <<'PY'
import hashlib, json, os, subprocess, sys

SOLVE = "/app/flux_select.py"
no_modify_broken = int(os.environ["no_modify_broken"])

# Pristine sha256 of every visible source catalog (no-modify rule).
PRISTINE_SOURCES = {}  # filled from /tests/pristine_sources.json if present
pmap = "/tests/pristine_sources.json"
if os.path.isfile(pmap):
    PRISTINE_SOURCES = json.load(open(pmap))
src_dir = "/app/sources"
if os.path.isdir(src_dir):
    for name in sorted(os.listdir(src_dir)):
        path = os.path.join(src_dir, name)
        if not os.path.isfile(path):
            continue
        h = hashlib.sha256(open(path, "rb").read()).hexdigest()
        if name not in PRISTINE_SOURCES or PRISTINE_SOURCES[name] != h:
            print("no-modify: sources/%s was modified or unrecognized" % name,
                  file=sys.stderr)
            no_modify_broken = 1
else:
    no_modify_broken = 1


def eq(a, b, where):
    if isinstance(a, float) and isinstance(b, float):
        if abs(a - b) > 1e-9:
            raise AssertionError("float mismatch at %s: %r vs %r" % (where, a, b))
        return
    if isinstance(a, dict) and isinstance(b, dict):
        assert set(a.keys()) == set(b.keys()), \
            "key mismatch at %s: %r vs %r" % (where, sorted(a), sorted(b))
        for k in a:
            eq(a[k], b[k], where + "." + str(k))
        return
    if isinstance(a, list) and isinstance(b, list):
        assert len(a) == len(b), \
            "length mismatch at %s: %d vs %d" % (where, len(a), len(b))
        for i, (x, y) in enumerate(zip(a, b)):
            eq(x, y, where + "[%d]" % i)
        return
    assert a == b, "value mismatch at %s: %r vs %r" % (where, a, b)


def run_case(sources, units, insts, target, expected_path):
    out = "/tmp/tide_ember_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, sources, units, insts, target, out],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return False
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out, encoding="utf-8") as fh:
            got = json.load(fh)
        with open(expected_path, encoding="utf-8") as fh:
            want = json.load(fh)
        assert isinstance(got, list), "output is not a JSON array"
        eq(got, want, "root")
        return True
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/flux_select.py")
else:
    # --- visible case: EXECUTE flux_select.py on the live supplied inputs ---
    if not (os.path.isdir("/app/sources") and os.path.isfile("/app/units.json")
            and os.path.isfile("/app/instruments.json")
            and os.path.isfile("/app/target.json")):
        failures.append("visible inputs missing")
    elif not run_case("/app/sources", "/app/units.json", "/app/instruments.json",
                      "/app/target.json", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/ranked.json must match expected ---
    if os.path.isfile("/app/ranked.json"):
        try:
            with open("/app/ranked.json", encoding="utf-8") as fh:
                got = json.load(fh)
            with open("/tests/expected.json", encoding="utf-8") as fh:
                want = json.load(fh)
            eq(got, want, "ranked")
        except Exception:
            failures.append("ranked.json does not match visible expected")
    else:
        failures.append("missing /app/ranked.json")

    # --- hidden cases: GENUINELY distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            sources = os.path.join(base, "sources")
            units = os.path.join(base, "units.json")
            insts = os.path.join(base, "instruments.json")
            target = os.path.join(base, "target.json")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isdir(sources) and all(os.path.isfile(p) for p in
                    (units, insts, target, exp))):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(sources, units, insts, target, exp):
                failures.append("hidden case '%s' failed" % c)
    else:
        failures.append("no hidden cases")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
