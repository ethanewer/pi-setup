#!/bin/bash
# Verifier for opal-summit: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app inputs, and
# EXECUTES the deliverable program (/app/solve.py) on the visible case and on
# every hidden case in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures (the instruction tells the
# agent not to modify them; tampering defeats the visible-case check).
PRISTINE_ORDERS_SHA="54b3c549135cf986e2f97bb762d7e8cba0ff798a24d53bd7e1ced82c6a516ffe"
PRISTINE_PRODUCTS_SHA="b34efcb31e63b7c53ea785174fbcc3a42d30fafacc236162cad0430ecfbe3151"
PRISTINE_PERIOD_SHA="31ea51049267fc8a99312e808962c37d6f97d7b8b49a5c10ec4e62d6e7005967"

no_modify_broken=0
check_sha() {
    local path="$1" want="$2" name="$3"
    if [ ! -f "$path" ]; then
        echo "no-modify: $name missing" >&2
        no_modify_broken=1
        return
    fi
    local actual
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $name was modified" >&2
        no_modify_broken=1
    fi
}
check_sha /app/orders.csv   "$PRISTINE_ORDERS_SHA"   /app/orders.csv
check_sha /app/products.csv "$PRISTINE_PRODUCTS_SHA" /app/products.csv
check_sha /app/period.txt   "$PRISTINE_PERIOD_SHA"   /app/period.txt

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])

PROD_KEYS = ["product_id", "product_name", "category",
             "units", "orders", "revenue"]
TOP_KEYS = ["period", "products", "top_products", "total_revenue"]


def norm(obj):
    """Normalize a report for comparison; guard every parse."""
    assert isinstance(obj, dict), "report is not a JSON object"
    assert list(obj.keys()) == TOP_KEYS, obj.keys()
    period = obj["period"]
    assert isinstance(period, dict) and list(period.keys()) == ["from", "to"], period
    assert isinstance(period["from"], str) and isinstance(period["to"], str)
    products = obj["products"]
    assert isinstance(products, list), products
    normed_products = []
    for p in products:
        assert isinstance(p, dict) and list(p.keys()) == PROD_KEYS, p
        assert isinstance(p["product_id"], str)
        assert isinstance(p["product_name"], str)
        assert isinstance(p["category"], str)
        units = p["units"]
        orders = p["orders"]
        assert isinstance(units, int), units
        assert isinstance(orders, int), orders
        rev = p["revenue"]
        assert isinstance(rev, (int, float)) and not isinstance(rev, bool), rev
        normed_products.append((p["product_id"], p["product_name"],
                                p["category"], units, orders,
                                round(float(rev), 2)))
    top = obj["top_products"]
    assert isinstance(top, list) and all(isinstance(t, str) for t in top), top
    total = obj["total_revenue"]
    assert isinstance(total, (int, float)) and not isinstance(total, bool), total
    return (period["from"], period["to"], normed_products, top,
            round(float(total), 2))


def run_case(orders, products, period, expected_path):
    out = "/tmp/opal_summit_verify_out.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, orders, products, period, out],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return False
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
    if not all(os.path.isfile(p) for p in
               ("/app/orders.csv", "/app/products.csv", "/app/period.txt")):
        failures.append("visible inputs missing")
    elif not run_case("/app/orders.csv", "/app/products.csv",
                      "/app/period.txt", "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/report.json must exist and match ---
    if os.path.isfile("/app/report.json"):
        try:
            with open("/app/report.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("report.json does not match visible expected")
        except Exception:
            failures.append("report.json unreadable")
    else:
        failures.append("missing /app/report.json")

    # --- hidden cases: GENUINELY distinct inputs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            orders = os.path.join(base, "orders.csv")
            products = os.path.join(base, "products.csv")
            period = os.path.join(base, "period.txt")
            exp = os.path.join(base, "expected.json")
            if not all(os.path.isfile(p) for p in
                       (orders, products, period, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(orders, products, period, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
