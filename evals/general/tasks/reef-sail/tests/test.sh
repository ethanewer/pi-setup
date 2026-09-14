#!/bin/bash
# Verifier for reef-sail: an upstream-clone debugging task on
# sqlalchemy/sqlalchemy.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# SQLiteDialect.get_check_constraints reflects a CHECK constraint that is
# followed by another constraint clause (bare UNIQUE / PRIMARY KEY / FOREIGN
# KEY in the stored CREATE TABLE text) with the beginning of that clause
# appended to its sqltext.  The instruction requires the agent to author its
# OWN failing reproduction at /app/reproduce_check_constraints.py first; the
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no
#      remotes were added, only the minimal tracked source file is modified,
#      and no new files appeared inside the sqlalchemy package);
#   1. checks the integrity of the harness-owned fixtures (/opt/golden,
#      /tests/hidden) against pinned sha256 hashes recorded here at review
#      time, so tampering with them cannot manufacture a pass;
#   2. requires the agent-authored reproduction deliverable and runs it
#      twice: against a pristine copy of the pre-fix tree it must FAIL
#      (nonzero exit, proving it genuinely catches the bug), and against the
#      repaired tree it must PASS (exit 0);
#   3. runs the project's own upstream regression test for this bug
#      (ConstraintReflectionTest from the fix commit, extracted at image
#      build time into /opt/golden/);
#   4. runs the project's own existing test/dialect/test_sqlite.py file in
#      full, proving the fix broke nothing else;
#   5. runs the authored hidden cases (constraint shapes and raw-DDL
#      orderings the upstream test does not use) that must pass against the
#      repaired tree (and each is confirmed to fail against the pre-fix
#      tree);
#   6. runs a pytest-independent behavioral probe through the installed
#      library so that a planted sitecustomize/.pth/conftest import hook or
#      a tampered pytest cannot fake a passing suite while the tree stays
#      buggy.
#
# All python invocations use `-S` (no site import): a root agent can plant
# sitecustomize.py / usercustomize.py / .pth / conftest.py inside the image,
# but with -S none of those run, and PYTHONPATH points explicitly at the
# checked-out tree and the interpreter's own site-packages.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# Clear any reward file a (hostile) agent phase may have planted; the only
# reward that counts is the one this verifier writes below.
rm -f /logs/verifier/reward.txt
reward=1

SRC=/app/src
PARENT_SHA=e51ff826b9374cadb8eded370a808bc4dcbe56ba
FIX_SHA=44be2ef4484345298825f547e21d2881cc4921a9
GOLDEN=/opt/golden/test_sqlite.py
ORIGIN_URL=https://github.com/sqlalchemy/sqlalchemy.git
REPRO=/app/reproduce_check_constraints.py

# sha256 of the harness-owned fixture files, pinned at review time:
#   golden  = git show 44be2ef44:test/dialect/test_sqlite.py (byte-identical
#             to the file extracted at image build time into /opt/golden/)
GOLDEN_SHA256=8ea90e52ae4137f081c4e998e972ce415c56dd52389899d404f5cb2ec95a29b8
declare -A HIDDEN_SHA256=(
  [hidden/case-unique-multicol/test_check_followed_by_unique.py]=e11022c7d622ed023dcd4d3257bc489047de3e393bd1db9e025df869f2872b2a
  [hidden/case-foreignkey/test_check_followed_by_foreignkey.py]=e19537ac2100d50bd56da728820a115ff9ade7036eed34be8785656c9380ca15
  [hidden/case-pk-middle/test_primary_key_between_checks.py]=6e2282410e9fd6b626c6956d9f68aa323cbe14777e992958ef5f25dea3609e7b
)

# -S mode: no sitecustomize/.pth/conftest import-hook can run.  PYTHONPATH
# gives python the checked-out tree and the real site-packages (which is
# where the editable install, greenlet, pytest, pluggy etc. live).
SP=$(python3 -S -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])' 2>/dev/null || echo /usr/local/lib/python3.12/site-packages)
export PYTHONPATH="$SRC/lib:$SP"
PY="python3 -S"

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && $PY -m pytest "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

