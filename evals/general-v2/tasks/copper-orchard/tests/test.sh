#!/bin/bash
# copper-orchard verifier: executes the delivered solve.py program on the
# visible input and on every hidden input, and checks the parsed outputs.
set -eu
mkdir -p /logs/verifier
reward=0

if [ ! -f /app/solve.py ]; then
    echo "MISSING /app/solve.py" >&2
    echo "$reward" > /logs/verifier/reward.txt
    exit 0
fi

python3 - <<'PY' && reward=1
import json, os, subprocess, sys

SOL = "/app/solve.py"
TOL = 1e-6


def same(a, b):
    if a is None or b is None:
        return a is None and b is None
    af = float(a)
    bf = float(b)
    return abs(af - bf) <= TOL


def check_case(input_path, want_path):
    got_path = "/tmp/" + os.path.basename(input_path) + ".out.json"
    subprocess.run(
        [sys.executable, SOL, input_path, got_path],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    with open(got_path) as f:
        got = json.load(f)
    with open(want_path) as f:
        want = json.load(f)
    # enforce top-level key order (the documented contract)
    if list(got.keys()) != list(want.keys()):
        raise AssertionError(f"key order mismatch: {list(got.keys())}")
    assert list(got["devices"].keys()) == list(want["devices"].keys()), got["devices"]
    for k, v in want["devices"].items():
        assert k in got["devices"] and same(got["devices"][k], v), (k, got["devices"].get(k), v)
    if want["trimmed_mean"] is None:
        assert got["trimmed_mean"] is None, got["trimmed_mean"]
    else:
        assert same(got["trimmed_mean"], want["trimmed_mean"]), (got["trimmed_mean"], want["trimmed_mean"])
    if want["bootstrap90"] is None:
        assert got["bootstrap90"] is None, got["bootstrap90"]
    else:
        assert same(got["bootstrap90"][0], want["bootstrap90"][0]), got["bootstrap90"]
        assert same(got["bootstrap90"][1], want["bootstrap90"][1]), got["bootstrap90"]
    return got


# 1) Visible case: the delivered answer.json must match, AND the program must
#    re-produce it when run against the pristine visible input.
assert os.path.exists("/app/answer.json"), "missing /app/answer.json"
with open("/app/answer.json") as f:
    answer = json.load(f)
with open("/tests/expected.json") as f:
    vis_expected = json.load(f)
assert list(answer.keys()) == list(vis_expected.keys()), answer.keys()
for k in vis_expected["devices"]:
    assert same(answer["devices"][k], vis_expected["devices"][k])
assert same(answer["trimmed_mean"], vis_expected["trimmed_mean"])
assert same(answer["bootstrap90"][0], vis_expected["bootstrap90"][0])
assert same(answer["bootstrap90"][1], vis_expected["bootstrap90"][1])

check_case("/app/readings.csv", "/tests/expected.json")

# 2) Hidden cases
hidden = "/tests/hidden"
for base in sorted(os.listdir(hidden)):
    if not base.endswith("_input.csv"):
        continue
    case_id = base[: -len("_input.csv")]
    want_path = os.path.join(hidden, case_id + "_expected.json")
    assert os.path.exists(want_path), "no expectation for " + base
    check_case(os.path.join(hidden, base), want_path)

print("ALL CASES PASSED")
PY
echo "$reward" > /logs/verifier/reward.txt