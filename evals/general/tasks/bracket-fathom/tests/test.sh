#!/bin/bash
# Verifier for bracket-fathom: an upstream-clone debugging task on psycopg.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the namedtuple row factory leaks a bare collections.namedtuple ValueError on
# duplicate result column names instead of raising psycopg.errors.DataError.
#
# Review hardening (keeps the original checks, adds four layers):
#   H1. fixture integrity: /opt/golden/ must still be the upstream test file
#       and utils module extracted at image build time (SHA-256 pinned), and
#       no foreign file may appear there. An agent that rewrites the golden
#       test so it passes vacuously now fails the trial.
#   H2. deliverable shape: the change to /app/src/psycopg/psycopg/rows.py
#       must actually contain the fix (added code lines must reference
#       DataError and intercept ValueError). A no-op edit plus a cheerful
#       wrapper around the test commands is no longer a fix.
#   H3. randomized behavioral spot-checks: the verifier itself generates
#       unseen duplicate-name inputs per run and asserts the INSTALLED
#       package raises psycopg.DataError with the required message, and that
#       the non-duplicate path still works. Run with a real interpreter under
#       `-S` (no sitecustomize/.pth interception) and WITHOUT pytest, so a
#       wrapper that forges pytest exit codes cannot fake these, and the
#       inputs cannot be enumerated in advance.
#   H4. evidence the tests actually ran: pytest logs must show real "N passed"
#       lines, so an exit-0 fake that never runs the tests is caught.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=7c9b6bee4ea6d7a4da5ce8e4bed9e4cba0c74012
FIX_SHA=66e4b33fe271780d0bd02f15e94c66d52ed69cba
GOLDEN_DIR=/opt/golden
GOLDEN=$GOLDEN_DIR/test_rows.py
PKG=psycopg/psycopg

# ---- H1: expected SHA-256 of the upstream golden fixtures (extracted from  --
# ---- the fix commit at image build time; immutable upstream bytes).        --
GOLDEN_ROWS_SHA=e9992121a31b9e78c72f6be42d83b6e31142b1bcf96ab407b63cb50a3aaaa062
GOLDEN_UTILS_SHA=d12213d53886d165518a0c76a9dad568dcdc3c1513450f36ce0cbcba2082db16

fail () {
  echo "FAIL: $*" >&2
  reward=0
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "HEAD is not the pinned parent commit $PARENT_SHA"
else
  echo "ok: HEAD is the pinned parent commit"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is unreachable from the working clone"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" \
  | grep -v "^ M $PKG/rows.py$" \
  | grep -Ev '^\?\? .*(__pycache__|\.pyc|\.pytest_cache|/build/|\.egg-info)' \
  || true)
if [ -n "$bad" ]; then
  fail "unexpected working-tree changes (only the minimal source file may be modified):"
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
fi

newpkg=$(printf '%s\n' "$porcelain" | grep '^?? psycopg/psycopg/' || true)
if [ -n "$newpkg" ]; then
  fail "new files were added inside the installed package:"
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
fi