fail_fixture () {
  echo "FAIL: $1" >&2
  shift
  for line in "$@"; do echo "    $line" >&2; done
  reward=0
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
else
  echo "ok: the upstream fix commit is not reachable from the working clone"
fi

remotes=$(git -C "$SRC" remote 2>/dev/null || true)
if [ "$(printf '%s\n' "$remotes" | sed '/^$/d' | wc -l)" != "1" ] || \
   [ "$(git -C "$SRC" remote get-url origin 2>/dev/null || true)" != "$ORIGIN_URL" ]; then
  echo "FAIL: remotes were added or origin changed" >&2
  printf '%s\n' "$remotes" | sed 's/^/    /' >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
# Allow only the one tracked modification; untracked entries are allowed only
# when they are interpreter caches (git-ignored by upstream anyway).
bad=$(printf '%s\n' "$porcelain" \
  | grep -v '^ M lib/sqlalchemy/dialects/sqlite/base.py$' \
  | grep -v '^?? .*\(__pycache__\|\.pytest_cache\|\.mypy_cache\|\.coverage\)' \
  | grep -v '^?? $' \
  | sed '/^$/d' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only lib/sqlalchemy/dialects/sqlite/base.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? lib/sqlalchemy/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the sqlalchemy package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- lib/sqlalchemy/dialects/sqlite/base.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. fixture integrity (anti-tamper) ---------------------------------
echo "== fixture integrity =="
# /opt/golden must hold exactly the single upstream file from the fix commit,
# byte-for-byte. A root agent can rewrite it during the agent phase; the hash
# was recorded at review time from `git show <fix>:test/dialect/test_sqlite.py`.
if [ ! -d /opt/golden ]; then
  fail_fixture "/opt/golden is missing"
elif [ "$(find /opt/golden -maxdepth 1 -type f | wc -l)" != "1" ]; then
  fail_fixture "/opt/golden must contain exactly the one golden test file" \
    "$(find /opt/golden -maxdepth 1 -type f | sed 's/^/    /')"
else
  actual=$(sha256sum "$GOLDEN" | awk '{print $1}')
  if [ "$actual" = "$GOLDEN_SHA256" ]; then
    echo "ok: golden file matches the fix-commit checksum"
  else
    fail_fixture "golden file checksum mismatch (tampered?)" \
      "expected $GOLDEN_SHA256" "actual   $actual"
  fi
fi
# Hidden cases arrive fresh from the harness at verification time; pin them
# anyway so any future wiring that lets an agent reach them is caught.
for rel in "${!HIDDEN_SHA256[@]}"; do
  f="/tests/$rel" # rel is relative to /tests
  if [ ! -f "$f" ]; then
    fail_fixture "hidden fixture missing: $rel"
  else
    actual=$(sha256sum "$f" | awk '{print $1}')
    if [ "$actual" = "${HIDDEN_SHA256[$rel]}" ]; then
      echo "ok: hidden fixture $rel checksum matches"
    else
      fail_fixture "hidden fixture checksum mismatch: $rel" \
        "expected ${HIDDEN_SHA256[$rel]}" "actual   $actual"
    fi
  fi
done

# ---------- 2. the agent-authored reproduction deliverable --------------------
echo "== agent-authored reproduction deliverable =="
if [ ! -f "$REPRO" ]; then
  echo "FAIL: deliverable $REPRO was not created" >&2; reward=0
else
  echo "ok: $REPRO exists"
fi

# 2a. against the REPAIRED tree it must pass (exit 0)
if [ -f "$REPRO" ]; then
  if ( cd "$SRC" && timeout 240 env PYTHONPATH="$PYTHONPATH" $PY "$REPRO" > /tmp/repro-fixed.out 2>&1 ); then
    echo "ok: reproduction exits 0 against the repaired tree"
  else
    echo "FAIL: reproduction does not exit 0 against the repaired tree" >&2
    tail -30 /tmp/repro-fixed.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

# 2b. against a pristine copy of the PRE-FIX tree it must FAIL (nonzero exit):
#     this proves the reproduction genuinely catches the bug and that the
#     tree was actually repaired.  (git clean + checkout restore the copy to
#     the exact parent-commit content.)
if [ -f "$REPRO" ]; then
  rm -rf /tmp/prefix
  cp -a "$SRC" /tmp/prefix
  git -C /tmp/prefix clean -fdq >/dev/null 2>&1 || true
  git -C /tmp/prefix checkout -- . >/dev/null 2>&1 || true
  cp "$REPRO" /tmp/prefix/reproduce_check_constraints.py
  pre_out=/tmp/repro-prefix.out
  ( cd /tmp/prefix && timeout 240 env PYTHONPATH="/tmp/prefix/lib:$SP" $PY /tmp/prefix/reproduce_check_constraints.py > "$pre_out" 2>&1 )
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ok: reproduction fails (exit $rc) against the pristine pre-fix tree"
    grep -m1 -i "corrupt" "$pre_out" | sed 's/^/    observed: /' || true
  else
    echo "FAIL: reproduction exits 0 against the pristine pre-fix tree (it does not catch the bug; the fix was not demonstrated or the reproduction is vacuous)" >&2
    tail -30 "$pre_out" | sed 's/^/    /' >&2
    reward=0
  fi
  rm -rf /tmp/prefix
fi

# ---------- 3. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression tests for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_pytest "golden ConstraintReflectionTest" /tmp/golden.out \
    "$GOLDEN::ConstraintReflectionTest" \
    -p sqlalchemy.testing.plugin.pytestplugin --rootdir="$SRC" \
    || true
fi

# ---------- 4. the project's own existing SQLite dialect tests ---------------
echo "== the project's own SQLite dialect test file =="
run_pytest "own test/dialect/test_sqlite.py in full" /tmp/own-sqlite.out \
  test/dialect/test_sqlite.py \
  || true

# ---------- 5. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && $PY -m pytest "$case" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

# ---------- 6. pytest-independent behavioral probe ----------------------------
echo "== behavioral probe (no pytest involved) =="
(
  cd "$SRC" && $PY - <<'PY'
import sqlalchemy as sa
from sqlalchemy import (
    CheckConstraint, Column, Integer, MetaData, String, Table,
    UniqueConstraint, create_engine, inspect,
)

# A. SQLAlchemy-emitted DDL: CHECK followed by a bare UNIQUE, then a CHECK
#    followed by a named UNIQUE (CONSTRAINT-prefixed, already fine upstream).
e = create_engine("sqlite://")
m = MetaData()
Table(
    "probe_a", m,
    Column("x", Integer), Column("y", String),
    CheckConstraint("x > 0", name="ck_x"),
    UniqueConstraint("x", "y"),
    CheckConstraint("length(y) < 100", name="ck_y"),
    UniqueConstraint("y", name="uq_y"),
)
with e.begin() as c:
    m.create_all(c)
    texts = {ck["name"]: ck["sqltext"] for ck in inspect(c).get_check_constraints("probe_a")}
    uniques = {tuple(u["column_names"]): u["name"] for u in inspect(c).get_unique_constraints("probe_a")}
assert texts["ck_x"] == "x > 0", texts
assert texts["ck_y"] == "length(y) < 100", texts
assert uniques[("x", "y")] is None and uniques[("y",)] == "uq_y", uniques

# B. Raw DDL: bare PRIMARY KEY physically between two CHECK constraints.
with e.begin() as c:
    c.exec_driver_sql(
        "CREATE TABLE probe_b (a INTEGER, CONSTRAINT ck_a CHECK (a > 0), "
        "PRIMARY KEY (a), CONSTRAINT ck_b CHECK (a < 10), UNIQUE (a))"
    )
    texts = {ck["name"]: ck["sqltext"] for ck in inspect(c).get_check_constraints("probe_b")}
assert texts["ck_a"] == "a > 0", texts
assert texts["ck_b"] == "a < 10", texts

# C. Raw DDL: bare FOREIGN KEY clause after a CHECK.
with e.begin() as c:
    c.exec_driver_sql("CREATE TABLE parent (id INTEGER PRIMARY KEY)")
    c.exec_driver_sql(
        "CREATE TABLE probe_c (pid INTEGER, q INTEGER, "
        "CONSTRAINT ck_q CHECK (q > 0), "
        "FOREIGN KEY (pid) REFERENCES parent (id))"
    )
    texts = {ck["name"]: ck["sqltext"] for ck in inspect(c).get_check_constraints("probe_c")}
assert texts["ck_q"] == "q > 0", texts

print("probe ok")
PY
) > /tmp/probe.out 2>&1
if [ $? -eq 0 ]; then
  echo "ok: behavioral probe (bare UNIQUE / PRIMARY KEY / FOREIGN KEY boundaries all split; named CONSTRAINT boundaries unchanged)"
else
  echo "FAIL: behavioral probe" >&2
  tail -30 /tmp/probe.out | sed 's/^/    /' >&2
  reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0