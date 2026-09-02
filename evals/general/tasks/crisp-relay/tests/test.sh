#!/bin/bash
# Verifier for crisp-relay: guards the immutable fixtures, enforces that the
# pinned torch/transformers toolchain survived, EXECUTES the deliverable
# installer (/app/install_vendor.sh) and scorer (/app/score.py) on the visible
# case and on every hidden case, and checks /app/scores.json. Writes REWARD
# (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of supplied fixtures the instruction forbids modifying.
PRISTINE_MODEL_SHA="ac2ffc9b69cdcd7c18d69d511deb0629972d6a884c69f8576d7579265564f907"
PRISTINE_INBOX_SHA="590cb2edb82256cccff1b36c812c3bff1cc119e4536b17dcf68c0809c0e69bec"
PRISTINE_REQS_SHA="cc65a529ac6870265395b558274dd2eb6fe966e7a6555ef2945b51fb3e211548"

guard_fail=0
check_sha() {
    local path="$1" want="$2" name="$3"
    if [ ! -f "$path" ]; then
        echo "no-modify: $name missing" >&2
        guard_fail=1
        return
    fi
    local got
    got="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$got" != "$want" ]; then
        echo "no-modify: $name was modified" >&2
        guard_fail=1
    fi
}
check_sha /app/model_store/model.safetensors "$PRISTINE_MODEL_SHA" "/app/model_store/model.safetensors"
check_sha /app/inbox.txt "$PRISTINE_INBOX_SHA" "/app/inbox.txt"
check_sha /app/vendor/requirements.txt "$PRISTINE_REQS_SHA" "/app/vendor/requirements.txt"

python3 - "$guard_fail" <<'PY'
import json, os, subprocess, sys

INSTALLER = "/app/install_vendor.sh"
SCORER = "/app/score.py"
SCORES = "/app/scores.json"
PINNED_TORCH = "2.13.0+cpu"
PINNED_TF = "5.16.1"
failures = []

if int(sys.argv[1]):
    failures.append("supplied fixtures were modified or missing")


def norm_answer(obj):
    try:
        assert isinstance(obj, dict), "not an object"
        assert set(obj.keys()) == {"count", "labels"}, obj.keys()
        labels = obj["labels"]
        count = obj["count"]
        assert isinstance(labels, list) and isinstance(count, int), (count, labels)
        assert count == len(labels), (count, labels)
        norm = [int(x) for x in labels]
        assert all(x in (0, 1) for x in norm), labels
        return (count, norm)
    except Exception as e:
        raise AssertionError(f"malformed answer: {obj!r} ({e})")


def run_scorer(inp, out):
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, SCORER, inp, out],
                           capture_output=True, text=True, timeout=240)
    except Exception as e:
        return False, f"scorer crashed: {e}"
    if r.returncode != 0:
        return False, f"scorer rc={r.returncode}: {r.stderr[-400:]}"
    if not os.path.exists(out):
        return False, "scorer wrote no output"
    return True, ""


def run_case(inp, expected_path, tag):
    out = "/tmp/crisp_relay_case.json"
    ok, why = run_scorer(inp, out)
    if not ok:
        failures.append(f"{tag}: {why}")
        return
    try:
        with open(out) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        if norm_answer(got) != norm_answer(want):
            failures.append(f"{tag}: labels/count mismatch")
    except Exception as e:
        failures.append(f"{tag}: {e}")


# --- 1. pinned toolchain must be intact BEFORE anything runs ---
try:
    code = ("import torch, transformers; print(torch.__version__ + '|' + "
            "transformers.__version__)")
    r = subprocess.run([sys.executable, "-c", code],
                       capture_output=True, text=True, timeout=120)
    versions = r.stdout.strip().split("|")
    if r.returncode != 0 or len(versions) != 2:
        failures.append("cannot read toolchain versions")
    else:
        if versions[0] != PINNED_TORCH:
            failures.append(f"torch altered: {versions[0]!r} != {PINNED_TORCH!r}")
        if versions[1] != PINNED_TF:
            failures.append(f"transformers altered: {versions[1]!r} != {PINNED_TF!r}")
except Exception as e:
    failures.append(f"toolchain check failed: {e}")

# --- 2. EXECUTE the installer deliverable, twice (idempotence) ---
if not os.path.isfile(INSTALLER):
    failures.append("missing /app/install_vendor.sh")
else:
    for i in (1, 2):
        try:
            r = subprocess.run(["bash", INSTALLER], capture_output=True,
                               text=True, timeout=240)
            if r.returncode != 0:
                failures.append(f"install_vendor.sh run {i} failed: "
                                f"{r.stderr[-300:]}")
        except Exception as e:
            failures.append(f"install_vendor.sh run {i} crashed: {e}")

# --- 3. vendor libs present, correct versions, correct behavior; and the
#        toolchain must STILL be intact after the installer ran ---
try:
    code = (
        "import toksplit, textnorm, torch, transformers\n"
        "assert toksplit.__version__ == '0.5.2', toksplit.__version__\n"
        "assert textnorm.__version__ == '1.3.0', textnorm.__version__\n"
        "assert textnorm.normalize('  a\\n\\nb  ') == 'a b', "
        "textnorm.normalize('  a\\n\\nb  ')\n"
        "assert toksplit.tokenize('A-b! c') == ['a', 'b', 'c'], "
        "toksplit.tokenize('A-b! c')\n"
        "assert torch.__version__ == '2.13.0+cpu', torch.__version__\n"
        "assert transformers.__version__ == '5.16.1', transformers.__version__\n"
    )
    r = subprocess.run([sys.executable, "-c", code],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        failures.append("vendor/toolchain post-install check failed: "
                        f"{r.stderr.strip()[-400:]}")
except Exception as e:
    failures.append(f"post-install check crashed: {e}")

# --- 4. EXECUTE the scorer deliverable on the visible inbox ---
if not os.path.isfile(SCORER):
    failures.append("missing /app/score.py")
else:
    run_case("/app/inbox.txt", "/tests/expected.json", "visible rerun")

# --- 5. visible-case deliverable /app/scores.json must match ---
if os.path.isfile(SCORES):
    try:
        with open(SCORES) as f:
            got = json.load(f)
        with open("/tests/expected.json") as f:
            want = json.load(f)
        if norm_answer(got) != norm_answer(want):
            failures.append("scores.json does not match visible expected")
    except Exception as e:
        failures.append(f"scores.json unreadable: {e}")
else:
    failures.append("missing /app/scores.json")

# --- 6. hidden cases: genuinely distinct inputs, each executed via score.py ---
hidden_dir = "/tests/hidden"
if os.path.isdir(hidden_dir):
    cases = sorted(os.listdir(hidden_dir))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        inp = os.path.join(base, "input.txt")
        exp = os.path.join(base, "expected.json")
        if not (os.path.isfile(inp) and os.path.isfile(exp)):
            failures.append(f"hidden '{c}' malformed")
            continue
        run_case(inp, exp, f"hidden '{c}'")
else:
    failures.append("hidden dir missing")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
