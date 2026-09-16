#!/bin/bash
# Verifier for ballast-roadstead: an upstream-clone debugging task on
# python-poetry/poetry.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# `poetry debug resolve` raises `IndexError: list assignment index out of
# range` for any resolved package that carries an environment marker (the row
# it builds has two columns but the code assigns a third with `row[2] = ...`
# instead of appending). The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no history
#      was fetched, no tracked file was deleted, the ONLY tracked file
#      modified under src/poetry/ is src/poetry/console/commands/debug/
#      resolve.py -- the file the bug lives in -- and at least that one file
#      is modified, and `import poetry` resolves to the checked-out tree).
#      Historically this task's verifier required only *some* file under
#      src/poetry/ to be modified; a tree could then pass through a conftest
#      wrapper or an unrelated decorative edit while resolve.py stayed buggy.
#      Requiring the buggy file itself to be the (only) change closes that.
#   1. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/,
#      whose byte content is pinned (sha256) so a tampered golden copy cannot
#      be swapped in -- first the marker test alone, then the whole file;
#   2. runs the project's own existing tests for the debug command area;
#   3. runs two authored hidden-case files with marker and package shapes the
#      upstream test does not use;
#   4. runs a randomized direct-execution check that is NOT pytest: a fresh
#      probe script (written at verify time into a fresh mktemp dir) drives
#      the real command machinery with a package name, version and marker
#      string chosen at random at verify time, plus a plain package that must
#      keep exactly two columns. Because the inputs are generated per run,
#      a hardcoded output keyed on the visible test inputs cannot satisfy it
#      while leaving the general bug in place; because it never runs pytest,
#      a conftest/sitecustomize wrapper cannot intercept it; and because the
#      probe file is created after the agent has finished, it cannot have been
#      pre-tampered.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=b760721672011534ca3607d17e3bf61a4dc6ed90
FIX_SHA=89aaee9d60cae20775d3c40e4f243f9945f718e1
GOLDEN=/opt/golden/test_resolve.py
# sha256 of the exact upstream bytes of the regression test at the fix commit
# (git show 89aaee9d60cae20775d3c40e4f243f9945f718e1:tests/console/commands/debug/test_resolve.py).
GOLDEN_SHA256=281411d7ab9aa040a3d545028bc293cde2ad1ff77160430b6f71ba03a0c7b89c
PY=/opt/poetry-venv/bin/python
PYTEST=/opt/poetry-venv/bin/pytest

export PYTHONDONTWRITEBYTECODE=1 COLUMNS=80

# The battery runs under `python -S` (skip site processing): the editable
# install puts /app/src/src on sys.path via a .pth file, which would import a
# sitecustomize.py an agent could drop there (or in site-packages) to monkey-
# patch the buggy command at interpreter startup and pass every test while
# leaving the bug on disk. -S never imports sitecustomize from any location,
# so the tests measure the on-disk tree. PYTHONPATH restores the paths the
# .pth files would have added; cwd=$SRC keeps ``tests`` importable.
run_pytest () {  # run_pytest LABEL OUT ...args  (cwd = SRC)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" \
       && PYTHONPATH="$SRC/src:/opt/poetry-venv/lib/python3.12/site-packages" \
          "$PY" -S -m pytest "$@" -o addopts="" -q -p no:cacheprovider -p no:randomly \
         > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
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
  echo "ok: fix commit not present in the working clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  echo "FAIL: the working clone contains $ncommits commits; it must contain exactly the pinned parent commit (history was fetched or added)" >&2
  reward=0
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

saw_mod=0
resolve_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M src/poetry/"*)
      saw_mod=1
      if [ "$line" = " M src/poetry/console/commands/debug/resolve.py" ]; then
        resolve_mod=1
      fi
      ;;
    " M "*) # modified tracked file outside src/poetry/
      case "$line" in
        " M tests/"*)
          echo "FAIL: a tracked test file was modified by the agent: $line" >&2; bad_tree=1 ;;
        *)  echo "FAIL: a tracked file outside src/poetry/ was modified: $line" >&2; bad_tree=1 ;;
      esac
      ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*) # untracked files are allowed only outside the poetry package
      case "$line" in
        "?? src/poetry/"*)
          echo "FAIL: a new file was added inside the poetry package: $line" >&2; bad_tree=1 ;;
        *) : ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
