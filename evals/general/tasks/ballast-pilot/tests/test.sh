#!/bin/bash
# Verifier for ballast-pilot: an upstream-clone debugging task on NLTK.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the RIBES machine-translation scorer crashes with ZeroDivisionError on empty
# hypotheses / empty reference lists / an empty corpus, silently scores -1.0
# for an empty reference list, and silently mis-scores a corpus whose
# reference-set count does not match its hypothesis count.
#
#   0. tree provenance: HEAD is still the pinned parent commit, the upstream
#      fix commit is not reachable from the working clone, only the minimal
#      tracked source file is modified, and no new files appeared;
#   1. the project's own regression tests for this bug, extracted at image
#      build time from the fix commit into /opt/golden/;
#   2. a direct reproduction of the reported symptom through the public API;
#   3. the project's own existing RIBES test file from the tree, proving the
#      fix broke nothing else;
#   4. authored hidden cases (empty shapes the upstream test does not use and
#      the exact error contract, plus genuine-scoring regressions) that the
#      upstream tests do not cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
# Disable user-site import injection: a usercustomize.py dropped in a writable
# user HOME must never be able to supply the expected behaviour on the
# verifier's own python processes.
export PYTHONNOUSERSITE=1
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=a167389c027a02a9d1f019630ed827f4069b3353
FIX_SHA=06c0e2cc94f763d43320812ee9d2a7b6bff68f9b
GOLDEN=/opt/golden/test_ribes.py

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
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
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
# The working tree must contain EXACTLY one change: an unstaged edit of
# nltk/translate/ribes_score.py.  Anything else fails provenance: other
# modified tracked files, staged changes, typechanges, and any untracked file
# anywhere in the tree.  Untracked files must be rejected because a wrapper (a
# steering conftest.py, a patched-in helper, ...) can supply the expected
# behaviour while the buggy scoring code is left in place.
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M nltk/translate/ribes_score.py$' || true)
if [ -n "$porcelain" ] && [ -n "$bad" ]; then
  echo "FAIL: working tree must contain exactly one change, an unstaged edit of nltk/translate/ribes_score.py:" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- nltk/translate/ribes_score.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 0.5 interpreter hygiene: no import-time wrappers -------------------
# The agent phase runs as root in this same filesystem, so every fix that the
# scored behaviours below accept could in principle have been layered in
# without touching the scored code: a sitecustomize.py on sys.path, a rewrite
# of the editable-install pth/finder, a rewrite of the golden test (or a
# conftest.py seeded next to it), or a stub of the guard text in the source
# while a wrapper supplies the behaviour.  All of those are rejected here.
echo "== interpreter hygiene =="
hygiene_ok=1
# (a) no sitecustomize.py / usercustomize.py anywhere on the interpreter path
if python3 - 2>/tmp/hygiene.err > /tmp/hygiene.out <<'PY'
import sys, pathlib
hits = []
for base in sys.path:
    if not base:
        continue
    p = pathlib.Path(base)
    if not p.is_dir():
        continue
    for name in ("sitecustomize.py", "usercustomize.py"):
        f = p / name
        if f.exists():
            hits.append(str(f))
sys.stdout.write("\n".join(hits))
PY
then
  if [ -s /tmp/hygiene.out ]; then
    echo "FAIL: import-time hook file(s) found on sys.path (the fix must be in the tracked source):" >&2
    sed 's/^/    /' /tmp/hygiene.out >&2
    hygiene_ok=0
  fi
else
  echo "FAIL: could not inspect the interpreter sys.path" >&2
  hygiene_ok=0
