#!/bin/bash
# Verifier for luff-yard: an upstream-clone debugging task on
# pallets/werkzeug.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# WWWAuthenticate.to_header leaves a trailing space when the challenge has
# neither parameters nor a token ('Bearer ' instead of 'Bearer'), so strict
# HTTP/1.1 stacks reject the header. The agent must also write its own
# failing reproduction at /app/reproduce_www_authenticate_bug.py and fix the
# tree. The verifier:
#   0. asserts tree provenance (HEAD still the pinned parent commit, the
#      upstream fix commit not reachable from the working clone, exactly one
#      commit in the clone, no tracked file deleted, only source files under
#      src/werkzeug/ modified with at least one such modification, the tree's
#      own test files untouched, `import werkzeug` resolves to the checkout,
#      and the fix is genuinely present in the checked-out source);
#   1. runs the agent's reproduction against a pristine pre-fix tree
#      (restored through git stash) and requires it to FAIL, then against the
#      repaired tree and requires it to PASS;
#   2. overlays and runs the project's own upstream regression test
#      (extracted at image build time from the fix commit into /opt/golden),
#      then restores the tree's own copy;
#   3. runs the project's own existing suites (tests/test_http.py and
#      tests/test_datastructures.py), proving the fix broke nothing else;
#   4. runs two authored hidden cases: a parameterless-challenge scheme
#      matrix with strict token grammar, and a guard that parameterised and
#      token challenges still serialize exactly as before.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
REPRO=/app/reproduce_www_authenticate_bug.py
PARENT_SHA=795f4eaf6ef1fdc2fd1d7114c61ad384ede4322c
FIX_SHA=051fd66352cf8b3f0797249858068dedaead6d39
GOLDEN=/opt/golden/test_http.py
GOLDEN_SHA=c0c6cb1f0074b921cc2765b5d2e15d716ff9966890fcb719e64b0749be92a932

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
# porcelain is "XY path" with X=staged, Y=worktree; the agent may legitimately
# `git add` its fix, so a modified file must count in either column.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  x=${line:0:1}; y=${line:1:1}; path=${line:3}
  case "$x$y" in
    \?\?)
      # an untracked file inside the repository: any such file is either
      # workspace clutter or a cheat vector (a root conftest.py or a
      # repo-local sitecustomize.py that skips tests or wraps imports).
      # Legitimate agent runs leave none: bytecode artifacts are gitignored
      # by the upstream .gitignore and the workspace contract is that the
      # only changes are modified files under src/werkzeug/.
      echo "FAIL: an untracked file was added inside the repository: $path (the only permitted changes are modified files under src/werkzeug/)" >&2; bad_tree=1
      ;;
    *D*)
      echo "FAIL: a tracked file was deleted: $path" >&2; bad_tree=1
      ;;
    A*) # a newly added tracked file
      echo "FAIL: a new tracked file was added: $path" >&2; bad_tree=1
      ;;
    *M*) # modified (staged, worktree, or both), excluding delete/add cases
      case "$path" in
        src/werkzeug/*)
          saw_mod=1
          ;;
        tests/*)
          echo "FAIL: tracked test file was modified by the agent: $path" >&2; bad_tree=1 ;;
        *)
          echo "FAIL: a tracked file outside src/werkzeug/ was modified: $path" >&2; bad_tree=1 ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
else
  echo "ok: at least one source file under src/werkzeug/ is modified"
fi

if ! ( cd / && python3 -c "import werkzeug; import sys; sys.exit(0 if werkzeug.__file__ == '$SRC/src/werkzeug/__init__.py' else 3)" >/dev/null 2>&1 ); then
  echo "FAIL: 'import werkzeug' does not resolve to the checked-out tree at /app/src" >&2
  reward=0
else
  echo "ok: import werkzeug resolves to $SRC/src/werkzeug/__init__.py"
fi

# The fix must live in the checked-out source itself. Without this check, a
# wrapper (a sitecustomize.py in site-packages, a monkeypatch module, ...) can
# make every behavioural check pass while the actual checked-out source still
# contains the buggy path.
#
# This check is AST-based, not regex-based: a textual fake (the guard text
# inside a comment or a dead string-literal statement) no longer passes. The
# guard must be a REAL `if not self.parameters:` If-node, a direct statement
# of WWWAuthenticate.to_header's body, positioned strictly between the token
# branch and the digest branch, whose body is exactly `return self.type.title()`
# (the canonical upstream fix). Exactly one such guard may exist file-wide.
shape=$(python3 - "$SRC/src/werkzeug/datastructures/auth.py" <<'PY'
import ast, sys
src = open(sys.argv[1]).read()
try:
    tree = ast.parse(src)
except SyntaxError as e:
    print("SYNTAXERROR:%s" % e)
    raise SystemExit
cls = next((n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "WWWAuthenticate"), None)
if cls is None:
    print("NOAUTHDEF")
    raise SystemExit
fn = next((n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == "to_header"), None)
if fn is None:
    print("NOFUNC")
    raise SystemExit
body = list(fn.body)

def is_token_if(n):
    return (isinstance(n, ast.If)
            and isinstance(n.test, ast.Compare)
            and isinstance(n.test.left, ast.Attribute)
            and n.test.left.attr == "token"
            and n.test.ops and isinstance(n.test.ops[0], (ast.Is, ast.IsNot))
            and any(isinstance(c, ast.Constant) and c.value is None for c in n.test.comparators)
            and len(n.body) == 1 and isinstance(n.body[0], ast.Return))

def is_guard_if(n):
    if not (isinstance(n, ast.If)
            and isinstance(n.test, ast.UnaryOp) and isinstance(n.test.op, ast.Not)
            and isinstance(n.test.operand, ast.Attribute)
            and n.test.operand.attr == "parameters"):
        return False
    if len(n.body) != 1 or not isinstance(n.body[0], ast.Return):
        return False
    r = n.body[0].value
    return (isinstance(r, ast.Call) and len(r.args) == 0 and not r.keywords
            and isinstance(r.func, ast.Attribute) and r.func.attr == "title"
            and isinstance(r.func.value, ast.Attribute) and r.func.value.attr == "type")

def is_digest_if(n):
    return (isinstance(n, ast.If) and isinstance(n.test, ast.Compare)
            and isinstance(n.test.left, ast.Attribute)
            and n.test.left.attr == "type"
            and any(isinstance(c, ast.Constant) and c.value == "digest" for c in n.test.comparators))

if_idx = {i: n for i, n in enumerate(body) if isinstance(n, ast.If)}
tok_i   = next((i for i, n in if_idx.items() if is_token_if(n)), None)
guard_i = next((i for i, n in if_idx.items() if is_guard_if(n)), None)
digest_i = next((i for i, n in if_idx.items() if is_digest_if(n)), None)

guards_total = sum(1 for n in ast.walk(tree)
                   if isinstance(n, ast.If)
                   and isinstance(n.test, ast.UnaryOp)
                   and isinstance(n.test.op, ast.Not)
                   and isinstance(n.test.operand, ast.Attribute)
                   and n.test.operand.attr == "parameters")

if (tok_i is not None and guard_i is not None and digest_i is not None
        and tok_i < guard_i < digest_i and guards_total == 1):
    print("OK")
else:
    print("BAD tok=%s guard=%s digest=%s guards_total=%s" % (tok_i, guard_i, digest_i, guards_total))
PY
)
case "$shape" in
  OK) echo "ok: auth.py carries the genuine no-parameter guard inside WWWAuthenticate.to_header" ;;
  *) echo "FAIL: the checked-out source does not contain the real fix in WWWAuthenticate.to_header (shape=$shape)" >&2; reward=0 ;;
esac

# The fix must also survive an interpreter that cannot load site-packages
# wrappers. Run the behaviour probe with `site` import disabled (-S): a
# sitecustomize.py / usercustomize.py / .pth wrapper (the classic fake) is
# never executed there, so only the checked-out source itself can produce the
# correct value. site-packages stays reachable through PYTHONPATH so the
# project's own dependencies (e.g. markupsafe) still import, but -S skips all
# site processing, so any monkeypatch living in site-packages is invisible.
SP=$(python3 -c "import site; print(site.getsitepackages()[0])")
if ( cd / && PYTHONPATH="$SRC/src:$SP" \
     python3 -S -c "from werkzeug.datastructures import WWWAuthenticate; h = WWWAuthenticate('bearer').to_header(); raise SystemExit(0 if h == 'Bearer' else 3)" >/dev/null 2>&1 ); then
  echo "ok: parameterless serialization correct with site-packages wrappers disabled (-S)"
else
  echo "FAIL: the correct value is not produced by the checked-out source alone - the fix must live in the tree (/app/src), not in a runtime wrapper in site-packages" >&2
  reward=0
fi

# ---------- 1. the agent's own reproduction, both directions ------------------
echo "== agent reproduction vs pristine pre-fix tree =="
if [ ! -s "$REPRO" ]; then
  echo "FAIL: deliverable $REPRO is missing or empty" >&2; reward=0
else
  # Temporarily restore the buggy sources. Provenance above requires the fix
  # to be uncommitted working-tree changes (HEAD is still the parent commit),
  # so a stash removes exactly the fix and leaves the pristine pre-fix tree.
  stash_before=$(git -C "$SRC" stash list 2>/dev/null | wc -l)
  if git -C "$SRC" stash push -q -m verifier-tmp 2>/dev/null; then
    stash_after=$(git -C "$SRC" stash list 2>/dev/null | wc -l)
    if [ "$stash_after" -gt "$stash_before" ]; then
      if python3 "$REPRO" > /tmp/repro-pristine.out 2>&1; then
        echo "FAIL: the reproduction PASSED on the pristine pre-fix tree; a correct reproduction must fail while the tree still contains the bug" >&2
        cat /tmp/repro-pristine.out | sed 's/^/    /' >&2
        reward=0
      else
        echo "ok: reproduction fails on the pristine pre-fix tree (non-zero exit as required)"
        cat /tmp/repro-pristine.out | sed 's/^/    /'
      fi
      if ! git -C "$SRC" stash pop -q 2>/dev/null; then
        echo "FAIL: could not restore the agent's fix after the pristine-tree run" >&2
        reward=0
      else
        echo "ok: agent's fix restored"
      fi
    else
      echo "FAIL: nothing was stashed; the fix must be uncommitted working-tree changes in src/werkzeug/ (provenance above also requires them)" >&2
      reward=0
    fi
  else
    echo "FAIL: git stash failed" >&2
    reward=0
  fi
fi

echo "== agent reproduction vs repaired tree =="
if [ -s "$REPRO" ]; then
  if python3 "$REPRO" > /tmp/repro-fixed.out 2>&1; then
    echo "ok: reproduction passes on the repaired tree"
    cat /tmp/repro-fixed.out | sed 's/^/    /'
  else
    echo "FAIL: the reproduction still fails on the repaired tree" >&2
    cat /tmp/repro-fixed.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

# ---------- 2. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
  echo "FAIL: /opt/golden/test_http.py was tampered with (sha256 mismatch)" >&2; reward=0
else
  echo "ok: golden file integrity confirmed"
  cp "$GOLDEN" "$SRC/tests/test_http.py"
  run_pytest "golden test_www_authenticate_header" /tmp/golden.out \
    "tests/test_http.py::TestHTTPUtility::test_www_authenticate_header" || true
  run_pytest "tests/test_http.py with golden regression overlaid" /tmp/golden-full.out \
    tests/test_http.py || true
  if git -C "$SRC" checkout -- tests/test_http.py 2>/dev/null; then
    echo "ok: tree's own tests/test_http.py restored"
  else
    echo "FAIL: could not restore the tree's own tests/test_http.py" >&2; reward=0
  fi
fi

# ---------- 3. the project's own existing suites ------------------------------
echo "== the project's own existing test suites =="
run_pytest "tests/test_http.py" /tmp/own-http.out tests/test_http.py || true
run_pytest "tests/test_datastructures.py" /tmp/own-ds.out tests/test_datastructures.py || true

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  # --confcutdir isolates the hidden-case runs from anything in the tree.
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