if [ -z "$(git -C "$SRC" diff -- psycopg/psycopg/rows.py 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
fi

# ---------- H2: the tree diff must contain the fix shape ----------------------
echo "== deliverable shape =="
diff_lines=$(git -C "$SRC" diff -- psycopg/psycopg/rows.py 2>/dev/null || true)
# added lines that are not comments:
added_code=$(printf '%s\n' "$diff_lines" | grep -E '^\+[^+#]' || true)
if printf '%s\n' "$added_code" | grep -q 'except ValueError'; then
  echo "ok: diff intercepts the stdlib ValueError"
else
  fail "the rows.py change does not intercept ValueError (expected try/except ValueError re-raising as DataError)"
fi
if printf '%s\n' "$added_code" | grep -q 'DataError'; then
  echo "ok: diff raises a psycopg DataError"
else
  fail "the rows.py change does not raise psycopg DataError anywhere in added code"
fi

# ---------- 1. refresh the installed package from the repaired tree ----------
echo "== refresh the installed package from the repaired tree =="
if python3 -m pip install --force-reinstall --no-deps --no-build-isolation --no-index \
    --root-user-action=ignore \
    "$SRC/psycopg" > /tmp/pip-reinstall.log 2>&1; then
  echo "ok: reinstall from /app/src/psycopg"
else
  fail "pip reinstall from the tree failed"
  tail -25 /tmp/pip-reinstall.log | sed 's/^/    /' >&2
fi

if ( cd /tmp && python3 -c "import psycopg; print(psycopg.__file__)" > /tmp/import-check.out 2>&1 ); then
  if grep -q "site-packages" /tmp/import-check.out; then
    echo "ok: import resolves to the installed package"
  else
    fail "import resolves to $(cat /tmp/import-check.out) instead of site-packages"
  fi
else
  fail "psycopg no longer imports after the reinstall"
  cat /tmp/import-check.out | sed 's/^/    /' >&2
fi

# ---------- H1: golden fixture integrity --------------------------------------
echo "== golden fixture integrity =="
if [ ! -f "$GOLDEN" ]; then
  fail "golden test file missing from the image"
elif ! echo "$GOLDEN_ROWS_SHA  $GOLDEN" | sha256sum -c - > /dev/null 2>&1; then
  fail "golden test_rows.py does not match the upstream byte-for-byte copy (tampered?)"
elif ! echo "$GOLDEN_UTILS_SHA  $GOLDEN_DIR/utils.py" | sha256sum -c - > /dev/null 2>&1; then
  fail "golden utils.py does not match the upstream byte-for-byte copy (tampered?)"
else
  echo "ok: golden files are the pristine upstream copies"
fi
unexpected=$(find "$GOLDEN_DIR" -mindepth 1 -maxdepth 1 \
  ! -name test_rows.py ! -name utils.py ! -name __init__.py \
  ! -name __pycache__ ! -name .pytest_cache ! -name '*.pyc' \
  -print 2>/dev/null | head -5)
if [ -n "$unexpected" ]; then
  fail "unexpected files in /opt/golden (harness-owned fixture must not gain files):"
  printf '%s\n' "$unexpected" | sed 's/^/    /' >&2
fi

# ---------- 2. golden: the project's upstream regression test ----------------
echo "== golden: the upstream regression test for this bug =="
if ( cd /tmp && python3 -m pytest /opt/golden/test_rows.py::test_make_nt_duplicate_names -q \
    > /tmp/golden.out 2>&1 ); then
  if grep -q 'passed' /tmp/golden.out && ! grep -q 'no tests ran' /tmp/golden.out; then
    echo "ok: upstream regression test passes"
  else
    fail "golden pytest log shows no real run (empty suite or fake wrapper?)"
    tail -10 /tmp/golden.out | sed 's/^/    /' >&2
  fi
else
  fail "upstream regression test failed against the repaired tree"
  tail -40 /tmp/golden.out | sed 's/^/    /' >&2
fi

# ---------- H4: the probe must report a psycopg error, not a ValueError ------
echo "== direct repro through the probe =="
(cd /tmp && python3 /app/probe_row_factory.py > /tmp/probe.out 2>&1)
probe_rc=$?
if [ "$probe_rc" -eq 0 ] && grep -q '\[psycopg error: True\]' /tmp/probe.out; then
  echo "ok: probe reports a psycopg error"
else
  fail "probe does not report a psycopg DataError (rc=$probe_rc)"
  cat /tmp/probe.out | sed 's/^/    /' >&2
fi

# ---------- 3. the project's own existing row-factory suite ------------------
echo "== the project's own existing tests/test_rows.py =="
if ( cd "$SRC" && python3 -m pytest tests/test_rows.py -q \
    > /tmp/own.out 2>&1 ); then
  echo "ok: existing row-factory tests pass"
else
  fail "the project's own tests/test_rows.py failed"
  tail -40 /tmp/own.out | sed 's/^/    /' >&2
fi

# ---------- H3: randomized behavioral spot-checks -----------------------------
echo "== randomized behavioral spot-checks (unseen inputs, no pytest) =="
SP=$(python3 -c "import site; print(site.getsitepackages()[0])")
REALPY=$(readlink -f "$(command -v python3)")
h3_code=$(cat <<'PY'
import random
import sys

import psycopg
from psycopg import rows

rng = random.Random(int.from_bytes(__import__("os").urandom(8), "little"))

# byte names that survive the factory's identifier mangling distinctively
pool = [b"id", b"name", b"cat", b"dog", b"x", b"y", b"z", b"aa", b"bb",
        b"q-1", b"q_1", b"r-2", b"r_2", b"f.id", b"f_id"]

def check_dup(names, enc="utf-8"):
    try:
        rows._make_nt(enc, *names)
    except psycopg.DataError as ex:
        msg = str(ex)
        assert "can't create a namedtuple row" in msg, msg
        assert "duplicate field name" in msg, msg
        return
    except Exception as ex:  # noqa: BLE001
        raise AssertionError(
            "duplicate names raised %r instead of psycopg.DataError" % (ex,))
    raise AssertionError("duplicate names were silently accepted")

n_iter = 12
for i in range(n_iter):
    # 1. a duplicate pair buried in a random-length select list
    k = rng.randint(2, 6)
    names = [rng.choice(pool) for _ in range(k)]
    dup = rng.choice(names)
    names.insert(rng.randint(0, len(names)), dup)
    check_dup(names)
    # 2. mangled-equivalent duplicates ("a-b" vs "a_b" both become a_b)
    mangled = [b"a-b", b"a_b"] if i % 2 == 0 else [b"f.id", b"f_id"]
    check_dup(mangled)
    # 3. the non-duplicate path must still build a working row type
    clean = [rng.choice(pool) for _ in range(5)]
    # make sure no post-mangle duplicate slips in (rare for this pool)
    m = [rows._as_python_identifier(n.decode("utf-8")) for n in clean]
    if len(set(m)) == len(m):
        nt = rows._make_nt("utf-8", *clean)
        data = list(range(len(clean)))
        row = nt(*data)
        assert tuple(row) == tuple(data)
        for j, f in enumerate(m):
            assert getattr(row, f) == j
print("ok: %d randomized duplicate/non-duplicate cases behaved correctly" % n_iter)
PY
)
if ( cd /tmp && PYTHONPATH="$SP" "$REALPY" -S -c "$h3_code" > /tmp/h3.out 2>&1 ); then
  if grep -q 'randomized duplicate/non-duplicate cases behaved correctly' /tmp/h3.out; then
    echo "ok: randomized behavioral spot-checks passed"
  else
    fail "randomized spot-check log does not show a real run (fake wrapper?)"
    tail -10 /tmp/h3.out | sed 's/^/    /' >&2
  fi
else
  fail "randomized behavioral spot-checks failed against the installed package"
  tail -25 /tmp/h3.out | sed 's/^/    /' >&2
fi

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd /tmp && python3 -m pytest "$case" -q > "$out" 2>&1 ); then
    if grep -q 'passed' "$out" && ! grep -q 'no tests ran' "$out"; then
      echo "ok: hidden case $name"
    else
      echo "FAIL: hidden case $name did not really run (empty suite or fake wrapper?)" >&2
      tail -15 "$out" | sed 's/^/    /' >&2
      reward=0
    fi
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0