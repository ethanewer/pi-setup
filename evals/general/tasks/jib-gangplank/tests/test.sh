#!/usr/bin/env bash
# Verifier for jib-gangplank: an upstream-clone debugging task on
# matplotlib/matplotlib.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# Axes.pie with all-zero wedge sizes divides by zero, leaves NaN angles and
# dies deep in path drawing with 'ValueError: cannot convert float NaN to
# integer' instead of a clear error. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, exactly one commit exists, the
#      only modified tracked file is lib/matplotlib/axes/_axes.py, no new
#      files appeared under lib/matplotlib/ apart from __pycache__, `import
#      matplotlib` resolves to the checked-out tree, Axes.pie is *defined
#      inside* $SRC/lib/matplotlib/axes/_axes.py and that file itself raises
#      ValueError('All wedge sizes are zero') — so the fixed behaviour must
#      come from the tree and not from a wrapper installed elsewhere
#      (sitecustomize/.pth), and /app/reproduce.py exists, is non-empty and
#      actually invokes the pie function);
#   1. runs the agent's OWN reproduction twice: against the pre-fix tree
#      concept (the parent HV** blob of _axes.py is restored into the working
#      tree; the repro must exit nonzero, must not print REPRO-OK and must
#      report the NaN symptom) and against the repaired tree (repro must exit
#      0 and print REPRO-OK) — so a reproduction that does not genuinely
#      reproduce the bug fails in one of the two directions;
#   2. copies in the project's own regression test for this bug, extracted
#      at image build time from the fix commit into /opt/golden/ (the
#      fix-commit lib/matplotlib/tests/test_axes.py, which appends
#      test_pie_all_zeros; content is sha-pinned against the sha written at
#      build time), and requires test_pie_all_zeros to be present in the
#      collection AND to pass against the agent's repaired tree (it fails
#      against the parent tree, which the image build asserts);
#   3. runs nine of the project's own existing pie tests that do not use
#      image comparison (fixed subset: must collect exactly 9 and report
#      '9 passed', nothing skipped) to prove the fix broke nothing else;
#   4. runs two authored hidden cases whose inputs the upstream test never
#      uses (other all-zero shapes; all-zero inputs through the
#      explode/startangle/counterclock/autopct keyword paths), each required
#      to raise the clean message, plus a sanity check that non-zero pies
#      still render.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=2d87c9584499f7619b3c84b89121a27c80d2373e
FIX_SHA=91740933b658437016063f904030706d84b4502b
GOLDEN=/opt/golden/test_axes.py
# The expected golden sha is a LITERAL pin in the verifier, not read from the
# image: an agent that could overwrite /opt/golden/test_axes.py AND its .sha
# file (the trial runs as root) would otherwise be able to forge the golden
# test it is graded against.
GOLDEN_SHA=4289978f224d221400ba3c6557e907b68bf1a981263def75c13f3269364b108f
if [ "$(cat /opt/golden/test_axes.py.sha 2>/dev/null || echo missing)" != "$GOLDEN_SHA" ]; then
  fail "the golden sha file in the image does not match the verifier's literal pin"
fi

export PYTHONDONTWRITEBYTECODE=1

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