elif [ "$resolve_mod" = 0 ]; then
  echo "FAIL: a file under src/poetry/ was modified but not src/poetry/console/commands/debug/resolve.py, where the bug lives (the tree only passes via a wrapper or an unrelated change)" >&2
  reward=0
else
  echo "ok: at least the buggy source file src/poetry/console/commands/debug/resolve.py is modified"
fi

if ! ( cd / && "$PY" -c "import poetry, sys; sys.exit(0 if any(p.rstrip('/') == '$SRC/src/poetry' for p in getattr(poetry, '__path__', [])) else 3)" >/dev/null 2>&1 ); then
  echo "FAIL: 'import poetry' does not resolve to the checked-out tree at /app/src" >&2
  ( cd / && "$PY" -c "import poetry; print('poetry path:', list(getattr(poetry, '__path__', [])))" ) 2>&1 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: import poetry resolves to $SRC/src/poetry"
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  golden_actual=$("$PY" -c "import hashlib,sys; print(hashlib.sha256(open('$GOLDEN','rb').read()).hexdigest())" 2>/dev/null || echo MISSING)
  if [ "$golden_actual" != "$GOLDEN_SHA256" ]; then
    echo "FAIL: golden test file /opt/golden/test_resolve.py has been modified (sha256 $golden_actual != $GOLDEN_SHA256)" >&2
    reward=0
  else
    echo "ok: golden test file matches the upstream fix-commit bytes (sha256 pin)"
    cp "$GOLDEN" "$SRC/tests/console/commands/debug/test_resolve.py"
    run_pytest "golden test_debug_resolve_shows_marker_when_present" /tmp/golden1.out \
      "tests/console/commands/debug/test_resolve.py::test_debug_resolve_shows_marker_when_present" || true
    run_pytest "whole golden test file (4 tests)" /tmp/golden2.out \
      tests/console/commands/debug/test_resolve.py || true
  fi
fi

# ---------- 2. the project's own existing debug-command tests ----------------
echo "== the project's own debug-command test suite =="
run_pytest "tests/console/commands/debug/ (project's own suite)" /tmp/own.out \
  tests/console/commands/debug/ || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  run_pytest "hidden case $name" "$out" "$case" || true
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

# ---------- 4. randomized direct-execution check (not pytest) -----------------
# A probe script is generated at verify time (into a fresh mktemp dir) with
# random package name, version and marker strings, and run with plain
# `python -S` (not pytest), so no conftest/sitecustomize wrapper and no
# hardcoded-output map keyed on the visible test inputs can satisfy it while
# the general bug remains in the tree.
echo "== randomized direct-execution check =="
dir_out=$(mktemp -d /tmp/direct.XXXXXX) || { echo "FAIL: cannot create temp dir" >&2; reward=0; dir_out=""; }
if [ -n "$dir_out" ]; then
  rnd1=$RANDOM$RANDOM; rnd2=$RANDOM$RANDOM
  mark_name="pkg$rnd1"
  plain_name="plain$rnd2"
  mark_marker="sys_platform == \"zoom$rnd2\""

  cat > "$dir_out/direct_probe.py" <<'PYEOF'
from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, "/app/src")
os.environ.setdefault("COLUMNS", "80")

from cleo.io.null_io import NullIO  # noqa: E402
from cleo.testers.command_tester import CommandTester  # noqa: E402
from poetry.core.version.markers import parse_marker  # noqa: E402
from poetry.factory import Factory  # noqa: E402
from poetry.repositories.repository_pool import RepositoryPool  # noqa: E402
from tests.helpers import PoetryTestApplication  # noqa: E402
from tests.helpers import TestRepository  # noqa: E402
from tests.helpers import get_package  # noqa: E402

PROJECT_TOML = """\
[tool.poetry]
name = "direct-probe"
version = "0.1.0"
description = "verifier-side randomized probe for the debug resolve marker fix"

[tool.poetry.dependencies]
python = "^3.9"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
"""

