#!/bin/bash
# Verifier for hazel-quay: checks the visible-case deliverables are present and
# correct, ENFORCES the no-modify rule on the supplied /app inputs, and EXECUTES
# the deliverable program (/app/solve.py) on the visible case and on every hidden
# case in /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction tells
# the agent not to modify these; tampering defeats the visible-case check).
PRISTINE_ITEMS_SHA="dcab7276929a20bee24b070915c9c5220f49f6ab33f2d6d5196837c7ff2a621a"
PRISTINE_RETURNS_SHA="7dc88ff55ad98b768ceac647ee57ede51fa9867cfd3507ef6616ff1e33f40287"
PRISTINE_PERIOD_SHA="f774e147df30668740631d44a5d003af04d9a675052900a0301b50e9f15cb24c"

no_modify_broken=0
for spec in "lineitems.csv:$PRISTINE_ITEMS_SHA" "returns.csv:$PRISTINE_RETURNS_SHA" "period.txt:$PRISTINE_PERIOD_SHA"; do
    f="/app/${spec%%:*}"
    want="${spec#*:}"
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

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])

TOP_KEYS = {"period", "total_gross", "total_returned", "total_net",
            "orders_in_range", "malformed_line_items", "malformed_returns",
            "unmatched_returns", "products", "top_products"}
PROD_KEYS = {"units_gross", "gross", "returned", "net", "units_net"}


def norm(obj):
    """Normalize so money floats compare at 2 decimals and dicts by content."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == TOP_KEYS, sorted(obj.keys())
    period = obj["period"]
    assert isinstance(period, dict) and set(period) == {"from", "to"}, period
    out = {"period": {"from": str(period["from"]), "to": str(period["to"])}}
    for k in ("total_gross", "total_returned", "total_net"):
        v = obj[k]
        assert isinstance(v, (int, float)), (k, v)
        out[k] = round(float(v), 2)
    for k in ("orders_in_range", "malformed_line_items", "malformed_returns",
              "unmatched_returns"):
        out[k] = int(obj[k])
    products = obj["products"]
    assert isinstance(products, dict), products
    norm_p = {}
    for pid, v in products.items():
        assert isinstance(v, dict) and set(v) == PROD_KEYS, (pid, v)
        norm_p[pid] = {
            "units_gross": int(v["units_gross"]),
            "gross": round(float(v["gross"]), 2),
            "returned": round(float(v["returned"]), 2),
            "net": round(float(v["net"]), 2),
            "units_net": int(v["units_net"]),
        }
    out["products"] = norm_p
    top = obj["top_products"]
    assert isinstance(top, list) and all(isinstance(x, str) for x in top), top
    out["top_products"] = list(top)
    return out


def run_case(items, returns, period, expected_path):
    out = "/tmp/hazel_quay_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run(
        [sys.executable, SOLVE, items, returns, period, out],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        return norm(got) == norm(want)
    except Exception:
        return False


failures = []
if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible case: EXECUTE solve.py on the live supplied inputs ---
    if not all(os.path.isfile("/app/" + n) for n in
               ("lineitems.csv", "returns.csv", "period.txt")):
        failures.append("visible inputs missing")
    elif not run_case("/app/lineitems.csv", "/app/returns.csv",
                      "/app/period.txt", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/answer.json must exist and match ---
    if os.path.isfile("/app/answer.json"):
        try:
            with open("/app/answer.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("answer.json does not match visible expected")
        except Exception:
            failures.append("answer.json unreadable")
    else:
        failures.append("missing /app/answer.json")

    # --- hidden cases: GENUINELY distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            files = [os.path.join(base, n) for n in
                     ("lineitems.csv", "returns.csv", "period.txt")]
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in files + [exp]):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(files[0], files[1], files[2], exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
