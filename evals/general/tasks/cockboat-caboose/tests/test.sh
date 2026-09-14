#!/bin/bash
# Verifier for cockboat-caboose: an upstream-clone debugging task on
# psf/requests (issue #7309: a Content-Type header parameter without an '='
# crashes response-encoding resolution with "'bool' object has no attribute
# 'strip'" instead of falling back to ISO-8859-1 for text content).
#
# The agent must, in the real checkout at /app/src, fix the real upstream bug,
# and MUST have authored its own failing reproduction at /app/repro.py as a
# deliverable. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, exactly
#      one commit exists, the upstream fix commit is not reachable, no history
#      was fetched, no tracked file was deleted, the ONLY modified tracked file
#      is src/requests/utils.py with at least one modification, no untracked
#      files, no assume-unchanged/skip-worktree flags, no .git exclude tricks);
#   0.5 checks module origin: requests and the encoding resolver resolve under
#      /app/src/src in an isolated interpreter;
#   1. runs the agent's /app/repro.py against the REPAIRED tree -- must exit 0
#      and print the correct fallback encoding ISO-8859-1;
#   2. runs the SAME /app/repro.py against a pristine copy of the pre-fix tree
#      kept in the image -- must exit non-zero with the AttributeError
#      "'bool' object has no attribute 'strip'" signature;
#   3. directly asserts the fixed parsing/encoding semantics on /app/src;
#   4. runs the upstream regression test for this bug, extracted at image build
#      time from the FIX commit into /opt/golden/test_utils.py (SHA-256
#      digest-checked; copied over the tree's own test_utils.py because the
#      parent revision of that file still asserts the old buggy behaviour);
#   5. runs the project's own existing test modules test_structures,
#      test_help, test_packages, test_hooks;
#   6. runs authored hidden-case files over valueless/valued parameter
#      combinations that the upstream test does not use.
#
# Every suite runs through an isolated interpreter (python3 -I -S with an
# explicit sys.path of <tree>/src plus the resolved site-packages dir): the
# site module never runs, so sitecustomize.py, .pth hooks or replaced
# functions in site-packages are invisible to the verdict, and "requests" is
# imported straight from the deliverable tree.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt   # a stale/planted reward file must never survive into this run
reward=1

SRC=/app/src
REPRO=/app/repro.py
PARENT_SHA=bc7dd0fc4d56e808bcdd85ac2d797b3107c89259
FIX_SHA=f0198e6dfc431a2293dc16e1b1e8fcddc910a7f3
GOLDEN=/opt/golden/test_utils.py
GOLDEN_SHA256=16ab372c2a8d9613e6ac30a42725847c66c683a1240f33850861e87872175eb5
PREFIX_SRC=/opt/prefix-src

is_ok () { [ "$1" = 0 ]; }

# site-packages used by the default python3; resolved dynamically so the
# isolated launcher below sees the same installed packages pytest would.
SP="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))' 2>/dev/null || true)"
if [ -z "$SP" ] || [ ! -d "$SP/pytest" ]; then
  echo "FAIL: could not resolve the site-packages directory (SP='${SP:-<empty>}')" >&2
  reward=0
fi

iso_pytest () {  # iso_pytest LABEL OUT ...args   (pytest argv)
  label="$1"; out="$2"; shift 2
  if ( cd /tmp \
       && python3 -I -S -B -c "
import sys
sys.path[:0] = ['$SRC/src', '$SP']
import pytest
raise SystemExit(pytest.main(sys.argv[1:]))
" "$@" -c /dev/null --rootdir="$SRC" --confcutdir="$SRC/tests" -q -p no:cacheprovider > "$out" 2>&1 ) \
     && grep -qE '[1-9][0-9]* passed' "$out" \
     && ! grep -qE '[1-9][0-9]* failed|[1-9][0-9]* error' "$out"; then
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
ok_prov=1
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; ok_prov=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; ok_prov=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  ok_prov=0
else
  echo "ok: fix commit not reachable from the working clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  echo "FAIL: the working clone contains $ncommits commits; it must contain exactly the pinned parent commit" >&2
  ok_prov=0
else
  echo "ok: exactly one commit reachable in the working clone"
fi

aux_flag=$(git -C "$SRC" ls-files -v 2>/dev/null | awk '$1 ~ /^[hS]/ {print $1, $2}')
if [ -n "$aux_flag" ]; then
  echo "FAIL: assume-unchanged/skip-worktree flags are set on tracked files: $aux_flag" >&2
  ok_prov=0
else
  echo "ok: no hidden working-tree changes via assume-unchanged/skip-worktree"
fi

if awk 'NF && $1 !~ /^#/ {n++} END {exit !n}' "$SRC/.git/info/exclude" 2>/dev/null; then
  echo "FAIL: .git/info/exclude contains non-comment entries (files hidden from git status)" >&2
  ok_prov=0
else
  echo "ok: .git/info/exclude has no sneaky ignore rules"
fi

if git -C "$SRC" config --get core.excludesFile >/dev/null 2>&1; then
  echo "FAIL: core.excludesFile is set (files hidden from git status via a custom excludes file)" >&2
  ok_prov=0
else
  echo "ok: no core.excludesFile redirection"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M src/requests/utils.py") saw_mod=1 ;;
    "?? "*) echo "FAIL: an untracked file was added in the repository: $line" >&2; bad_tree=1 ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    " M "*) echo "FAIL: a tracked file outside src/requests/utils.py was modified: $line" >&2; bad_tree=1 ;;
    "!! "*) # ignored files: only pytest/bytecode/interpreter caches are benign
      case "$(printf '%s' "$line" | sed 's/^!! //')" in
        *__pycache__*|*.pyc|.pytest_cache*|*.egg-info*|.coverage) : ;;
        *) echo "FAIL: an unexpected ignored/planted file is present in the repository: $line" >&2; bad_tree=1 ;;
      esac ;;
    "A "*) echo "FAIL: a tracked file was staged/added: $line" >&2; bad_tree=1 ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain --ignored --untracked-files=all 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then
  reward=0; ok_prov=0