run_pytest () {  # run_pytest LABEL OUT ...args  (cwd = SRC)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0a. startup-hook scan --------------------------------------------
# The trial container runs as root, so a cheating agent could install a
# sitecustomize.py / usercustomize.py -- or a foreign .pth -- into the
# interpreter's site directories to patch matplotlib at import time while
# leaving the real fix out of the tree (a decoy `raise` in _axes.py satisfies
# the file-content check). The fixed behaviour must come from the tree, so any
# such startup hook that was not shipped in the image fails the task.
echo "== startup-hook scan (sitecustomize / usercustomize / foreign .pth) =="
if python3 - <<'PYEOF' >/tmp/hookscan.out 2>&1
import os
import site
import sys

checked = set()
for p in list(site.getsitepackages()) + [site.getusersitepackages()] + list(sys.path):
    if p and os.path.isdir(p):
        checked.add(os.path.realpath(p))

KNOWN_PTH = {"distutils-precedence.pth", "matplotlib-editable.pth"}
hits = []
for base in sorted(checked):
    for name in ("sitecustomize.py", "usercustomize.py"):
        f = os.path.join(base, name)
        if os.path.exists(f):
            hits.append(f)
    if os.path.isdir(base):
        for fn in sorted(os.listdir(base)):
            if not fn.endswith(".pth"):
                continue
            if fn in KNOWN_PTH:
                continue
            fp = os.path.join(base, fn)
            try:
                content = open(fp, encoding="utf-8", errors="replace").read()
            except OSError:
                content = ""
            # tolerate empty / comment-only .pth files, nothing else
            if any(line.strip() and not line.lstrip().startswith("#") for line in content.splitlines()):
                hits.append(fp)
if hits:
    print("found startup hook(s): %s" % ", ".join(hits))
    raise SystemExit(1)
print("clean")
PYEOF
then
  echo "ok: no sitecustomize / usercustomize / foreign .pth startup hooks were installed"
else
  fail "a startup hook (sitecustomize/usercustomize/foreign .pth) is present in the interpreter's site directories; the fix must live in the checked-out tree"
  cat /tmp/hookscan.out | sed 's/^/    /' >&2
fi

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  fail "the working clone contains $ncommits commits; it must contain exactly the pinned parent commit"
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M lib/matplotlib/axes/_axes.py")
      saw_mod=1
      ;;
    " M "*) # modified tracked file outside the fix target
      echo "FAIL: a tracked file other than lib/matplotlib/axes/_axes.py was modified: $line" >&2
      bad_tree=1
      ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? subprojects/.wraplock") : ;;  # meson lock file the project's own
      # editable-install hook (re)creates at trial time on first import
    "?? "*) # no new untracked file may appear inside the repository (an
      # untracked root-level conftest.py would otherwise be able to
      # monkeypatch the API without touching any tracked source file)
      echo "FAIL: a new untracked file appeared in the repository: $line" >&2
      bad_tree=1
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: lib/matplotlib/axes/_axes.py differs from the pinned commit"
fi

