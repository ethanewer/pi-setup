#!/bin/bash
# Verifier for mooring-port: an upstream-clone debugging task on
# pylint-dev/pylint. The agent must write its own failing reproduction
# (/app/reproduce.py) and fix, in the real checkout at /app/src, a real
# upstream bug: with the typing extension enabled, a file containing an
# empty-tuple type-argument subscript such as `collections.abc.Generator[()]`
# crashes the checker with an internal IndexError and a fatal-error report
# (upstream issue #11357; fixed upstream in
# 5e00da601a4c14f8321494db4dcdb4a9e42e92d7 by guarding the redundant
# default-type-args check on a non-empty subscript slice).
#
# The verifier:
#   0. asserts tree provenance (HEAD still the pinned parent commit, the
#      upstream fix commit not reachable from the working clone, exactly one
#      commit in the clone, no tracked file deleted, modified tracked files
#      confined to Pylint package sources with at least one such modification,
#      the fix guard present in the source tree itself, the reproduction
#      deliverable present, and `import pylint` resolving to the checked-out
#      tree);
#   1. runs the agent's own reproduction against a pristine copy of the
#      parent's pylint/extensions/typing.py (must crash with the fatal
#      internal error) and against the repaired tree (must exit 0 cleanly);
#   2. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/;
#   3. runs the project's own typing-extension functional tests, proving the
#      fix broke nothing else;
#   4. runs authored hidden cases over empty-tuple subscript shapes, code
#      positions, message-preservation and extension-loading guards that the
#      upstream test does not use.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=92b631fac22e503e9520fb5280929499b6787093
FIX_SHA=5e00da601a4c14f8321494db4dcdb4a9e42e92d7
GOLDEN_DIR=/opt/golden/ext/typing
GOLDEN_PY_SHA=64e9eb3de656f816f2fdd07015d93b8017b91f4d244ff922af6159b7db3a9a84
PRISTINE=/opt/pristine_typing.py
PRISTINE_SHA=8b109a19cd1c23bd464369aadd61ad9d887429ffd7acd4b71bfebe16e83001c5
REPRO=/app/reproduce.py

export PYTHONDONTWRITEBYTECODE=1

