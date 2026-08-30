#!/bin/bash
# Verifier for tasks/vine-inlet (executes-deliverable).
#
# The agent's deliverables are:
#   /app/env/.venv          hedge venv with pip repaired and lotusfields
#                           upgraded 0.7.0 -> 0.9.0, coreclutch importable
#   /app/pinned.txt         exact two-line lock of the frozen top-level
#                           python packages in that venv
#   /app/node/package.json  react-family downgraded, aws untouched, name sets
#                           preserved
# It checks every deliverable, including executing the repaired venv
# interpreter (via the shipped /app/tools/probe.py) on every hidden CSV under
# /tests/hidden. Input references are recomputed independently (the verifier
# sums the CSV columns itself, never lotusfields), so it does not trust the
# deliverable.
set -u
mkdir -p /logs/verifier
failures=()

VENVPY=/app/env/.venv/bin/python
HALL=/tests/hidden

# ==========================================================================
# 1) the venv interpreter exists and pip is repaired
# ==========================================================================
if [ ! -x "$VENVPY" ]; then
    echo "missing deliverable /app/env/.venv/bin/python" >&2
    echo "0" > /logs/verifier/reward.txt; exit 0
fi
if ! "$VENVPY" -m pip --version >/dev/null 2>&1; then
    failures+=("pip is still broken (python -m pip --version fails)")
fi

# ==========================================================================
# 2) lotusfields upgraded and coreclutch importable
# ==========================================================================
lv=$("$VENVPY" -c 'import lotusfields as l; print(l.__version__)' 2>/dev/null || true)
if [ "$lv" != "0.9.0" ]; then
    failures+=("lotusfields version is '$lv', expected 0.9.0")
fi
if ! "$VENVPY" -c "import coreclutch" 2>/dev/null; then
    failures+=("coreclutch not importable in the venv")
fi

# ==========================================================================
# 3) hidden probe scenarios (independent recompute)
# ==========================================================================
parse_errs=$("$VENVPY" - "$HALL" <<'PYEOF'
import csv, json, os, subprocess, sys
HALL = sys.argv[1] if len(sys.argv) > 1 else "/tests/hidden"
issues = []

def probe(csv_path):
    return subprocess.run(["/app/env/.venv/bin/python", "/app/tools/probe.py", csv_path],
                          capture_output=True, text=True)

def compute_valid(path):
    with open(path, newline="") as fh:
        rows = list(csv.DictReader(fh))
    total = round(sum(float(r["flux"]) for r in rows), 3)
    zones = sorted({r["zone"].strip() for r in rows})
    return {"rows": len(rows), "total_flux": total, "zones": zones}

for base in ("lake", "area"):
    csvp = os.path.join(HALL, "parser", "valid", base + ".csv")
    with open(os.path.join(HALL, "parser", "valid", base + ".expected.json")) as fh:
        want = json.load(fh)
    r = probe(csvp)
    if r.returncode != 0:
        issues.append("[%s] probe rc=%d %s" % (base, r.returncode, r.stderr[-150:]))
        continue
    try:
        got = json.loads(r.stdout)
    except Exception as exc:
        issues.append("[%s] non-JSON output %r" % (base, exc))
        continue
    ref = compute_valid(csvp)
    if got.get("ok") is not True:
        issues.append("[%s] ok not true: %s" % (base, got)); continue
    if got.get("rows") != want.get("rows"):
        issues.append("[%s] rows %r want %r" % (base, got.get("rows"), want.get("rows")))
    gf = float(got.get("total_flux", "nan")); wf = float(want.get("total_flux"))
    if abs(gf - wf) > 1e-9:
        issues.append("[%s] total_flux %r want %r" % (base, got.get("total_flux"), want.get("total_flux")))
    if got.get("zones") != want.get("zones"):
        issues.append("[%s] zones %r want %r" % (base, got.get("zones"), want.get("zones")))
    if got.get("rows") != ref["rows"] or abs(gf - float(ref["total_flux"])) > 1e-9 \
       or got.get("zones") != ref["zones"]:
        issues.append("[%s] result differs from independent recompute" % base)

edges = {
    "empty":       ("empty-data", 422, 4),
    "missing_col": ("missing-columns:flux", 422, 4),
    "nonnumeric":  ("non-numeric-flux:row-1", 422, 4),
}
for name, (errkey, code, rc) in edges.items():
    csvp = os.path.join(HALL, "parser", "edge", name + ".csv")
    r = probe(csvp)
    if r.returncode != rc:
        issues.append("[edge-%s] rc=%d want %d" % (name, r.returncode, rc)); continue
    try:
        got = json.loads(r.stdout)
    except Exception as exc:
        issues.append("[edge-%s] non-JSON %r" % (name, exc)); continue
    if got.get("error") != errkey:
        issues.append("[edge-%s] error=%r want %r" % (name, got.get("error"), errkey))
    if got.get("code") != code:
        issues.append("[edge-%s] code=%r want %r" % (name, got.get("code"), code))

print("\n".join(issues))
sys.exit(1 if issues else 0)
PYEOF
)
if [ -n "$parse_errs" ]; then
    while IFS= read -r line; do failures+=("$line"); done <<< "$parse_errs"
