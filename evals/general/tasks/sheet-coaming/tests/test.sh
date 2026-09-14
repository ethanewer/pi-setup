#!/bin/bash
# Verifier for sheet-coaming: an upstream-clone debugging task on PyCQA/bandit.
#
# The agent must repair, in the real checkout at /app/src, a real upstream bug
# (PyCQA/bandit issue #764): scanning Python that calls Django's raw-SQL
# expression helper (RawSQL) with the SQL text passed as a keyword argument
# makes the django_rawsql_used plugin raise IndexError ("list index out of
# range"), which bandit logs as "Bandit internal error running: ..." on
# stderr and continues past, so the risky call is never reported. The
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no history
#      was fetched, no tracked file was deleted, no new files were added under
#      bandit/, only source files under bandit/ are modified with at least one
#      modification present, no import-time wrapper, `import bandit` resolves
#      to the checked-out tree, and the unguarded `sql = context.node.args[0]`
#      indexing is gone from the plugin with a guard in its place);
#   1. runs the agent's own reproduction deliverable /app/repro.py twice: on
#      the repaired tree it must exit 0 AND its printed scan output must
#      contain the raw-SQL finding (B611), and with the pristine pre-fix tree
#      at /opt/pretree on the import path it must exit non-zero and print the
#      internal-error evidence;
#   2. runs the project's own upstream regression material for this behaviour,
#      reconstructed byte-exactly by the verifier from the sha-pinned pristine
#      pre-fix tree at /opt/pretree (no fix-commit bytes exist in the image)
#      and overlaid onto a throwaway copy of the tree (so the working tree is
#      never touched by the harness);
#   3. runs the project's own existing test suite from the tree, proving the
#      fix broke nothing else;
#   4. runs four authored hidden-case files (keyword-style variants,
#      keyword-order/nested shapes, keyword-constant guards that must stay
#      unflagged, and positional guard shapes) plus the verifier's own scans
#      of the same shapes: the
#      pre-fix tree must still show the internal error on every trigger
#      shape, and the repaired tree must show none on any shape while
#      reporting exactly the expected B611 findings.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PRETREE=/opt/pretree
REPRO=/app/repro.py
PARENT_SHA=6d6ec6d550ef3ce1c7b6b04a56931bac65e94f71
FIX_SHA=c420d1d5356f6979b7af3cc46bd182f3ac9edaeb
PARENT_PLUGIN_SHA=1193a0a0a1156cf4c882175b2270df6d5c110caad0e6da64dbb98e0e6866372f
# sha256 the verifier's RECONSTRUCTION of the fix-commit material must match:
# the fix-commit revision of tests/functional/test_functional.py and of
# examples/django_sql_injection_raw.py. Because the fix commit only changed
# two example lines and one expected count relative to the parent revision,
# reconstructing from the sha-pinned pristine tree is byte-exact.
GOLDEN_TEST_SHA=ca42f12021717da9daaacb620403ffe5ec9b1680f50820db8596a2af43660914
GOLDEN_EXAMPLE_SHA=4d04b972eaf70c7076ffee0c556d6af93bf2ab8427da78d2f64efb35a2afae61
SHA_KW_VARIANTS=f9654fcd97511ceb8a6ccb61c024481b6a5204e5c281850737c14846768c5ff9
SHA_ORDER=378d659998c5fd4e454234bed4ba4520604eba1425e6f85960626b47480fde1a
SHA_GUARDS=6c396e6eaff8dfdc56b199f7e576110b489f9327c45f1214b58a848530cde82a
SHA_KW_CONST=8f5e0b9a836bc28a8071db00970ef481c522112853a4dc3b2ca937536b1e3331

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
    *.testrepository*) continue ;;
  esac
  x=${line:0:1}; y=${line:1:1}; path=${line:3}
  case "$x$y" in
    \?\?)
      # untracked files are allowed only outside the bandit package
      case "$path" in
        bandit/*)
          echo "FAIL: a new file was added inside the bandit package: $path" >&2; bad_tree=1 ;;
        *) : ;;
      esac
      ;;
    *D*)
      echo "FAIL: a tracked file was deleted: $path" >&2; bad_tree=1
      ;;
    A*) # newly added tracked file (staged add, possibly also modified)
      echo "FAIL: a new tracked file was added: $path" >&2; bad_tree=1
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

# The fix must live in the plugin source itself. The buggy line is the
# unconditional `sql = context.node.args[0]` inside django_rawsql_used; any
# repair must remove that exact form and guard the positional-argument
# access in its place (either by branching on args or by catching the
# indexing failure). If the plugin still contains the bare unconditional
# indexing, no repair happened.
shape=$(python3 - "$SRC/bandit/plugins/django_sql_injection.py" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
if re.search(r"^\s{12}sql = context\.node\.args\[0\]\s*$", src, re.M):
    print("BUGGY")
elif "if context.node.args:" in src or "except" in src:
    print("OK")
else:
    print("NOGUARD")
PY
)
case "$shape" in
  OK) echo "ok: the unguarded indexing is gone from the plugin and a guard on the positional-argument access is present" ;;
  BUGGY) echo "FAIL: the unguarded buggy indexing is still present in bandit/plugins/django_sql_injection.py" >&2; reward=0 ;;
  *) echo "FAIL: no guard on the positional args is present in the plugin; the fix must be in the code, not in a wrapper" >&2; reward=0 ;;
esac

# ---------- pre-fix reference tree integrity ---------------------------------
echo "== pre-fix reference tree =="
if [ "$(git -C "$PRETREE" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /opt/pretree HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: /opt/pretree HEAD is $PARENT_SHA"
fi
psha=$(sha256sum "$PRETREE/bandit/plugins/django_sql_injection.py" 2>/dev/null | cut -d' ' -f1)
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
  if ( cd /tmp && python3 "$REPRO" > /tmp/repro-fixed.out 2>&1 ); then
    echo "ok: /app/repro.py exits 0 on the repaired tree"
  else
    echo "FAIL: /app/repro.py exits non-zero on the repaired tree" >&2
    tail -60 /tmp/repro-fixed.out | sed 's/^/    /' >&2
    reward=0
  fi
  # the scan the reproduction performs must actually report the raw-SQL
  # finding on the repaired tree (non-vacuity: it must exercise the
  # vulnerable behaviour, not an empty file or an unrelated call)
  if grep -q "B611" /tmp/repro-fixed.out && grep -q "Use of RawSQL" /tmp/repro-fixed.out; then
    echo "ok: the reproduction's scan reports the raw-SQL finding (B611) on the repaired tree"
  else
    echo "FAIL: the reproduction's scan reports no B611 raw-SQL finding on the repaired tree" >&2
    tail -60 /tmp/repro-fixed.out | sed 's/^/    /' >&2
    reward=0
  fi
  if grep -q "internal error" /tmp/repro-fixed.out; then
    echo "FAIL: the reproduction's scan still logs an internal error on the repaired tree" >&2
    reward=0
  else
    echo "ok: no internal error in the reproduction's repaired-tree scan"
  fi

  echo "== agent reproduction, pre-fix tree =="
  ( cd /tmp && PYTHONPATH="$PRETREE" python3 "$REPRO" > /tmp/repro-pretree.out 2>&1 )
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: /app/repro.py exits 0 against the pre-fix tree; a reproduction of the bug must fail while the bug is present" >&2
    tail -60 /tmp/repro-pretree.out | sed 's/^/    /' >&2
    reward=0
  elif ! grep -q "internal error" /tmp/repro-pretree.out; then
    echo "FAIL: the pre-fix run of /app/repro.py printed no 'internal error' evidence; the reproduction does not demonstrate the bug" >&2
    tail -60 /tmp/repro-pretree.out | sed 's/^/    /' >&2
    reward=0
  else
    echo "ok: /app/repro.py exits non-zero against the pre-fix tree and prints the internal-error evidence"
  fi
fi

# ---------- 2. golden: upstream regression material --------------------------
# No fix-commit bytes exist in the image. The verifier RECONSTRUCTS the
# fix-commit revision of the regression material from the sha-pinned pristine
# pre-fix tree (/opt/pretree): the fix commit added only the two
# keyword-argument calls to examples/django_sql_injection_raw.py and raised
# the expected Medium count of test_django_sql_injection_raw from 4 to 6. The
# reconstruction is checked against the fix-commit file shas, so any tampering
# with /opt/pretree or with this reconstruction fails closed.
echo "== upstream regression material =="
rm -f /tmp/golden-test.py /tmp/golden-example.py
python3 - "$PRETREE" /tmp/golden-test.py <<'PY'
import re, sys
pretree, out = sys.argv[1], sys.argv[2]
src = open(pretree + "/tests/functional/test_functional.py").read()
start = src.index("    def test_django_sql_injection_raw")
m = re.search(r"\n    def ", src[start + 1:])
end = start + 1 + m.start() if m else len(src)
seg = src[start:end]
old = ('            "SEVERITY": {"UNDEFINED": 0, "LOW": 0, "MEDIUM": 4, "HIGH": 0},\n'
       '            "CONFIDENCE": {"UNDEFINED": 0, "LOW": 0, "MEDIUM": 4, "HIGH": 0},')
new = ('            "SEVERITY": {"UNDEFINED": 0, "LOW": 0, "MEDIUM": 6, "HIGH": 0},\n'
       '            "CONFIDENCE": {"UNDEFINED": 0, "LOW": 0, "MEDIUM": 6, "HIGH": 0},')
assert old in seg, "parent regression test shape not found; pretree is not the pristine parent tree"
open(out, "w").write(src[:start] + seg.replace(old, new) + src[end:])
PY
cp "$PRETREE/examples/django_sql_injection_raw.py" /tmp/golden-example.py
cat >> /tmp/golden-example.py <<'EOF'
User.objects.annotate(val=RawSQL(sql='{}secure'.format('no'), params=[]))
User.objects.annotate(val=RawSQL(params=[], sql='{}secure'.format('no')))
EOF
gs1=$(sha256sum /tmp/golden-test.py 2>/dev/null | cut -d' ' -f1)
gs2=$(sha256sum /tmp/golden-example.py 2>/dev/null | cut -d' ' -f1)
if [ "$gs1" != "$GOLDEN_TEST_SHA" ] || [ "$gs2" != "$GOLDEN_EXAMPLE_SHA" ]; then
  echo "FAIL: reconstructed regression material does not match the fix-commit revision" >&2
  echo "      (test sha $gs1, example sha $gs2); /opt/pretree is not pristine or the reconstruction is broken" >&2
  reward=0
else
  echo "ok: reconstruction of the fix-commit regression material is byte-exact (sha256 pinned)"
  rm -rf /tmp/grun
  cp -a "$SRC" /tmp/grun
  cp /tmp/golden-test.py /tmp/grun/tests/functional/test_functional.py
  cp /tmp/golden-example.py /tmp/grun/examples/django_sql_injection_raw.py
  if ( cd /tmp/grun && python3 -m stestr run --concurrency 1 \
        tests.functional.test_functional.FunctionalTests.test_django_sql_injection_raw \
        > /tmp/golden.out 2>&1 ); then
    echo "ok: golden test test_django_sql_injection_raw passes"
  else
    echo "FAIL: golden test test_django_sql_injection_raw failed" >&2
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
    */case-keyword-variants/*) want="$SHA_KW_VARIANTS" ;;
    */case-arg-order/*) want="$SHA_ORDER" ;;
    */case-guards/*) want="$SHA_GUARDS" ;;
    */case-kw-constant/*) want="$SHA_KW_CONST" ;;
    *) echo "unknown hidden test file: $f"; return 1 ;;
  esac
  [ "$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)" = "$want" ]
}

# scan_bandit TREE FILE OUTPREFIX  ->  runs bandit -f json; sets rc and writes
# $OUTPREFIX.json (results) and $OUTPREFIX.err (bandit stderr). TREE is
# "fixed" (run from /app/src as installed) or "pretree" (PYTHONPATH override).
scan_bandit () {
  local tree=$1 f=$2 pre=$3
  if [ "$tree" = fixed ]; then
    ( cd /tmp && python3 -m bandit -f json "$f" > "$pre.json" 2> "$pre.err" )
  else
    ( cd /tmp && PYTHONPATH="$PRETREE" python3 -m bandit -f json "$f" > "$pre.json" 2> "$pre.err" )
  fi
  rc=$?
  return $rc
}

n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  expected="" ; expected_rc=0
  case "$name" in
    case-keyword-variants) expected="5:B611:MEDIUM 10:B611:MEDIUM 11:B611:MEDIUM"; expected_rc=1 ;;
    case-arg-order)       expected="5:B611:MEDIUM 8:B611:MEDIUM 11:B611:MEDIUM"; expected_rc=1 ;;
    case-guards)          expected="6:B611:MEDIUM"; expected_rc=1 ;;
    # keyword-constant guard: SQL passed as an unchanging literal must stay
    # unflagged, matching the upstream ast.Str semantics (a faithful fix must
    # read and evaluate the keyword's literal, not blanket-flag kw calls).
    case-kw-constant)     expected="" ; expected_rc=0 ;;
    *) echo "FAIL: unknown hidden case dir: $name" >&2; reward=0; continue ;;
  esac
  tainted=0
  for tf in "$case"*.py; do
    [ -f "$tf" ] || continue
    if ! hidden_sha_ok "$tf"; then
      echo "FAIL: hidden test file was tampered with: $tf" >&2; tainted=1; reward=0
    fi
  done
  if [ "$tainted" = 0 ]; then
    # repaired tree: correct findings, correct exit status, no internal error
    for tf in "$case"*.py; do
      [ -f "$tf" ] || continue
      scan_bandit fixed "$tf" "/tmp/h-${name}-fixed"
      rc=$?
      if [ "$rc" != "$expected_rc" ]; then
        echo "FAIL: hidden case $name: bandit exit $rc != expected $expected_rc on $(basename "$tf")" >&2
        reward=0
      fi
      if grep -q "internal error" "/tmp/h-${name}-fixed.err"; then
        echo "FAIL: hidden case $name: internal error on repaired tree for $(basename "$tf")" >&2
        reward=0
      fi
      got=$(python3 - "/tmp/h-${name}-fixed.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
out = " ".join(f'{r["line_number"]}:{r["test_id"]}:{r["issue_severity"]}' for r in sorted(d["results"], key=lambda r: r["line_number"]))
print(out)
PY
)
      if [ "$got" != "$expected" ]; then
        echo "FAIL: hidden case $name: findings on repaired tree [$got] != expected [$expected]" >&2
        reward=0
      else
        echo "ok: hidden case $name on the repaired tree"
      fi
    done
    # pre-fix tree: trigger shapes must still show the internal error; guard
    # shapes must produce exactly the same findings on both trees (constant
    # literals stay unflagged, positional variable calls stay flagged) with
    # no internal error
    for tf in "$case"*.py; do
      [ -f "$tf" ] || continue
      scan_bandit pretree "$tf" "/tmp/h-${name}-pretree"
      nerr=$(grep -c "internal error" "/tmp/h-${name}-pretree.err" || true)
      got_pretree=$(python3 - "/tmp/h-${name}-pretree.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
out = " ".join(f'{r["line_number"]}:{r["test_id"]}:{r["issue_severity"]}' for r in sorted(d["results"], key=lambda r: r["line_number"]))
print(out)
PY
)
      case "$name" in
        case-guards)
          if [ "$nerr" -ge 1 ]; then
            echo "FAIL: hidden case $name: pre-fix tree showed an internal error for guard shape $(basename "$tf")" >&2
            reward=0
          elif [ "$got_pretree" != "$expected" ]; then
            echo "FAIL: hidden case $name: pre-fix findings [$got_pretree] differ from the repaired-tree expectation [$expected]" >&2
            reward=0
          else
            echo "ok: hidden case $name (guard) behaves identically on the pre-fix tree"
          fi
          ;;
        *)
          if [ "$nerr" -lt 1 ]; then
            echo "FAIL: hidden case $name: pre-fix tree showed no internal error for trigger shape $(basename "$tf")" >&2
            tail -8 "/tmp/h-${name}-pretree.err" | sed 's/^/    /' >&2
            reward=0
          else
            echo "ok: hidden case $name still crashes internally on the pre-fix tree"
          fi
          ;;
      esac
    done
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "== verifier's own scans =="
rm -rf /tmp/snippets
mkdir -p /tmp/snippets/triggers /tmp/snippets/kwconst /tmp/snippets/guards
python3 - >/dev/null <<'PY'
import pathlib
trig = {
    "kw_single": "from django.db.models.expressions import RawSQL\nfrom django.contrib.auth.models import User\nraw = 'X' or ''\nUser.objects.annotate(val=RawSQL(sql=raw, params=[]))\n",
    "kw_flipped": "from django.db.models.expressions import RawSQL\nfrom django.contrib.auth.models import User\nUser.objects.annotate(val=RawSQL(params=[], sql='a' or 'b'))\n",
    "kw_multiline": "from django.db.models.expressions import RawSQL\nfrom django.contrib.auth.models import User\nUser.objects.annotate(val=RawSQL(\n    sql='{}'.format('x'),\n    params=[],\n))\n",
}
# keyword-constant guards: SQL passed as an unchanging literal by keyword must
# stay unflagged on the repaired tree (upstream ast.Str semantics -- the fix
# must read and evaluate the keyword's value, not blanket-flag kw calls), while
# the pre-fix tree still crashes internally on them.
kwconst = {
    "kw_const": "from django.db.models.expressions import RawSQL\nfrom django.contrib.auth.models import User\nUser.objects.annotate(val=RawSQL(sql='SELECT 1', params=[]))\n",
}
guard = {
    "pos_constant": "from django.db.models.expressions import RawSQL\nfrom django.contrib.auth.models import User\nUser.objects.annotate(val=RawSQL('SELECT 1', []))\n",
    "pos_var": "from django.db.models.expressions import RawSQL\nfrom django.contrib.auth.models import User\nq = 'SELECT 2'\nUser.objects.annotate(val=RawSQL(q, []))\n",
}
base = pathlib.Path("/tmp/snippets")
for name, src in trig.items():
    (base / "triggers" / (name + ".py")).write_text(src)
for name, src in kwconst.items():
    (base / "kwconst" / (name + ".py")).write_text(src)
for name, src in guard.items():
    (base / "guards" / (name + ".py")).write_text(src)
PY

# pre-fix tree must still show the internal error on every trigger/kwconst shape
bad=0
for f in /tmp/snippets/triggers/*.py /tmp/snippets/kwconst/*.py; do
  scan_bandit pretree "$f" /tmp/ps
  n=$(grep -c "internal error" /tmp/ps.err)
  if [ "$n" -lt 1 ]; then
    echo "FAIL: the pre-fix tree showed no internal error for $(basename "$f")" >&2
    tail -8 /tmp/ps.err | sed 's/^/    /' >&2
    reward=0; bad=1
  fi
done
if [ "$bad" = 0 ]; then
  echo "ok: the pre-fix tree still crashes internally on every trigger and kw-constant shape"
fi

# repaired tree must show none on any shape; triggers must report B611,
# positional guards keep their findings, and keyword-constant calls stay
# unflagged (a blanket flag of kw calls is not the upstream fix)
bad=0
for f in /tmp/snippets/triggers/*.py /tmp/snippets/guards/*.py /tmp/snippets/kwconst/*.py; do
  scan_bandit fixed "$f" /tmp/rs
  n=$(grep -c "internal error" /tmp/rs.err)
  if [ "$n" -ne 0 ]; then
    echo "FAIL: the repaired tree still logs an internal error for $(basename "$f")" >&2
    tail -20 /tmp/rs.err | sed 's/^/    /' >&2
    reward=0; bad=1
  fi
  nres=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['results']))" /tmp/rs.json 2>/dev/null || echo -)
  case "$f" in
    */guards/pos_constant.py|*/kwconst/*)
      if [ "$nres" != "0" ]; then
        echo "FAIL: constant-literal RawSQL call was flagged on the repaired tree ($(basename "$f"): $nres findings, expected 0)" >&2
        reward=0; bad=1
      fi
      ;;
    */guards/*)
      if [ "$nres" != "1" ]; then
        echo "FAIL: positional variable RawSQL call produced $nres findings (expected 1) on the repaired tree" >&2
        reward=0; bad=1
      fi
      ;;
    */triggers/*)
      if [ "$nres" -lt 1 ]; then
        echo "FAIL: trigger shape $(basename "$f") produced no finding on the repaired tree" >&2
        reward=0; bad=1
      fi
      ;;
  esac
done
if [ "$bad" = 0 ]; then
  echo "ok: the repaired tree scans every shape with no internal error and the expected findings"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0