run_pytest () {  # run_pytest LABEL OUT ...args  (cwd = SRC)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -o addopts="" -q -p no:cacheprovider > "$out" 2>&1 ); then
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
bad_tree=0
# porcelain is "XY path" with X=staged, Y=worktree; an agent may legitimately
# `git add` its fix, so a modified file counts regardless of which column.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  x=${line:0:1}; y=${line:1:1}; path=${line:3}
  case "$x$y" in
    \?\?)
      case "$path" in
        pylint/*)
          echo "FAIL: a new file was added inside the pylint package: $path" >&2; bad_tree=1 ;;
        conftest.py|*/conftest.py|sitecustomize.py|*/sitecustomize.py|usercustomize.py|*/usercustomize.py)
          echo "FAIL: a pytest/import interception file was added to the working tree: $path" >&2; bad_tree=1 ;;
        __pycache__/*|*/__pycache__/*|*.pyc|.pytest_cache/*|.coverage|.pylint.d/*)
          : ;;  # benign test residue (pyc/cache/coverage files) is tolerated
        *)
          echo "FAIL: an untracked file appeared in the working tree: $path" >&2; bad_tree=1 ;;
      esac
      ;;
    *D*)
      echo "FAIL: a tracked file was deleted: $path" >&2; bad_tree=1
      ;;
    A*)
      echo "FAIL: a new tracked file was added: $path" >&2; bad_tree=1
      ;;
    *M*)
      case "$path" in
        pylint/*)
          saw_mod=1
          ;;
        *)
          echo "FAIL: a tracked file outside the pylint package was modified: $path" >&2; bad_tree=1 ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
else
  echo "ok: at least one source file under pylint/ is modified"
fi

# The fix must live in the source tree itself: visit_subscript must guard the
# suggestion-building on a non-empty subscript slice. Without this check, a
# wrapper installed outside the source (sitecustomize, conftest, ...) or an
# exception-swallowing workaround could make the behavioural checks pass while
# the checked-out code still contains the bug.
shape=$(python3 - "$SRC/pylint/extensions/typing.py" <<'PY'
import io, re, sys, tokenize
src = open(sys.argv[1], encoding="utf-8").read()
# A correct fix adds an emptiness guard on node.slice.elts (upstream: the extra
# "and node.slice.elts" conjunct) before elts[0] is indexed, INSIDE
# visit_subscript. The parent code only ever writes node.slice.elts[1:] /
# node.slice.elts[0], which none of these patterns match. Comments and string
# literals are stripped first, so a decoy "guard" scribbled in a comment or a
# docstring does not count. The guard must live in the visit_subscript method
# itself, not in some never-called helper elsewhere in the module.
buf = []
try:
    for t in tokenize.generate_tokens(io.StringIO(src).readline):
        if t.type in (tokenize.COMMENT, tokenize.STRING,
                      getattr(tokenize, "FSTRING_START", -1),
                      getattr(tokenize, "FSTRING_MIDDLE", -1),
                      getattr(tokenize, "FSTRING_END", -1)):
            buf.append(" ")
        else:
            buf.append(t.string)
except (IndentationError, tokenize.TokenizeError):
    print("NOGUARD")
    raise SystemExit(0)
code = "".join(buf)
i = code.find("def visit_subscript")
j = code.find("\ndef ", i + 1) if i != -1 else -1
span = code[i:j] if i != -1 else code
pattern = re.compile(
    r"node\.slice\.elts\s+and"
    r"|not\s+node\.slice\.elts"
    r"|len\(node\.slice\.elts\)"
    r"|if\s+node\.slice\.elts"
    r"|node\.slice\.elts\s*\)?\s*and"
)
print("OK" if pattern.search(span) else "NOGUARD")
PY
)
case "$shape" in
  OK) echo "ok: pylint/extensions/typing.py guards the redundant-args check on a non-empty subscript slice" ;;
  NOGUARD) echo "FAIL: no emptiness guard on node.slice.elts in pylint/extensions/typing.py; the fix must be in the source tree, not in a wrapper" >&2; reward=0 ;;
  *) echo "FAIL: could not evaluate the source-shape check" >&2; reward=0 ;;
esac

if [ ! -f "$REPRO" ]; then
  echo "FAIL: deliverable /app/reproduce.py does not exist" >&2; reward=0
elif [ ! -x "$REPRO" ] && ! head -1 "$REPRO" | grep -q python; then
  echo "FAIL: /app/reproduce.py is not executable Python" >&2; reward=0
else
  echo "ok: /app/reproduce.py present"
fi

if ! ( cd / && python3 -c "import pylint; import sys; sys.exit(0 if pylint.__file__ == '$SRC/pylint/__init__.py' else 3)" >/dev/null 2>&1 ); then
  echo "FAIL: 'import pylint' does not resolve to the checked-out tree at /app/src" >&2
  reward=0
else
  echo "ok: import pylint resolves to $SRC/pylint/__init__.py"
fi

# ---------- 0b. verifier-owned /tests fixtures are integrity-pinned ----------
# The agent container runs as root, the /tests bind mount is writable, and the
# verifier's own scope re-uploads only test.sh + hidden/ (extra files an agent
# planted persist). A planted /tests/conftest.py would be imported by every
# hidden-case pytest run (--confcutdir=/tests includes the cut dir itself), so
# the hidden fixtures are sha256-pinned here and nothing but test.sh and the
# pinned hidden/ tree may exist under /tests.
echo "== /tests fixture integrity =="
bad_tests=0
extra=$(find /tests -maxdepth 1 -mindepth 1 \
  \( -name test.sh -o -name hidden \) -prune -o -print)
if [ -n "$extra" ]; then
  echo "FAIL: unexpected files at /tests root:" >&2
  echo "$extra" | sed 's/^/    /' >&2
  bad_tests=1
fi
n=$(find /tests/hidden \( -path "*/__pycache__/*" -o -name "*.pyc" \) -prune -o -type f -print 2>/dev/null | wc -l)
if [ "$n" != 8 ]; then
  echo "FAIL: expected exactly 8 files under /tests/hidden, found $n" >&2
  bad_tests=1
fi
while read -r sha path; do
  real=$(sha256sum "/tests/$path" 2>/dev/null | cut -d' ' -f1)
  if [ "$real" != "$sha" ]; then
    echo "FAIL: /tests/$path content changed (sha mismatch)" >&2
    bad_tests=1
  fi
done <<'EOF'
2706e4f78f1d034eb6821efd5ab564b66e0cdb111b18eadca47f648b27bacd97  hidden/case-corner-shapes/fixture_corner_shapes.py
fb067caee9dd5786f0b0dbcbc690d58c8977c3c03650dfbff858827196392955  hidden/case-corner-shapes/test_corner_shapes.py
4f5f92845f6a8fd617b54b24daef3fa34eec3b9c4bb7ba18cdb54925f386b0e5  hidden/case-message-preservation/fixture_message_preservation.py
95143d21a19b0e883249d7a6566909545bdf8a890c02105abc980ec346f0956e  hidden/case-message-preservation/test_message_preservation.py
201c61b6a70fc14968d7192aac639d499ccea854eacb547b77e48565bf9f52cf  hidden/case-no-extension/fixture_no_extension.py
0a5e2302943883865b1a811f85e0baa91ca74783e7d3e3481b5a567f3a68c318  hidden/case-no-extension/test_no_extension.py
e859c0bed70fcdd7ed73022e4e749e86cb216e138d4d47d4647f529dd0fa6de2  hidden/case-positions/fixture_positions.py
8e356c4b4f8d0d7d05029a9bc00df87af49603bea599cebc7d741289ea2aa360  hidden/case-positions/test_positions.py
EOF
if [ "$bad_tests" = 1 ]; then reward=0; else echo "ok: /tests hidden fixtures pinned and intact"; fi

# ---------- 1. the agent's reproduction: pristine (pre-fix) vs repaired -------
echo "== agent reproduction against pristine pre-fix code =="
if [ -f "$REPRO" ]; then
  # The pristine file must be the parent's typing.py, not something the agent
  # retouched to hide the crash.
  if [ "$(sha256sum "$PRISTINE" 2>/dev/null | cut -d' ' -f1)" != "$PRISTINE_SHA" ]; then
    echo "FAIL: /opt/pristine_typing.py was tampered with (sha256 mismatch)" >&2; reward=0
  else
    echo "ok: pristine file integrity confirmed"
    cp "$SRC/pylint/extensions/typing.py" /tmp/agent_typing.py
    cp "$PRISTINE" "$SRC/pylint/extensions/typing.py"
    if ( cd "$SRC" && python3 "$REPRO" > /tmp/repro_pre.out 2> /tmp/repro_pre.err ); then
      echo "FAIL: the reproduction exited 0 against the pre-fix code, so it does not exercise the bug" >&2
      reward=0
    elif grep -qE "Fatal error|IndexError" /tmp/repro_pre.out /tmp/repro_pre.err; then
      echo "ok: reproduction crashes with the fatal internal error against pre-fix code"
    else
      echo "FAIL: reproduction failed against pre-fix code but without the fatal-error marker" >&2
      tail -20 /tmp/repro_pre.out /tmp/repro_pre.err 2>/dev/null | sed 's/^/    /' >&2
      reward=0
    fi
    cp /tmp/agent_typing.py "$SRC/pylint/extensions/typing.py"
    if [ "$(sha256sum "$SRC/pylint/extensions/typing.py" | cut -d' ' -f1)" = "$(sha256sum /tmp/agent_typing.py | cut -d' ' -f1)" ]; then
      echo "ok: agent's typing.py restored after the pristine run"
    else
      echo "FAIL: could not restore the agent's typing.py after the pristine run" >&2; reward=0
    fi
  fi
  echo "== agent reproduction against the repaired tree =="
  if ( cd "$SRC" && python3 "$REPRO" > /tmp/repro_fix.out 2> /tmp/repro_fix.err ); then
    if grep -qE "Fatal error|IndexError" /tmp/repro_fix.out /tmp/repro_fix.err; then
      echo "FAIL: reproduction still reports the fatal internal error on the repaired tree" >&2; reward=0
    else
      echo "ok: reproduction completes cleanly (exit 0) on the repaired tree"
    fi
  else
    echo "FAIL: reproduction did not exit 0 on the repaired tree" >&2
    tail -20 /tmp/repro_fix.out /tmp/repro_fix.err 2>/dev/null | sed 's/^/    /' >&2
    reward=0
  fi
fi

# ---------- 2. golden: the upstream regression test for this bug --------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN_DIR/unnecessary_default_type_args.py" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  # The golden file is baked into the image and the agent runs in the same
  # container, so it could retouch it to assert the buggy output. Pin its
  # content to the bytes extracted at build time from the fix commit.
  if [ "$(sha256sum "$GOLDEN_DIR/unnecessary_default_type_args.py" | cut -d' ' -f1)" != "$GOLDEN_PY_SHA" ]; then
    echo "FAIL: /opt/golden/ext/typing/unnecessary_default_type_args.py was tampered with (sha256 mismatch)" >&2; reward=0
  else
    echo "ok: golden file integrity confirmed"
    cp "$GOLDEN_DIR"/unnecessary_default_type_args.* "$SRC/tests/functional/ext/typing/"
    run_pytest "golden unnecessary_default_type_args" /tmp/golden.out \
      tests/test_functional.py -k unnecessary_default_type_args --confcutdir=/app/src/tests || true
    # restore the tree to its committed state (verifier-owned overlay)
    git -C "$SRC" checkout -q -- tests/functional/ext/typing/
  fi
fi

# ---------- 3. the project's own typing-extension functional tests -----------
echo "== the project's own typing-extension functional tests =="
run_pytest "typing-extension functional tests" /tmp/own.out \
  tests/test_functional.py -k "typing or redundant_typehint" --confcutdir=/app/src/tests || true

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  # --confcutdir isolates the hidden-case runs from any conftest.py the agent
  # might have dropped into the tree as a runtime-interception wrapper.
  if ( cd "$SRC" && python3 -m pytest "$case" -o addopts="" -q -p no:cacheprovider \
        --confcutdir=/tests > "$out" 2>&1 ); then
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

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0