MARK_NAME = os.environ["DIRECT_MARK_NAME"]
MARK_VERSION = os.environ["DIRECT_MARK_VERSION"]
MARK_MARKER = os.environ["DIRECT_MARK_MARKER"]
PLAIN_NAME = os.environ["DIRECT_PLAIN_NAME"]
PLAIN_VERSION = os.environ["DIRECT_PLAIN_VERSION"]


def build_tester(pkgs) -> CommandTester:
    project_dir = Path(tempfile.mkdtemp(prefix="direct-project-"))
    (project_dir / "pyproject.toml").write_text(PROJECT_TOML, encoding="utf-8")

    poetry = Factory().create_poetry(project_dir)

    repo = TestRepository(name="direct")
    for name, version, marker in pkgs:
        pkg = get_package(name, version)
        if marker is not None:
            pkg.marker = parse_marker(marker)
        repo.add_package(pkg)

    pool = RepositoryPool()
    pool.add_repository(repo)
    poetry.set_pool(pool)

    app = PoetryTestApplication(poetry)
    app._load_plugins(NullIO())

    command = app.find("debug resolve")
    tester = CommandTester(command)
    app_io = app.create_io()
    formatter = app_io.output.formatter
    tester.io.output.set_formatter(formatter)
    tester.io.error_output.set_formatter(formatter)
    return tester


def resolve(tester: CommandTester, package: str) -> str:
    tester.execute(package)
    return tester.io.fetch_output()


def check(reason: str, cond: bool) -> None:
    if not cond:
        raise AssertionError(reason)


# 1) a marked package with a random marker string renders the marker as a
#    third column on its row, and the command does not crash.
tester = build_tester([(MARK_NAME, MARK_VERSION, MARK_MARKER)])
out = resolve(tester, MARK_NAME)
expected = (
    "Resolving dependencies...\n"
    "\n"
    "Resolution results:\n"
    "\n"
    f'{MARK_NAME} {MARK_VERSION} {MARK_MARKER}\n'
)
check(f"marked package output mismatch:\n---\n{out}\n---", out == expected)
check("marked package output contains a traceback", "Traceback" not in out)

# 2) a plain package (no marker) keeps exactly two columns, no empty or
#    spurious third column.
tester2 = build_tester([(PLAIN_NAME, PLAIN_VERSION, None)])
out2 = resolve(tester2, PLAIN_NAME)
expected2 = (
    "Resolving dependencies...\n"
    "\n"
    "Resolution results:\n"
    "\n"
    f'{PLAIN_NAME} {PLAIN_VERSION}\n'
)
check(f"plain package output mismatch:\n---\n{out2}\n---", out2 == expected2)
check("plain package output contains a traceback", "Traceback" not in out2)

# 3) both packages in one repository: each renders on its own.
tester3 = build_tester(
    [
        (MARK_NAME, MARK_VERSION, MARK_MARKER),
        (PLAIN_NAME, PLAIN_VERSION, None),
    ]
)
out3 = resolve(tester3, MARK_NAME)
check("marked row missing in combined repo", out3.endswith(f"{MARK_NAME} {MARK_VERSION} {MARK_MARKER}\n"))
out4 = resolve(tester3, PLAIN_NAME)
check("plain row missing in combined repo", out4.endswith(f"{PLAIN_NAME} {PLAIN_VERSION}\n"))

print("DIRECT_OK")
PYEOF

  if ( cd "$SRC" \
       && PYTHONPATH="$SRC/src:/opt/poetry-venv/lib/python3.12/site-packages" \
          DIRECT_MARK_NAME="$mark_name" DIRECT_MARK_VERSION="1.2.3" \
          DIRECT_MARK_MARKER="$mark_marker" \
          DIRECT_PLAIN_NAME="$plain_name" DIRECT_PLAIN_VERSION="0.9.1" \
          "$PY" -S "$dir_out/direct_probe.py" > /tmp/direct.out 2>&1 ); then
    echo "ok: randomized direct-execution check (marked + plain, random inputs)"
  else
    echo "FAIL: randomized direct-execution check" >&2
    tail -40 /tmp/direct.out | sed 's/^/    /' >&2
    reward=0
  fi
  rm -rf "$dir_out"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0