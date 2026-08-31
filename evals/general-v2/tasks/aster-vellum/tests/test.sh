#!/bin/bash
# Verifier for aster-vellum: enforces the no-modify rule on the seeded package
# files, then EXECUTES the deliverable (/app/pkg/src/dotkit/__init__.py) by
# importing the dotkit package in two modes (source tree, offline install) and
# running a visible case plus every hidden case in /tests/hidden/cases.json.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier

# Pristine sha256 of the seeded files the agent must not modify.
PRISTINE_PYPROJECT_SHA="a747d6db21262f2e934a676888623199e3e094fb3a5cbf64044f340166b10fab"
PRISTINE_README_SHA="e9d284fa97cbab6022271dc12269f64b60dbb56e9854af164630b9e3caf53e21"
PRISTINE_VECTOR_SHA="a5cc8b3b2d368536c99f924c1d56ba0daaa15f97142b34a6cd7b69865bee1899"

protected_broken=0
check_sha() {
    path="$1"; want="$2"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        protected_broken=1
        return
    fi
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $path was modified" >&2
        protected_broken=1
    fi
}
check_sha /app/pkg/pyproject.toml "$PRISTINE_PYPROJECT_SHA"
check_sha /app/pkg/README.md "$PRISTINE_README_SHA"
check_sha /app/pkg/src/dotkit/vector.py "$PRISTINE_VECTOR_SHA"

# Fresh copy of the source tree so stray work files cannot interfere.
rm -rf /tmp/dk_src_mode /tmp/dk_inst_mode /tmp/dk_pip.log
mkdir -p /tmp/dk_src_mode
cp -r /app/pkg/src/dotkit /tmp/dk_src_mode/

python3 -m pip install --no-build-isolation --no-deps --quiet \
    --target /tmp/dk_inst_mode /app/pkg > /tmp/dk_pip.log 2>&1
pip_status=$?
if [ "$pip_status" -ne 0 ]; then
    echo "verify: offline pip install of /app/pkg failed" >&2
    tail -5 /tmp/dk_pip.log >&2 || true
fi

cat > /tmp/dk_runner.py <<'PY'
import json, sys

sys.path.insert(0, sys.argv[1])
import dotkit

cases = json.load(open(sys.argv[2]))
out = {"module": getattr(dotkit.dot_product, "__module__", None), "results": []}
for c in cases:
    a, b = c["a"], c["b"]
    wrap = c.get("wrap")
    if wrap == "tuple":
        a, b = tuple(a), tuple(b)
    elif wrap == "gen":
        a, b = iter(a), iter(b)
    try:
        v = dotkit.dot_product(a, b)
        out["results"].append(
            {"name": c["name"], "ok": True,
             "type": type(v).__name__, "value": v}
        )
    except Exception as e:  # noqa: BLE001
        out["results"].append(
            {"name": c["name"], "ok": False, "etype": type(e).__name__}
        )
json.dump(out, open(sys.argv[3], "w"))
PY

cat > /tmp/dk_checker.py <<'PY'
import json, sys

with open(sys.argv[1]) as fh:
    got = json.load(fh)
with open(sys.argv[2]) as fh:
    cases = json.load(fh)

if got.get("module") != "dotkit":
    print("module check failed: dot_product.__module__=%r" % (got.get("module"),))
    sys.exit(1)

by_name = {}
for r in got.get("results", []):
    by_name[r["name"]] = r
if len(by_name) != len(cases):
    print("runner did not evaluate every case")
    sys.exit(1)

for c in cases:
    r = by_name.get(c["name"])
    if r is None:
        print("missing result for case %s" % c["name"])
        sys.exit(1)
    if "error" in c:
        if r.get("ok") or r.get("etype") != c["error"]:
            print("case %s: expected %s, got %r" % (c["name"], c["error"], r))
            sys.exit(1)
        continue
    if not r.get("ok"):
        print("case %s: unexpected error %r" % (c["name"], r))
        sys.exit(1)
    want = c["expect"]
    want_type = "int" if isinstance(want, int) and not isinstance(want, bool) else "float"
    if r.get("type") != want_type:
        print("case %s: wanted %s, got %s (%r)"
              % (c["name"], want_type, r.get("type"), r.get("value")))
        sys.exit(1)
    value = r.get("value")
    if want_type == "int":
        if value != want:
            print("case %s: wanted %r, got %r" % (c["name"], want, value))
            sys.exit(1)
    else:
        tol = 1e-9 * max(1.0, abs(want))
        if not isinstance(value, float) or abs(value - want) > tol:
            print("case %s: wanted %r, got %r" % (c["name"], want, value))
            sys.exit(1)
print("all cases OK")
PY

# Visible cases (not hidden artifacts): exercised in both modes.
cat > /tmp/dk_visible_cases.json <<'JSON'
[
  {"name": "vis_ints", "a": [1, 2, 3], "b": [4, 5, 6], "expect": 32},
  {"name": "vis_empty", "a": [], "b": [], "expect": 0},
  {"name": "vis_float", "a": [1.5, 2.5], "b": [2.0, 4.0], "expect": 13.0},
  {"name": "vis_mismatch", "a": [1, 2], "b": [1], "error": "ValueError"}
]
JSON

reward=1
run_and_check() {
    # $1 = mode root, $2 = cases json, $3 = result out, $4 = label
    python3 /tmp/dk_runner.py "$1" "$2" "$3" || return 1
    python3 /tmp/dk_checker.py "$3" "$2" || return 1
    return 0
}

if [ "$protected_broken" -ne 0 ] \
   || [ ! -f /app/pkg/src/dotkit/__init__.py ] \
   || [ "$pip_status" -ne 0 ] \
   || [ ! -d /tmp/dk_inst_mode/dotkit ]; then
    echo "verify: precondition failed (modified files / missing deliverable / install)" >&2
    reward=0
else
    for mode in src inst; do
        if [ "$mode" = "src" ]; then root=/tmp/dk_src_mode; else root=/tmp/dk_inst_mode; fi
        if ! run_and_check "$root" /tmp/dk_visible_cases.json \
             "/tmp/dk_vis_$mode.json" "$mode"; then
            echo "verify: visible case failed ($mode mode)" >&2
            reward=0
        fi
        if ! run_and_check "$root" /tests/hidden/cases.json \
             "/tmp/dk_hid_$mode.json" "$mode"; then
            echo "verify: hidden cases failed ($mode mode)" >&2
            reward=0
        fi
    done
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0
