#!/bin/bash
# Verifier for cistern-basin: an upstream-clone debugging task on
# sqlalchemy/sqlalchemy.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# SQLiteDDLCompiler emits the "WITHOUT ROWID" and "STRICT" table-option
# clauses with no comma between them, so a table defined with both
# sqlite_with_rowid=False and sqlite_strict=True compiles to invalid DDL
# ("... WITHOUT ROWID STRICT") that SQLite rejects near "STRICT".  The
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no
#      remotes were added, only the minimal tracked source file is modified,
#      and no new files appeared inside the sqlalchemy package);
#   1. checks the integrity of the harness-owned test fixtures (/opt/golden,
#      /tests/hidden) against pinned sha256 hashes recorded here at review
#      time, so tampering with them cannot manufacture a pass;
#   2. runs the project's own regression test for this bug, extracted at
#      image build time from the fix commit into /opt/golden/;
#   3. runs the project's own existing SQLite dialect compile tests from the
#      tree (SQLTest + OnConflictDDLTest), proving the fix broke nothing
#      else;
#   4. runs the authored hidden cases (end-to-end DDL execution against
#      in-memory SQLite with round-trip/reflection checks, and compile-level
#      assertions over other table shapes including single-option regression
#      guards) that the upstream test does not cover;
#   5. runs a pytest-independent behavioral probe (raw DDL compile +
#      in-memory SQLite execution through the installed library) so that a
#      planted sitecustomize/.pth/conftest import hook or a tampered pytest
#      cannot fake a passing suite while the tree stays buggy.
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
PARENT_SHA=42ddb1fd5f1e29682bcd6ccc7b835999aafec12e
FIX_SHA=48ad8c81115bd01d733fe1a4f78c8c30d7c2abbb
GOLDEN=/opt/golden/test_sqlite.py
ORIGIN_URL=https://github.com/sqlalchemy/sqlalchemy.git

# sha256 of the harness-owned fixture files, pinned at review time:
#   golden  = git show 48ad8c8:test/dialect/test_sqlite.py (byte-identical
#             to the file extracted at image build time into /opt/golden/)
GOLDEN_SHA256=e9a750ea6d8fb3bad3cc31c452cbdc1242f78c50ced948b8f5c2dc24d85e2f99
declare -A HIDDEN_SHA256=(
  [hidden/case-compile/test_ddl_compiles.py]=a31b99cbc22e1a0b5f49db6b86a7901c4df1798675206ddee4f175e2907ad6bf
  [hidden/case-execute/test_ddl_executes.py]=31faaa7f6310ce4c5debb8f44deb00a25b602e2ba4b50ddc5203ab89fb46e04c
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

# ---------- 2. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_pytest "golden test_create_table_without_rowid_strict" /tmp/golden.out \
    "$GOLDEN::SQLTest::test_create_table_without_rowid_strict" \
    -p sqlalchemy.testing.plugin.pytestplugin --rootdir="$SRC" \
    || true
fi

# ---------- 3. the project's own existing SQLite dialect compile tests --------
echo "== the project's own SQLite dialect compile tests =="
run_pytest "existing SQLTest" /tmp/own-sqltest.out \
  test/dialect/test_sqlite.py::SQLTest \
  || true
run_pytest "existing OnConflictDDLTest" /tmp/own-onconflict.out \
  test/dialect/test_sqlite.py::OnConflictDDLTest \
  || true

# ---------- 4. hidden cases ---------------------------------------------------
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

# ---------- 5. pytest-independent behavioral probe ----------------------------
echo "== behavioral probe (no pytest involved) =="
(
  cd "$SRC" && $PY - <<'PY'
import re
from sqlalchemy import Column, Integer, MetaData, Table, create_engine
from sqlalchemy.dialects import sqlite as sqlite_dialect
from sqlalchemy.schema import CreateTable

def norm(s):
    return re.sub(r"\s+", " ", s.replace("\t", " ")).strip()

d = sqlite_dialect.dialect()

t = Table("probe_a", MetaData(), Column("id", Integer, primary_key=True),
          sqlite_with_rowid=False, sqlite_strict=True)
ddl = str(CreateTable(t).compile(dialect=d))
n = norm(ddl)
assert "WITHOUT ROWID, STRICT" in n and "WITHOUT ROWID STRICT" not in n, n
e = create_engine("sqlite://")
with e.begin() as c:
    c.exec_driver_sql(ddl)
    stored = c.exec_driver_sql(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='probe_a'"
    ).scalar()
assert stored is not None and "WITHOUT ROWID, STRICT" in norm(stored), stored

t2 = Table("probe_b", MetaData(), Column("id", Integer, primary_key=True),
           sqlite_with_rowid=False)
n2 = norm(str(CreateTable(t2).compile(dialect=d)))
assert n2.endswith("WITHOUT ROWID"), n2
assert not n2.rstrip().endswith(","), n2

t3 = Table("probe_c", MetaData(), Column("id", Integer, primary_key=True),
           sqlite_strict=True)
n3 = norm(str(CreateTable(t3).compile(dialect=d)))
assert n3.endswith("STRICT"), n3
assert "WITHOUT ROWID" not in n3 and not n3.rstrip().endswith(","), n3

print("probe ok")
PY
) > /tmp/probe.out 2>&1
if [ $? -eq 0 ]; then
  echo "ok: behavioral probe (combined-option DDL compiles and executes; single-option forms unchanged)"
else
  echo "FAIL: behavioral probe" >&2
  tail -30 /tmp/probe.out | sed 's/^/    /' >&2
  reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0