fi

# ==========================================================================
# 4) /app/pinned.txt is exactly the two frozen pins and matches the venv
# ==========================================================================
if [ ! -f /app/pinned.txt ]; then
    failures+=("pinned.txt missing")
else
    lines=$(sed -e 's/[[:space:]]*$//' /app/pinned.txt | grep -v '^[[:space:]]*$' | tr '\n' ' ' | sed 's/ *$//')
    want="lotusfields==0.9.0 coreclutch==0.5.0"
    if [ "$lines" != "$want" ]; then
        failures+=("pinned.txt = '$lines', want '$want'")
    fi
    cv=$("$VENVPY" -c 'import coreclutch as c; print(c.__version__)' 2>/dev/null || true)
    if [ "$lv$cv" != "0.9.00.5.0" ]; then
        failures+=("installed versions (lotus=$lv, core=$cv) do not match pinned.txt")
    fi
fi

# ==========================================================================
# 5) /app/node/package.json -- executed and checked by python
# ==========================================================================
node_errs=$("$VENVPY" - <<'PYEOF'
import json, sys
issues = []
path = "/app/node/package.json"
try:
    with open(path) as fh:
        d = json.load(fh)
except Exception as exc:
    print("package.json unreadable: %r" % exc)
    sys.exit(1)

deps_orig = {"@aws-amplify/lambda", "aws-amplify", "react", "react-dom"}
dev_orig  = {"@aws-sdk/client-s3", "@hedge/gauge-ribbon", "@hedge/rivette-core",
             "aws-sdk", "react-native"}
deps = set(d.get("dependencies", {}))
dev  = set(d.get("devDependencies", {}))
if deps != deps_orig:
    issues.append("dependencies name-set changed")
if dev != dev_orig:
    issues.append("devDependencies name-set changed")

if d["dependencies"].get("react") != "18.2.0":
    issues.append("react != 18.2.0")
if d["dependencies"].get("react-dom") != "18.2.0":
    issues.append("react-dom != 18.2.0")
if d["devDependencies"].get("react-native") != "0.72.1":
    issues.append("react-native != 0.72.1")

frozen = {
    "@aws-amplify/lambda": "2.8.7", "aws-amplify": "6.7.0",
    "@aws-sdk/client-s3": "3.700.0", "aws-sdk": "3.650.0",
    "@hedge/gauge-ribbon": "2.4.1", "@hedge/rivette-core": "1.9.0",
}
def look(key):
    return d.get("dependencies", {}).get(key) or d.get("devDependencies", {}).get(key)
for k, want in frozen.items():
    got = look(k)
    if got != want:
        issues.append("non-react dep %s changed: got %r want %r" % (k, got, want))

orig = dict(frozen)
orig.update({"react": "19.5.0", "react-dom": "19.5.0", "react-native": "0.77.5"})
def ver(x):
    parts = str(x).split(".")
    return tuple(int(p) for p in parts)
for k, ov in orig.items():
    nv = look(k)
    if nv is not None and ver(nv) > ver(ov):
        issues.append("%s was RAISED (got %r, was %r)" % (k, nv, ov))

print("\n".join(issues))
sys.exit(1 if issues else 0)
PYEOF
)
if [ -n "$node_errs" ]; then
    failures+=("package.json: $node_errs")
fi

if [ ${#failures[@]} -gt 0 ]; then
    echo "FAILURES:"
    for m in "${failures[@]}"; do
        echo "  - $m"
    done
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

echo "ALL PASS"
echo "1" > /logs/verifier/reward.txt
exit 0