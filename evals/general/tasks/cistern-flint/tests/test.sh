#!/bin/bash
# Verifier for cistern-flint: an upstream-clone debugging task on
# prometheus/prometheus.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# relabel rules that deliberately configure an empty separator or empty regex
# replacement lose those values on a config serialize/reload cycle.  The
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source file is modified, no new files appeared inside
#      model/relabel, and a fix was actually implemented);
#   1. swaps the package's test file for the project's own regression test as
#      it exists at the fixed revision (extracted to /opt/golden at image build
#      time) and runs the project's own test runner on: the regression test
#      functions themselves and the whole model/relabel package suite; the
#      reason the fixed-revision file must be used is that the JSON round-trip
#      expectations in the parent's relabel_test.go encode the pre-fix
#      behaviour and would contradict a correct fix;
#   2. runs four authored hidden cases (empty separator only, empty replacement
#      only, empty regex, and a functional after-reload semantics check) that
#      the upstream test does not cover;
#   3. re-asserts tree provenance.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=7d1195258cb1702d958361deab455059fdebc08e
FIX_SHA=7450865dcd1f7a521b96c5c9dad01e5eb2c66be0
GOLDEN=/opt/golden/relabel_test.go
GO=/opt/go/bin/go

# ---- harness integrity: the toolchain and the golden test must be the        ----
# pristine ones from the image build.  The agent runs as root in this container,
# so a cheap bypass is to stub /opt/go/bin/go (or to rewrite /opt/golden) and
# let every `go test` appear to pass without fixing anything.  Both files are
# hashed against the values measured at image build time (go1.26.0 official
# tarball and `git show <fix>:model/relabel/relabel_test.go` are immutable, so
# the hashes are stable across rebuilds of the committed Dockerfile).
GO_SHA256=61e7455a40a2fdfcdab99e881cd30ba10e216e3d0f32ab5f8e59d10cac4ecf57
GOLDEN_SHA256=22c67830956b824bdc9623de76b9708a389f90f2f4e8a4c2b4dd285b92a1ddee

check_integrity () {  # nonzero on failure
  local bad=0
  if [ ! -x "$GO" ] || [ "$(sha256sum "$GO" 2>/dev/null | awk '{print $1}')" != "$GO_SHA256" ]; then
    echo "FAIL: /opt/go/bin/go is not the pristine go1.26.0 toolchain from the image build" >&2
    bad=1
  fi
  if [ ! -s "$GOLDEN" ] || [ "$(sha256sum "$GOLDEN" 2>/dev/null | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
    echo "FAIL: /opt/golden/relabel_test.go is not the pristine fix-revision test extracted at image build time" >&2
    bad=1
  fi
  if [ "$bad" = 0 ] && ! "$GO" version 2>/dev/null | grep -q '^go version go1\.[0-9]\+'; then
    echo "FAIL: the go toolchain at /opt/go/bin/go does not answer to 'go version'" >&2
    bad=1
  fi
  return "$bad"
}

if ! check_integrity; then
  echo 'REWARD=0'
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

run_go () {  # run_go LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && "$GO" test -v "$@" > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -60 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

provenance () {  # provenance WHEN  => nonzero on failure
  local when="$1"
  echo "== tree provenance ($when) =="
  if [ ! -d "$SRC/.git" ]; then
    echo "FAIL: /app/src is not a git clone" >&2; reward=0; return 1
  fi
  if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
    echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0; return 1
  fi
  if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
    reward=0; return 1
  fi
  changed=$(git -C "$SRC" status --porcelain 2>/dev/null | grep -v '^?? ' || true)
  bad=$(printf '%s\n' "$changed" | grep -v '^ M model/relabel/relabel.go$' || true)
  if [ -n "$bad" ]; then
    echo "FAIL: unexpected tracked-file changes (only model/relabel/relabel.go may be modified):" >&2
    printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
    reward=0; return 1
  fi
  newpkg=$(git -C "$SRC" status --porcelain 2>/dev/null | grep '^?? model/relabel/' || true)
  if [ -n "$newpkg" ]; then
    echo "FAIL: new files were added inside the model/relabel package:" >&2
    printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
    reward=0; return 1
  fi
  if [ -z "$(git -C "$SRC" diff -- model/relabel/relabel.go 2>/dev/null || true)" ]; then
    echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
    reward=0; return 1
  fi
  return 0
}

# ---------- 0. tree provenance on the agent-delivered tree --------------------
provenance "before" || true

# ---------- 1. the project's own regression test and package suite ------------
# The package's test file at the pinned commit encodes the pre-fix round-trip
# expectations (its JSON case would contradict a correct fix), so the verifier
# runs the project's own tests as they exist at the fixed revision, taken from
# /opt/golden/relabel_test.go.  The original file is restored afterwards.
echo "== the project's own regression test and relabel package suite =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test file missing from image" >&2; reward=0
else
  cp "$SRC/model/relabel/relabel_test.go" /tmp/pristine_relabel_test.go
  cp "$GOLDEN" "$SRC/model/relabel/relabel_test.go"
  run_go "regression test (YAML round-trip)" /tmp/golden_yaml.out \
      ./model/relabel -run TestConfig_UnmarshalThenMarshal || true
  run_go "regression test (JSON round-trip)" /tmp/golden_json.out \
      ./model/relabel -run TestRegexp_JSONUnmarshalThenMarshal || true
  run_go "the project's own model/relabel package suite" /tmp/own.out \
      ./model/relabel || true
  cp /tmp/pristine_relabel_test.go "$SRC/model/relabel/relabel_test.go"
fi

# ---------- 2. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  safe=$(printf '%s' "$name" | tr -c 'a-zA-Z0-9' '_')
  testfile="$(find "$case" -maxdepth 1 -name '*_test.go' -print -quit)"
  if [ -z "$testfile" ]; then
    echo "FAIL: hidden case $name has no *_test.go file" >&2; reward=0; continue
  fi
  names=$(grep -ho 'func Test[A-Za-z0-9_]*' "$testfile" | sed 's/func //' | paste -sd'|' -)
  [ -n "$names" ] || { echo "FAIL: hidden case $name has no Test funcs" >&2; reward=0; continue; }
  staged="$SRC/model/relabel/zz_hidden_${safe}_test.go"
  cp "$testfile" "$staged"
  for tn in $(printf '%s' "$names" | tr '|' ' '); do
    if ( cd "$SRC" && "$GO" test -v ./model/relabel -run "$tn" > /tmp/hidden-${safe}.out 2>&1 ); then
      echo "ok: hidden case $name ($tn)"
    else
      echo "FAIL: hidden case $name ($tn)" >&2
      tail -60 /tmp/hidden-${safe}.out | sed 's/^/    /' >&2
      reward=0
    fi
  done
  rm -f "$staged"
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

# ---------- 3. tree provenance again after the verifier's own work ------------
provenance "after" || true

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0