else
  echo "ok: no unexpected working-tree changes"
fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0; ok_prov=0
else
  echo "ok: at least one modification in src/requests/utils.py"
fi

# ---------- 0.5 module origin: the verdict must measure /app/src --------------
echo "== module origin (isolated interpreter) =="
if python3 -I -S -c "
import sys, inspect
sys.path[:0] = ['$SRC/src', '$SP']
import requests
import requests.utils as u
af = requests.__file__
cf = inspect.getsourcefile(u.get_encoding_from_headers)
print('requests file:', af)
print('encoding resolver source file:', cf)
assert af.startswith('$SRC/src/'), af
assert cf is not None and cf.startswith('$SRC/src/'), cf
" > /tmp/origin.out 2>&1; then
  echo "ok: requests and the encoding resolver both resolve under $SRC/src"
  sed 's/^/    /' /tmp/origin.out
else
  echo "FAIL: requests does not resolve to the deliverable under an isolated interpreter:" >&2
  cat /tmp/origin.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 1. the agent's reproduction against the REPAIRED tree -------------
echo "== reproduction against the repaired tree =="
if [ ! -f "$REPRO" ]; then
  echo "FAIL: the deliverable /app/repro.py does not exist" >&2
  reward=0
elif ( cd /tmp && timeout 120 python3 -I -S -c "
import sys
sys.path[:0] = ['$SRC/src', '$SP']
code = compile(open('$REPRO').read(), '$REPRO', 'exec')
exec(code)
" > /tmp/repro-pass.out 2>&1 ) && grep -q 'ISO-8859-1' /tmp/repro-pass.out; then
  echo "ok: /app/repro.py exits 0 and resolves the encoding to ISO-8859-1"
  sed 's/^/    /' /tmp/repro-pass.out
else
  echo "FAIL: /app/repro.py does not exit 0 and print the correct encoding ISO-8859-1..." >&2
  tail -30 /tmp/repro-pass.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 2. the agent's reproduction against the PRE-FIX tree --------------
echo "== reproduction against the pristine pre-fix tree =="
if [ ! -f "$REPRO" ]; then
  : # already failed in step 1
elif ( cd /tmp && timeout 120 python3 -I -S -c "
import sys
sys.path[:0] = ['$PREFIX_SRC/src', '$SP']
code = compile(open('$REPRO').read(), '$REPRO', 'exec')
exec(code)
" > /tmp/repro-prefix.out 2>&1 ); then
  echo "FAIL: /app/repro.py exits 0 on the pristine PRE-FIX tree: it does not actually reproduce the bug" >&2
  reward=0
elif grep -q "AttributeError" /tmp/repro-prefix.out \
     && grep -q "has no attribute 'strip'" /tmp/repro-prefix.out; then
  echo "ok: /app/repro.py crashes on the pristine pre-fix tree with the expected signature"
  grep -m1 "AttributeError" /tmp/repro-prefix.out | sed 's/^/    /'
else
  echo "FAIL: /app/repro.py fails on the pristine pre-fix tree, but not with the expected bug signature:" >&2
  tail -30 /tmp/repro-prefix.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 3. direct semantics assertion on the repaired tree ----------------
echo "== direct semantics assertion =="
if python3 -I -S -c "
import sys
sys.path[:0] = ['$SRC/src', '$SP']
from requests.utils import _parse_content_type_header, get_encoding_from_headers
r = _parse_content_type_header('text/html; charset')
assert r == ('text/html', {}), r
e = get_encoding_from_headers({'content-type': 'text/html; charset'})
assert e == 'ISO-8859-1', e
assert _parse_content_type_header('text/html; charset=UTF-8') == ('text/html', {'charset': 'UTF-8'}), 'valued parameters must survive'
assert get_encoding_from_headers({'content-type': 'text/html; charset=UTF-8'}) == 'UTF-8'
assert _parse_content_type_header('multipart/form-data; boundary=q; no_equals') == ('multipart/form-data', {'boundary': 'q'})
print('ok: parser drops valueless parameters and keeps valued ones')
" > /tmp/direct.out 2>&1; then
  cat /tmp/direct.out
else
  echo "FAIL: the fixed parsing semantics do not hold on /app/src:" >&2
  tail -20 /tmp/direct.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 3b. source-level parser assertion ---------------------------------
# The fixed semantics must hold in the TRACKED FILE BYTES THEMSELVES, compiled
# in isolation: parse /app/src/src/requests/utils.py with ast, take the
# module's own FunctionDef for _parse_content_type_header, compile and run it
# standalone, and assert the semantics. Nothing that shadows the name at
# import time can influence this verdict -- a site-packages helper, a trailing
# `from x import _parse_content_type_header`, an exec()/globals() rebinding, a
# .pth hook or a swapped sitecustomize all change what the module IMPORT
# produces, never what the file's own definition computes when compiled from
# these bytes. A repair implemented anywhere other than the real definition in
# this tracked file (e.g. a fake definition that leaves the buggy body in
# place) therefore still fails here, even though it can satisfy the imported
# semantics checks above.
echo "== source-level parser assertion (clean compile of tracked bytes) =="
if python3 -I -S - <<'PY' > /tmp/srcparse.out 2>&1
import ast
import pathlib

SRC = pathlib.Path('/app/src/src/requests/utils.py')
text = SRC.read_text()
tree = ast.parse(text)

fndefs = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "_parse_content_type_header"]
rebinds = []
for node in tree.body:
    if isinstance(node, (ast.Import, ast.ImportFrom)):
        for a in getattr(node, "names", []):
            nm = (a.asname or a.name).split(".")[0]
            if nm == "_parse_content_type_header":
                rebinds.append(ast.unparse(node))
    elif isinstance(node, ast.Assign):
        for tgt in node.targets:
            if isinstance(tgt, ast.Name) and tgt.id == "_parse_content_type_header":
                rebinds.append(ast.unparse(node))

assert len(fndefs) == 1, f"expected exactly one def, found {len(fndefs)}"
assert not rebinds, f"name rebound outside its def: {rebinds}"

fn = fndefs[0]
ns = {}
exec(compile(ast.unparse(fn), "<utils.py:_parse_content_type_header>", "exec"), ns)
f = ns["_parse_content_type_header"]

cases = [
    ("text/html; charset", ("text/html", {})),
    ("text/plain; charset", ("text/plain", {})),
    ("text/html; charset=UTF-8", ("text/html", {"charset": "UTF-8"})),
    ("multipart/form-data; boundary=q; no_equals", ("multipart/form-data", {"boundary": "q"})),
    ("multipart/form-data; boundary = something", ("multipart/form-data", {"boundary": "something"})),
    ('text/html; charset="utf-8"; foo', ("text/html", {"charset": "utf-8"})),
    ("application/json ; Charset = utf-8", ("application/json", {"charset": "utf-8"})),
]
for header, expected in cases:
    got = f(header)
    assert got == expected, (header, got, expected)

_ct, params = f("text/plain; a; b; c=d")
assert params == {"c": "d"} and all(not isinstance(v, bool) for v in params.values()), params
print("ok: tracked-file definition of _parse_content_type_header implements the fixed semantics")
PY
then
  cat /tmp/srcparse.out
else
  echo "FAIL: the tracked-file definition of _parse_content_type_header does not itself implement the fixed semantics (shadowed, partial or relocated fix):" >&2
  tail -20 /tmp/srcparse.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 4. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
  echo "FAIL: /opt/golden/test_utils.py does not match the bytes extracted from the upstream fix commit" >&2
  reward=0
else
  cp "$GOLDEN" "$SRC/tests/test_utils.py"
  iso_pytest "golden tests/test_utils.py (from the fix commit)" /tmp/golden.out \
    "$SRC/tests/test_utils.py" || true
fi

# ---------- 5. the project's own existing test modules ------------------------
echo "== the project's own existing test modules =="
iso_pytest "test_structures/test_help/test_packages/test_hooks" /tmp/own.out \
  "$SRC/tests/test_structures.py" "$SRC/tests/test_help.py" \
  "$SRC/tests/test_packages.py" "$SRC/tests/test_hooks.py" || true

# ---------- 6. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd /tmp \
       && python3 -I -S -B -c "
import sys
sys.path[:0] = ['$SRC/src', '$SP']
import pytest
raise SystemExit(pytest.main(sys.argv[1:]))
" "$case" -c /dev/null --rootdir="$SRC" -q -p no:cacheprovider > "$out" 2>&1 ) \
     && grep -qE '[1-9][0-9]* passed' "$out" \
     && ! grep -qE '[1-9][0-9]* failed|[1-9][0-9]* error' "$out"; then
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