fi
# (b) the editable-install pth and finder must still be the build-time files
SP=/usr/local/lib/python3.12/site-packages
pth_sha=$(sha256sum "$SP/__editable__.nltk-3.10.0.pth" 2>/dev/null | cut -d' ' -f1)
finder_sha=$(sha256sum "$SP/__editable___nltk_3_10_0_finder.py" 2>/dev/null | cut -d' ' -f1)
if [ "$pth_sha" != "8e7da00fe062c2aab93816ccabcd1b9620c35af59f32267fb324a71bd84e4a4e" ] \
   || [ "$finder_sha" != "85e88a27e6837e21d69dc47a10d9c0b33eda6f3f212b6b535cd615d94fcdbec2" ]; then
  echo "FAIL: editable-install pth/finder differs from the build-time files (an import hook was injected)" >&2
  echo "    pth=$pth_sha finder=$finder_sha" >&2
  hygiene_ok=0
fi
# (c) the golden directory holds exactly the pinned fix-commit test
if [ "$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)" != "be5c54fceec95bbab21a4488140eb737b3338627f3fab3c2571ab5cc68854682" ]; then
  echo "FAIL: $GOLDEN differs from the fix-commit regression test (it was rewritten, not implemented)" >&2
  hygiene_ok=0
fi
extra=$(find /opt/golden -maxdepth 1 -type f ! -name test_ribes.py 2>/dev/null)
if [ -n "$extra" ]; then
  echo "FAIL: unexpected additional file(s) in /opt/golden:" >&2
  echo "$extra" | sed 's/^/    /' >&2
  hygiene_ok=0
fi
# (d) the tracked scorer source itself must carry the empty-input guard and the
#     mandated error text: the fix belongs in the deliverable, not in a wrapper.
src_file="$SRC/nltk/translate/ribes_score.py"
if ! grep -q "if not references or not hypothesis" "$src_file" 2>/dev/null; then
  echo "FAIL: the empty-input guard is not present in the tracked source nltk/translate/ribes_score.py" >&2
  hygiene_ok=0
fi
if ! grep -q "if not hypotheses" "$src_file" 2>/dev/null; then
  echo "FAIL: the empty-corpus guard is not present in the tracked source nltk/translate/ribes_score.py" >&2
  hygiene_ok=0
fi
if ! grep -q "The number of reference sets must match the number of hypotheses" "$src_file" 2>/dev/null; then
  echo "FAIL: the mandated mismatch-error message is not present in the tracked source" >&2
  hygiene_ok=0
fi
if [ "$hygiene_ok" = 0 ]; then
  reward=0
else
  echo "ok: interpreter hygiene (no import hooks, golden pinned, guards in tracked source)"
fi

# ---------- 1. golden: the upstream regression tests --------------------------
echo "== golden test (upstream regression tests for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_pytest "golden test_ribes.py" /tmp/golden.out "$GOLDEN" || true
fi

# ---------- 2. direct reproduction through the public API ---------------------
echo "== direct reproduction =="
if python3 - > /tmp/direct.out 2>&1 <<'PY'
from nltk.translate.ribes_score import corpus_ribes, sentence_ribes

# empty hypothesis -> 0.0 (was ZeroDivisionError)
assert sentence_ribes([["a"]], []) == 0.0
# empty reference list -> 0.0 (was silent -1.0)
assert sentence_ribes([], ["a"]) == 0.0
# fully empty sentence call -> 0.0 (was silent -1.0)
assert sentence_ribes([], []) == 0.0
# empty corpus -> 0.0 (was ZeroDivisionError)
assert corpus_ribes([], []) == 0.0
# mismatched corpus rejected with a clear ValueError before any scoring
try:
    corpus_ribes([[["a"]]], [["a"], ["b"]])
except ValueError as e:
    assert "number of reference sets" in str(e), str(e)
else:
    raise SystemExit("mismatched corpus was accepted")

print("ok: empty and mismatched inputs behave per contract")
PY
then
  echo "ok: direct reproduction"
else
  echo "FAIL: direct reproduction (expected 0.0 for the empty cases and ValueError for the mismatch)" >&2
  tail -20 /tmp/direct.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 3. the project's own existing RIBES tests -------------------------
echo "== the project's own existing RIBES tests =="
run_pytest "existing nltk/test/unit/test_ribes.py" /tmp/own.out nltk/test/unit/test_ribes.py \
  || true

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if run_pytest "hidden case $name" "$out" "$case"; then
    :
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0