if ! python3 -c "
import re
import matplotlib
assert matplotlib.__file__.startswith('$SRC'), matplotlib.__file__
import matplotlib.axes._axes as _axes_mod
assert _axes_mod.__file__.startswith('$SRC'), _axes_mod.__file__
src = open('$SRC/lib/matplotlib/axes/_axes.py', encoding='utf-8').read()
# a raise statement inside a comment must not satisfy the check
code = '\n'.join(l for l in src.splitlines() if not l.lstrip().startswith('#'))
assert re.search(r\"raise ValueError\\(['\\\"]All wedge sizes are zero['\\\"]\\)\", code), \
       'the clean error message is not raised inside _axes.py'
assert 'All wedge sizes are zero' in code
" >/tmp/prov.out 2>&1; then

  fail "the fixed behaviour must come from the tree: Axes.pie is implemented in $SRC/lib/matplotlib/axes/_axes.py (that module must be the one loaded) and that file must raise ValueError('All wedge sizes are zero') itself"
  tail -5 /tmp/prov.out | sed 's/^/    /' >&2
else
  echo "ok: Axes.pie is implemented in $SRC/lib/matplotlib/axes/_axes.py and that module is the one loaded (no wrapper); the file itself raises the clean error"
fi

if [ ! -s /app/reproduce.py ]; then
  fail "the deliverable /app/reproduce.py is missing or empty"
else
  if ! grep -q "pie(" /app/reproduce.py; then
    fail "/app/reproduce.py never invokes the pie function"
  else
    echo "ok: /app/reproduce.py exists, is non-empty and invokes the pie function"
  fi
fi

# ---------- 1. the agent's own reproduction, both directions -----------------
echo "== the agent's own reproduction =="
if [ -s /app/reproduce.py ]; then
  cp "$SRC/lib/matplotlib/axes/_axes.py" /tmp/agent_axes.py

  # 1a. against the pre-fix tree concept: restore the parent blob exactly.
  git -C "$SRC" show HEAD:lib/matplotlib/axes/_axes.py > "$SRC/lib/matplotlib/axes/_axes.py"
  if ( cd "$SRC" && timeout 180 python3 /app/reproduce.py > /tmp/repro-prefix.out 2>&1 ); then
    fail "the reproduction PASSED against the pre-fix tree: it does not reproduce the bug"
  else
    echo "ok: the reproduction exits nonzero against the pre-fix tree"
  fi
  if grep -q "REPRO-OK" /tmp/repro-prefix.out 2>/dev/null; then
    fail "the reproduction printed REPRO-OK against the pre-fix tree"
  else
    echo "ok: the reproduction did not print REPRO-OK against the pre-fix tree"
  fi
  if ! grep -qiE "NaN|cannot convert|ValueError|Traceback|zero" /tmp/repro-prefix.out 2>/dev/null; then
    fail "the reproduction output does not report the NaN symptom it observed:"
    tail -15 /tmp/repro-prefix.out 2>/dev/null | sed 's/^/    /' >&2 || true
  else
    echo "ok: the reproduction reports the observed symptom on the pre-fix tree"
    grep -iE "ValueError|Traceback|NaN" /tmp/repro-prefix.out 2>/dev/null | head -3 | sed 's/^/    /'
  fi

  # restore the agent's repaired file and verify the restore is exact
  cp /tmp/agent_axes.py "$SRC/lib/matplotlib/axes/_axes.py"
  if ! cmp -s /tmp/agent_axes.py "$SRC/lib/matplotlib/axes/_axes.py"; then
    fail "could not restore the repaired _axes.py after the pre-fix run"
  else
    echo "ok: repaired _axes.py restored byte-exact after the pre-fix run"
  fi

  # 1b. against the repaired tree
  if ( cd "$SRC" && timeout 180 python3 /app/reproduce.py > /tmp/repro-fixed.out 2>&1 ) \
     && grep -q "^REPRO-OK" /tmp/repro-fixed.out; then
    echo "ok: the reproduction passes against the repaired tree (REPRO-OK)"
  else
    fail "the reproduction does not pass against the repaired tree"
    tail -15 /tmp/repro-fixed.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 2. golden: the project's own regression test for this bug --------
echo "== golden test (the project's own regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  fail "golden test missing from image"
  reward=0
else
  sha=$(sha256sum < "$GOLDEN" | cut -d' ' -f1)
  if [ "$sha" != "$GOLDEN_SHA" ]; then
    fail "golden test in image has unexpected hash $sha (expected $GOLDEN_SHA)"
    reward=0
  else
    echo "ok: /opt/golden/test_axes.py matches the build-time pinned sha"
    cp "$GOLDEN" "$SRC/lib/matplotlib/tests/test_axes.py"
    # The upstream regression test must be present in the collection (a
    # conftest/module edit could otherwise drop it from the run).
    if ( cd "$SRC" && python3 -m pytest --collect-only -q \
           "lib/matplotlib/tests/test_axes.py::test_pie_all_zeros" \
           -p no:cacheprovider > /tmp/golden.collect 2>&1 ) \
       && grep -qE "test_pie_all_zeros" /tmp/golden.collect \
       && grep -qE "1 test(s)? collected" /tmp/golden.collect; then
      echo "ok: the golden regression test is present in the collection"
    else
      fail "the golden regression test is not present in the collection"
      tail -10 /tmp/golden.collect | sed 's/^/    /' >&2
    fi
    if ( cd "$SRC" && python3 -m pytest \
           "lib/matplotlib/tests/test_axes.py::test_pie_all_zeros" \
           -p no:cacheprovider > /tmp/golden.out 2>&1 ) \
       && grep -qE "1 passed" /tmp/golden.out \
       && ! grep -qiE "skipped" /tmp/golden.out; then
      echo "ok: golden test test_pie_all_zeros passes"
    else
      fail "golden test test_pie_all_zeros did not pass"
      tail -15 /tmp/golden.out | sed 's/^/    /' >&2
    fi
  fi
fi

# ---------- 3. the project's own existing pie tests --------------------------
echo "== the project's own existing pie tests (no image comparison) =="
if ( cd "$SRC" && python3 -m pytest --collect-only -q \
       "lib/matplotlib/tests/test_axes.py::test_pie_textprops" \
       "lib/matplotlib/tests/test_axes.py::test_pie_get_negative_values" \
       "lib/matplotlib/tests/test_axes.py::test_pie_invalid_explode" \
       "lib/matplotlib/tests/test_axes.py::test_pie_invalid_labels" \
       "lib/matplotlib/tests/test_axes.py::test_pie_invalid_radius" \
       "lib/matplotlib/tests/test_axes.py::test_normalize_kwarg_pie" \
       "lib/matplotlib/tests/test_axes.py::test_pie_hatch_single" \
       "lib/matplotlib/tests/test_axes.py::test_pie_hatch_multi" \
       "lib/matplotlib/tests/test_axes.py::test_pie_non_finite_values" \
       -p no:cacheprovider > /tmp/own.collect 2>&1 ) \
   && grep -qE "9 tests collected" /tmp/own.collect; then
  echo "ok: own-suite subset collects exactly 9 tests"
else
  fail "own-suite subset did not collect exactly 9 tests (expected 9)"
  tail -10 /tmp/own.collect | sed 's/^/    /' >&2
fi
run_pytest "existing pie tests" /tmp/own.out \
  "lib/matplotlib/tests/test_axes.py::test_pie_textprops" \
  "lib/matplotlib/tests/test_axes.py::test_pie_get_negative_values" \
  "lib/matplotlib/tests/test_axes.py::test_pie_invalid_explode" \
  "lib/matplotlib/tests/test_axes.py::test_pie_invalid_labels" \
  "lib/matplotlib/tests/test_axes.py::test_pie_invalid_radius" \
  "lib/matplotlib/tests/test_axes.py::test_normalize_kwarg_pie" \
  "lib/matplotlib/tests/test_axes.py::test_pie_hatch_single" \
  "lib/matplotlib/tests/test_axes.py::test_pie_hatch_multi" \
  "lib/matplotlib/tests/test_axes.py::test_pie_non_finite_values" || true
if ! grep -qE "9 passed" /tmp/own.out || grep -qiE "skipped" /tmp/own.out; then
  fail "existing pie subset did not run to completion (expected '9 passed', nothing skipped)"
  tail -20 /tmp/own.out | sed 's/^/    /' >&2
fi

# ---------- 4. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  for f in "$case"test_*.py; do
    [ -f "$f" ] || continue
    n_hidden=$((n_hidden + 1))
    name=$(basename "$(dirname "$f")")/$(basename "$f")
    out="/tmp/hidden-${n_hidden}.out"
    if timeout 180 python3 "$f" > "$out" 2>&1; then
      echo "ok: hidden case $name"
      tail -2 "$out" | sed 's/^/    /'
    else
      fail "hidden case $name"
      tail -15 "$out" | sed 's/^/    /' >&2
    fi
  done
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

# ---------- 5. randomized all-zero generalization probe -----------------------
# Inputs are DRAWN AT VERIFICATION TIME from a system-random generator, so no
# file in the image (nor any static hidden case) enumerates them. A fix that
# special-cases the exact golden/hidden/repro inputs -- while leaving the real
# bug in place for every other all-zero input -- fails here with certainty,
# while the honest general guard ("if sum is zero, raise the clean error")
# passes regardless of the draw.
echo "== randomized all-zero generalization probe (inputs not present in any shipped file) =="
if timeout 180 python3 - <<'PYEOF' >/tmp/randprobe.out 2>&1
import random

import numpy as np

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

rng = random.SystemRandom()


def expect_clean(ax, x, **kw):
    try:
        ax.pie(x, **kw)
    except ValueError as e:
        assert 'All wedge sizes are zero' in str(e), \
            'unexpected message %r for x=%r kw=%r' % (str(e), x, kw)
        return
    raise AssertionError('pie(%r, %r) did not raise for an all-zero input' % (x, kw))


for _ in range(8):
    n = rng.choice([1, 3, 5, 6, 7, 8])
    kind = rng.randrange(4)
    if kind == 0:
        x = [0.0] * n
    elif kind == 1:
        x = np.zeros(n, dtype=float)
    elif kind == 2:
        x = np.zeros(n, dtype=np.int64)
    else:
        x = [0] * n
    fig, ax = plt.subplots()
    if rng.randrange(2):
        kw = {'labels': ['s%d' % i for i in range(n)]}
        if rng.randrange(2):
            kw['explode'] = [0.0] * n
        if rng.randrange(3) == 0:
            kw['autopct'] = '%1.1f%%'
    else:
        kw = {}
    expect_clean(ax, x, **kw)
    plt.close(fig)

# sanity: non-zero pies (including through the same keyword paths) must still
# draw without any error
for x in ([1, 2, 3], [0.5, 1.5], (1, 1, 2)):
    fig, ax = plt.subplots()
    ax.pie(x, labels=[str(i) for i in range(len(x))])
    plt.close(fig)

print('ok')
PYEOF
then
  echo "ok: randomized all-zero inputs drawn at verification time are rejected cleanly; non-zero pies still draw"
else
  fail "a random all-zero input was NOT rejected with the clean message (the fix must reject any all-zero input, not just the shipped test inputs)"
  tail -15 /tmp/randprobe.out | sed 's/^/    /' >&2
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
