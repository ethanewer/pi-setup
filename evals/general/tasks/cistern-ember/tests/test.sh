#!/bin/bash
# Verifier for cistern-ember (real-upstream debugging task: unclosed async
# generators in jinja2's async streaming path). Checks, in order:
#   1. the declared deliverable /app/diagnosis.md exists and names the real
#      area and cause (not a placeholder),
#   2. /app/src is the real jinja2 tree,
#   3. byte-level provenance: every file under /app/src is still
#      byte-identical to the pristine parent checkout EXCEPT in exactly the
#      three modules the fix requires (async_utils.py, compiler.py,
#      environment.py); no new files, no deletions, no test-file edits,
#   4. the project's OWN regression test for this bug (extracted at image
#      build time from the upstream fix commit into /opt/golden, copied into
#      the tree's tests/ dir so pytest applies the project's own warning
#      config) passes for the four streaming scenarios, under both friends of
#      runners the project uses,
#   5. the project's OWN full test suite passes in the repaired tree,
#   6. every authored hidden generalisation case in /tests/hidden/*/run.py
#      passes (fresh inputs, same code path).
# Reward is binary and written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
failures=0

# ---- 1. deliverable: /app/diagnosis.md --------------------------------------
if [ ! -f /app/diagnosis.md ]; then
    echo "FAIL: deliverable /app/diagnosis.md missing" >&2
    failures=1
else
    python3 - /app/diagnosis.md <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
low = text.lower()
ok = (len(text.strip()) >= 100
      and "async" in low
      and any(k in low for k in ("generator", "aclose", "auto_aiter", "aiter"))
      and any(k in low for k in ("compiler", "environment", "compile", "generate_async")))
if not ok:
    print(f"FAIL: /app/diagnosis.md does not name the real area and cause "
          f"(len={len(text.strip())}, async={'async' in low}, "
          f"generator/aclose={any(k in low for k in ('generator','aclose','auto_aiter','aiter'))}, "
          f"compiler/environment={any(k in low for k in ('compiler','environment','compile','generate_async'))})",
          file=sys.stderr)
    sys.exit(1)
print("diagnosis: acceptable (names area + cause)")
PY
    rc=$?
    if [ $rc -ne 0 ]; then
        failures=1
    fi
fi

# ---- 2. this must be the real upstream clone --------------------------------
if [ ! -f /app/src/pyproject.toml ] || [ ! -d /app/src/src/jinja2 ] || \
   [ ! -f /app/src/tests/test_async.py ]; then
    echo "FAIL: /app/src is not the jinja2 source tree" >&2
    failures=1
fi

# ---- 3. provenance: byte-identical to the pristine parent tree --------------
#      except in exactly the modules the fix needs; no new or deleted files.
python3 - <<'PY'
import hashlib
import os
import sys

ROOT = "/app/src"
MANIFEST = "/opt/golden/manifest.sha256"
ALLOWED = {
    "src/jinja2/async_utils.py",
    "src/jinja2/compiler.py",
    "src/jinja2/environment.py",
}
SKIP_DIRS = {"__pycache__", ".pytest_cache", ".git", ".hg", ".svn"}


def current_hashes(root):
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if fn.endswith(".pyc"):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root)
            out[rel] = hashlib.sha256(open(p, "rb").read()).hexdigest()
    return out


expected = {}
for line in open(MANIFEST, encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    h, name = line.split(None, 1)
    if name.startswith("./"):
        name = name[2:]
    expected[name] = h

cur = current_hashes(ROOT)

changed = {n for n in expected if n not in cur or cur[n] != expected[n]}
new = set(cur) - set(expected)

problems = []
for n in sorted(changed - ALLOWED):
    problems.append(f"non-allowed file changed: {n}")
for n in sorted(new):
    problems.append(f"file added that was not in the pristine tree: {n}")
c = sorted(changed & ALLOWED)
print(f"provenance: {len(expected)} files checked, {len(changed)} changed "
      f"({', '.join(c) if c else 'none'}), {len(new)} added")
if problems:
    for p in problems:
        print("FAIL: " + p, file=sys.stderr)
    sys.exit(1)
print("provenance: tree matches the pristine parent checkout apart from the required modules")
PY
rc=$?
if [ $rc -ne 0 ]; then
    failures=1
fi

# ---- 4. the project's OWN regression tests for this bug ---------------------
#      (upstream tests/test_async.py at the fix commit, extracted into
#      /opt/golden at image build time; copied into the tree's tests/ dir so
#      pytest applies the project's own pyproject warning config, exactly as
#      upstream runs it). The four streaming scenarios run under both the
#      asyncio and trio parametrisations; at the buggy parent commit the
#      trio variants fail (ResourceWarning caught by the trio finaliser), so
#      a nop container scores 0 here.
if [ -f /opt/golden/test_async_fix.py ]; then
    cp /opt/golden/test_async_fix.py /app/src/tests/test_async_golden.py
    glog=/tmp/verifier_golden.log
    if (cd /app/src && PYTHONPATH=/app/src/src python3 -m pytest -p no:cacheprovider -q \
        "tests/test_async_golden.py::test_basic_generate_async" \
        "tests/test_async_golden.py::test_include_generate_async" \
        "tests/test_async_golden.py::test_blocks_generate_async" \
        "tests/test_async_golden.py::test_async_extend" > "$glog" 2>&1); then
        echo "golden regression tests: PASS ($(tail -1 "$glog"))"
    else
        echo "FAIL: golden regression tests do not pass" >&2
        tail -12 "$glog" >&2
        failures=1
    fi
else
    echo "FAIL: /opt/golden/test_async_fix.py missing (image broken)" >&2
    failures=1
fi

# ---- 5. the project's own full test suite -----------------------------------
slog=/tmp/verifier_suite.log
if (cd /app/src && PYTHONPATH=/app/src/src python3 -m pytest -p no:cacheprovider -q tests/ > "$slog" 2>&1); then
    echo "jinja2 own tests/ suite: PASS ($(tail -1 "$slog"))"
else
    echo "FAIL: jinja2's own tests/ suite does not pass" >&2
    tail -12 "$slog" >&2
    failures=1
fi

# ---- 6. authored hidden generalisation cases --------------------------------
for case_dir in /tests/hidden/*/; do
    run="$case_dir/run.py"
    if [ -f "$run" ]; then
        hlog=/tmp/verifier_hidden.log
        if PYTHONPATH=/app/src/src python3 "$run" > "$hlog" 2>&1; then
            echo "hidden case $(basename "$case_dir"): PASS"
        else
            echo "FAIL: hidden case $(basename "$case_dir") failed" >&2
            tail -8 "$hlog" >&2
            failures=1
        fi
    fi
done

# ---- reward ----------------------------------------------------------------
if [ $failures -eq 0 ]; then
    echo "VERIFIER: all checks passed, reward=1"
    echo 1 > /logs/verifier/reward.txt
else
    echo "VERIFIER: failures present, reward=0" >&2
    echo 0 > /logs/verifier/reward.txt
fi
exit 0