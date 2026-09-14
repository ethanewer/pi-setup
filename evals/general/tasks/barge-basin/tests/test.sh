#!/bin/bash
# Verifier for barge-basin: an upstream-clone debugging task on PyCQA/bandit.
#
# The agent must repair, in the real checkout at /app/src, a real upstream bug
# (PyCQA/bandit issue #1141): scanning valid Python that passes an empty list
# to a standard-library subprocess helper makes the injection-shell plugin
# raise IndexError ("list index out of range"), which bandit logs as
# "Bandit internal error running: ..." on stderr and continues past. The
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no history
#      was fetched, no tracked file was deleted, only source files under
#      bandit/ are modified with at least one modification present, no import-
#      time wrapper, `import bandit` resolves to the checked-out tree, and the
#      unguarded buggy condition is gone from the source with a guard in its
#      place);
#   1. runs the agent's own reproduction deliverable /app/repro.py twice: on
#      the repaired tree it must exit 0, and with the pristine pre-fix tree at
#      /opt/pretree on the import path it must exit non-zero and print the
#      internal-error evidence;
#   2. runs the project's own upstream regression material for this behaviour,
#      extracted at image build time from the fix commit into /opt/golden/ and
#      overlaid onto a throwaway copy of the tree (so the working tree is
#      never touched by the harness);
#   3. runs the project's own existing test suite from the tree, proving the
#      fix broke nothing else;
#   4. runs three authored hidden-case files (family of subprocess helpers,
#      import/call styles, and non-crashing guard shapes) and the verifier's
#      own bandit scans of the same shapes: the pre-fix tree must still show
#      the internal error on every trigger shape, and the repaired tree must
#      show none on any shape.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PRETREE=/opt/pretree
GOLDEN_DIR=/opt/golden
REPRO=/app/repro.py
PARENT_SHA=ad56c78f1e2f7d56fb3f75e8c2d78da85292d0e0
FIX_SHA=049eba08c90c86404d16ed71e5f109dfddf459cd
PARENT_PLUGIN_SHA=6ac89442e38ff67cc3cd1b5c88c72e31ebacf339ce2b03fb6905850dda63c1b6
GOLDEN_TEST_SHA=9d1392f5de3731ada360fcafa8f9ea17688a3b2e0d5218f435a310740506149a
GOLDEN_EXAMPLE_SHA=e57fa980c54aff45b49883db2ebc4b6ddbe6fa85cee9d860cf826b0feaa2ad2c
SHA_FAMILY=5f4225e44a10efce5205d077e9e5c314fb7f99370a4ea91da84a5f06701319ae
SHA_IMPORTS=0ff0cd7527c522d9cb535803baf7ead54c2fd31cff4e7e203a1cb8b6734d8866
SHA_GUARDS=e205a920541a21d24f573de5018676426a5b1d2a8f98ee94467e37a91c3d10e4

export PYTHONDONTWRITEBYTECODE=1

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
bad_tree=0
# porcelain is "XY path" with X=staged, Y=worktree; an agent may legitimately
# `git add` its fix, so a modified file must count regardless of which column
# the M appears in.  Ignore bytecode/cache/egg-info noise.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    *__pycache__*) continue ;;
    *pytest_cache*) continue ;;
    *.egg-info*) continue ;;
  esac
  x=${line:0:1}; y=${line:1:1}; path=${line:3}
  case "$x$y" in
    \?\?)
      # untracked files are allowed only outside the bandit package, and never
      # an import-time hook or a module that could shadow the checked-out
      # package (sitecustomize.py/usercustomize.py get imported by every
      # interpreter whose cwd is the tree; a flat bandit.py would shadow the
      # bandit package dir for `python3 -m bandit` runs inside the tree).
      case "$path" in
        bandit/*)
          echo "FAIL: a new file was added inside the bandit package: $path" >&2; bad_tree=1 ;;
        sitecustomize.py|usercustomize.py|*/sitecustomize.py|*/usercustomize.py|bandit.py|*/bandit.py)
          echo "FAIL: a new module that could hijack imports was added: $path" >&2; bad_tree=1 ;;
        *) : ;;
      esac
      ;;
    *D*)
      echo "FAIL: a tracked file was deleted: $path" >&2; bad_tree=1
      ;;
    A*) # newly added tracked file (staged add, possibly also modified)
      case "$path" in
        bandit/*)
          echo "FAIL: a new tracked file was added inside bandit/: $path" >&2; bad_tree=1 ;;
        *)
          echo "FAIL: a new tracked file was added outside bandit/: $path" >&2; bad_tree=1 ;;
      esac
      ;;
    *M*) # modified (staged, worktree, or both), excluding delete/add cases above
      case "$path" in
        bandit/*)
          saw_mod=1
          ;;
        tests/*|examples/*)
          echo "FAIL: a tracked file under tests/ or examples/ was modified by the agent: $path" >&2; bad_tree=1 ;;
        *)
          echo "FAIL: a tracked file outside bandit/ was modified: $path" >&2; bad_tree=1 ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain --untracked-files=all 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
else
  echo "ok: at least one source file under bandit/ is modified"
fi

if ! ( cd / && python3 -c "import bandit; import sys; sys.exit(0 if bandit.__file__ == '$SRC/bandit/__init__.py' else 3)" >/dev/null 2>&1 ); then
  echo "FAIL: 'import bandit' does not resolve to the checked-out tree at /app/src" >&2
  reward=0
else
  echo "ok: import bandit resolves to $SRC/bandit/__init__.py"
fi

# No import-time wrappers: they could patch the plugin at runtime and fake
# every behavioural check while the checked-out source stays buggy.
if python3 -c "import sitecustomize" >/dev/null 2>&1 \
   || python3 -c "import usercustomize" >/dev/null 2>&1 \
   || [ -f /usr/local/lib/python3.12/sitecustomize.py ] \
   || [ -f /usr/local/lib/python3.12/usercustomize.py ] \
   || [ -f /usr/local/lib/python3.12/site-packages/sitecustomize.py ] \
   || [ -f /usr/local/lib/python3.12/site-packages/usercustomize.py ]; then
  echo "FAIL: an import-time wrapper (sitecustomize/usercustomize) is present; the fix must live in the source" >&2
  reward=0
else
  echo "ok: no import-time wrapper present"
fi

# The fix must live in the source tree itself. The buggy guard is the bare
# `if isinstance(node, ast.List):` before `node = node.elts[0]`; any repair
# must remove that exact form and keep guarding the list contents.
shape=$(python3 - "$SRC/bandit/plugins/injection_shell.py" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()

def bare_and_unguarded() -> bool:
    """True when some bare `if isinstance(node, ast.List):` line still reaches
    the elts access without any intervening mention of node.elts being handled.
    A repair that moves the work under a guard (upstream one-liner `and
    node.elts:`, a nested `if node.elts:`, `len(node.elts) > 0`, ...) passes;
    leaving the bare condition alone is exactly the bug."""
    for i, ln in enumerate(lines):
        if not re.match(r"^\s*if isinstance\(node, ast\.List\):\s*$", ln):
            continue
        indent = len(ln) - len(ln.lstrip())
        guarded = False
        for j in range(i + 1, len(lines)):
            nxt = lines[j]
            if not nxt.strip():
                continue
            nind = len(nxt) - len(nxt.lstrip())
            if "node.elts" in nxt:
                guarded = True
            if nind <= indent and not nxt.lstrip().startswith(("#", "else", "elif", "except", "finally", "try")):
                break
        if not guarded:
            return True
    return False

src = "\n".join(lines)
if bare_and_unguarded():
    print("BUGGYGUARD")
elif "node.elts" in src:
    print("OK")
else:
    print("NOGUARD")
PY
)
case "$shape" in
  OK) echo "ok: the unguarded ast.List condition is gone from the source and a guard on the list contents is present" ;;
  BUGGYGUARD) echo "FAIL: the unguarded buggy condition is still present in bandit/plugins/injection_shell.py" >&2; reward=0 ;;
  *) echo "FAIL: no guard on the list contents is present in the source; the fix must be in the code, not in a wrapper" >&2; reward=0 ;;
esac

# ---------- pre-fix reference tree integrity ---------------------------------
echo "== pre-fix reference tree =="
if [ "$(git -C "$PRETREE" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /opt/pretree HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: /opt/pretree HEAD is $PARENT_SHA"
fi
psha=$(sha256sum "$PRETREE/bandit/plugins/injection_shell.py" 2>/dev/null | cut -d' ' -f1)
if [ "$psha" != "$PARENT_PLUGIN_SHA" ]; then
  echo "FAIL: /opt/pretree plugin file was tampered (sha256 mismatch)" >&2; reward=0
else
  echo "ok: /opt/pretree plugin file is the pristine parent revision"
fi

# ---------- 1. the agent's own reproduction ----------------------------------
echo "== agent reproduction, repaired tree =="
if [ ! -f "$REPRO" ]; then
  echo "FAIL: deliverable /app/repro.py is missing" >&2; reward=0
else
  if ( cd /tmp && PYTHONSAFEPATH=1 python3 "$REPRO" > /tmp/repro-fixed.out 2>&1 ); then
    echo "ok: /app/repro.py exits 0 on the repaired tree"
  else
    echo "FAIL: /app/repro.py exits non-zero on the repaired tree" >&2
    tail -60 /tmp/repro-fixed.out | sed 's/^/    /' >&2
    reward=0
  fi

  echo "== agent reproduction, pre-fix tree =="
  ( cd /tmp && PYTHONPATH="$PRETREE" PYTHONSAFEPATH=1 python3 "$REPRO" > /tmp/repro-pretree.out 2>&1 )
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: /app/repro.py exits 0 against the pre-fix tree; a reproduction of the bug must fail while the bug is present" >&2
    tail -60 /tmp/repro-pretree.out | sed 's/^/    /' >&2
    reward=0
  elif ! grep -q "internal error" /tmp/repro-pretree.out \
       || ! grep -q "start_process_with_partial_path" /tmp/repro-pretree.out; then
    echo "FAIL: the pre-fix run of /app/repro.py printed no genuine 'internal error' evidence (expected the real plugin name on the error line); the reproduction does not demonstrate the bug" >&2
    tail -60 /tmp/repro-pretree.out | sed 's/^/    /' >&2
    reward=0
  else
    echo "ok: /app/repro.py exits non-zero against the pre-fix tree and prints the internal-error evidence"
  fi
fi

# ---------- 2. golden: upstream regression material --------------------------
echo "== upstream regression material =="
gs1=$(sha256sum "$GOLDEN_DIR/test_functional.py" 2>/dev/null | cut -d' ' -f1)
gs2=$(sha256sum "$GOLDEN_DIR/subprocess_shell.py" 2>/dev/null | cut -d' ' -f1)
if [ "$gs1" != "$GOLDEN_TEST_SHA" ] || [ "$gs2" != "$GOLDEN_EXAMPLE_SHA" ]; then
  echo "FAIL: /opt/golden files were tampered with (sha256 mismatch)" >&2; reward=0
else
  echo "ok: golden files integrity confirmed"
  rm -rf /tmp/grun
  cp -a "$SRC" /tmp/grun
  cp "$GOLDEN_DIR/test_functional.py" /tmp/grun/tests/functional/test_functional.py
  cp "$GOLDEN_DIR/subprocess_shell.py" /tmp/grun/examples/subprocess_shell.py
  if ( cd /tmp/grun && python3 -m stestr run --concurrency 1 \
        tests.functional.test_functional.FunctionalTests.test_subprocess_shell \
        > /tmp/golden.out 2>&1 ); then
    echo "ok: golden test test_subprocess_shell passes"
  else
    echo "FAIL: golden test test_subprocess_shell failed" >&2
    tail -40 /tmp/golden.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

# ---------- 3. the project's own existing test suite --------------------------
echo "== the project's own test suite =="
if ( cd "$SRC" && python3 -m stestr run --concurrency 1 > /tmp/own.out 2>&1 ); then
  echo "ok: the project's own test suite passes"
else
  echo "FAIL: the project's own test suite failed" >&2
  tail -40 /tmp/own.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 4. hidden cases + the verifier's own scans ------------------------
echo "== hidden cases =="
hidden_sha_ok () {  # hidden_sha_ok FILE
  local f=$1 want=""
  case "$f" in
    */case-subprocess-family/*) want="$SHA_FAMILY" ;;
    */case-import-shapes/*) want="$SHA_IMPORTS" ;;
    */case-guards/*) want="$SHA_GUARDS" ;;
    *) echo "unknown hidden test file: $f"; return 1 ;;
  esac
  [ "$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)" = "$want" ]
}
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  tainted=0
  for tf in "$case"*.py; do
    [ -f "$tf" ] || continue
    if ! hidden_sha_ok "$tf"; then
      echo "FAIL: hidden test file was tampered with: $tf" >&2; tainted=1; reward=0
    fi
  done
  if [ "$tainted" = 0 ]; then
    if ( cd "$SRC" && python3 -m pytest "$case" -o addopts="" -q -p no:cacheprovider \
          --confcutdir=/tests > "$out" 2>&1 ); then
      echo "ok: hidden case $name"
    else
      echo "FAIL: hidden case $name" >&2
      tail -40 "$out" | sed 's/^/    /' >&2
      reward=0
    fi
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "== verifier's own scans =="
rm -rf /tmp/snippets
mkdir -p /tmp/snippets/triggers /tmp/snippets/guards
python3 - >/dev/null <<'PY'
import pathlib
trig = {
    "popen_empty": "import subprocess\nsubprocess.Popen([])\n",
    "call_empty": "import subprocess\nsubprocess.call([])\n",
    "check_call_empty": "import subprocess\nsubprocess.check_call([], stdout=None)\n",
    "check_output_empty": "import subprocess\nsubprocess.check_output([], stdout=None)\n",
    "run_empty": "import subprocess\nsubprocess.run([], stdout=None)\n",
    "aliased_empty": "import subprocess as sp\nsp.check_output([], stdout=None)\n",
    "fromimport_empty": "from subprocess import check_output\ncheck_output([], stdout=None)\n",
    "multiline_empty": "import subprocess\nsubprocess.check_output(\n    [],\n    stdout=None,\n)\n",
    "kwonly_empty": "import subprocess\nsubprocess.check_output([], stdout=None, input=b'')\n",
}
guard = {
    "nonempty_list": "import subprocess\nsubprocess.check_output(['/bin/ls', '-l'], stdout=None)\n",
    "string_arg": "import subprocess\nsubprocess.check_output('ls -l', stdout=None)\n",
    "tuple_arg": "import subprocess\nsubprocess.check_output(('ls', '-l'), stdout=None)\n",
    "variable_arg": "import subprocess\ncmd = '/bin/ls -l'\nsubprocess.check_output(cmd, stdout=None)\n",
    "mixed_list": "import subprocess\nsubprocess.check_output(['sh', '-c', 'ls -l'], stdout=None)\n",
}
base = pathlib.Path("/tmp/snippets")
for name, src in trig.items():
    (base / "triggers" / (name + ".py")).write_text(src)
for name, src in guard.items():
    (base / "guards" / (name + ".py")).write_text(src)
PY

# pre-fix tree must still show the internal error on every trigger shape
bad=0
for f in /tmp/snippets/triggers/*.py; do
  ( cd /tmp && PYTHONPATH="$PRETREE" python3 -P -m bandit "$f" > /tmp/ps.out 2>&1 )
  n=$(grep -c "internal error" /tmp/ps.out)
  if [ "$n" -lt 1 ]; then
    echo "FAIL: the pre-fix tree showed no internal error for $(basename "$f")" >&2
    tail -8 /tmp/ps.out | sed 's/^/    /' >&2
    reward=0; bad=1
  fi
done
if [ "$bad" = 0 ]; then
  echo "ok: the pre-fix tree still crashes internally on every trigger shape"
fi

# repaired tree must show none on any shape (triggers and guards)
bad=0
for f in /tmp/snippets/triggers/*.py /tmp/snippets/guards/*.py; do
  ( cd /tmp && python3 -P -m bandit "$f" > /tmp/rs.out 2>&1 )
  n=$(grep -c "internal error" /tmp/rs.out)
  if [ "$n" -ne 0 ]; then
    echo "FAIL: the repaired tree still logs an internal error for $(basename "$f")" >&2
    tail -20 /tmp/rs.out | sed 's/^/    /' >&2
    reward=0; bad=1
  fi
done
if [ "$bad" = 0 ]; then
  echo "ok: the repaired tree scans every shape with no internal error"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0