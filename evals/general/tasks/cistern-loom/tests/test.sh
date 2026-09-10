#!/usr/bin/env bash
# Verifier for cistern-loom (executes-deliverable).
#
# Proves the strict-mode migration of /app/cistern end to end:
#   * delivered tsconfig is strict with strictNullChecks on (and no
#     strictness override left disabled),
#   * the tree stays at repository scale with its git history intact,
#   * no banned escape hatches ('any', @ts-* comments, unknown-casts)
#     survive anywhere in src/ or tests/,
#   * the deliverable tsconfig compiles with `tsc --noEmit`,
#   * the whole tree also compiles with noUncheckedIndexedAccess,
#     exactOptionalPropertyTypes and noImplicitOverride forced on,
#   * the vitest suite is green,
#   * two fresh hidden type-contract files are dropped into the tree and
#     compile as part of the same passes (they only compile against a
#     real, precise migration).
# Reward is 1 only when every stage passes in the delivered tree AND in
# the hidden-augmented tree.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

REPO=/app/cistern
TSC="$REPO/node_modules/.bin/tsc"
VITEST="$REPO/node_modules/.bin/vitest"

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

# ------------------------------------------------------------- deliverables
for f in /app/cistern/tsconfig.json /app/cistern/package.json; do
  if [ ! -f "$f" ]; then
    fail "deliverable $f missing"
  fi
done
if [ ! -x "$TSC" ]; then
  fail "typescript binary not installed at $TSC"
fi
if [ ! -x "$VITEST" ]; then
  fail "vitest binary not installed at $VITEST"
fi

# ---------------------------------------------------------------- history
if [ ! -d "$REPO/.git" ]; then
  fail "/app/cistern is not a git repository"
fi
cc=$(cd "$REPO" && git rev-list --count HEAD 2>/dev/null || echo 0)
if [ "$cc" -lt 10 ]; then
  fail "git history suspiciously shallow: $cc commits"
fi

# ------------------------------------------------------- repository scale
tsloc=$(find "$REPO/src" "$REPO/tests" -name '*.ts' -not -path '*/node_modules/*' -print0 2>/dev/null \
  | xargs -0 wc -l 2>/dev/null | tail -1 | awk '{print $1}')
if [ -z "$tsloc" ] || [ "$tsloc" -lt 5000 ]; then
  fail "TypeScript LOC = ${tsloc:-0}, below the 5000 floor"
fi

# -------------------------------------------------- tests are the spec
for t in "$REPO"/tests/*.test.ts; do
  base=$(basename "$t")
  if [ ! -f "/tests/pristine/$base" ]; then
    fail "tests/$base is not part of the shipped suite (the suite is the specification; do not add tests)"
    continue
  fi
  if ! cmp -s "$t" "/tests/pristine/$base"; then
    fail "tests/$base was modified or replaced (the suite is the specification; migrate library code, not tests)"
  fi
done
# Reverse direction: every pristine test must still exist in the tree, so
# deleting part of the suite cannot soften the spec.
for p in /tests/pristine/*.test.ts; do
  base=$(basename "$p")
  if [ ! -f "$REPO/tests/$base" ]; then
    fail "tests/$base was deleted (the suite is the specification; migrate library code, not tests)"
  fi
done

# ------------------------------------------------- tsconfig contract
python3 - "$REPO/tsconfig.json" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except Exception as e:  # noqa: BLE001
    print("tsconfig unreadable: %s" % e)
    sys.exit(1)
opts = cfg.get("compilerOptions", {})
bad = []
if opts.get("strict") is not True:
    bad.append("strict must be true")
if opts.get("strictNullChecks") is not True:
    bad.append("strictNullChecks must be true")
for flag in ("noImplicitAny", "noUncheckedIndexedAccess", "exactOptionalPropertyTypes", "noImplicitOverride"):
    if opts.get(flag) is False:
        bad.append("%s must not be left disabled" % flag)
if bad:
    print("tsconfig contract violations: %s" % "; ".join(bad))
    sys.exit(1)
PY
if [ $? -ne 0 ]; then
  fail "tsconfig does not enable strict+strictNullChecks (see above)"
fi

# ----------------------------------------------------- escape hatches
if ! node /tests/scan_escapes.cjs "$REPO" "$REPO/src" "$REPO/tests"; then
  fail "banned type escape hatches found (see above)"
fi

# ---------------------------------------------------- toolchain passes
hardened() { # label
  local label=$1
  local tscf=/tmp/cis-verify.$label.json
  python3 - "$REPO/tsconfig.json" "$tscf" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as fh:
    cfg = json.load(fh)
opts = dict(cfg.get("compilerOptions", {}))
opts["strict"] = True
opts["strictNullChecks"] = True
opts["noImplicitAny"] = True
opts["noUncheckedIndexedAccess"] = True
opts["exactOptionalPropertyTypes"] = True
opts["noImplicitOverride"] = True
cfg["compilerOptions"] = opts
cfg["include"] = ["/app/cistern/src", "/app/cistern/tests"]
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh)
PY
  if ! "$TSC" --noEmit -p "$tscf" >/tmp/cis-tsc-$label.log 2>&1; then
    fail "$label: hardened tsc --noEmit failed"
    tail -8 /tmp/cis-tsc-$label.log >&2
  fi
}

if ! "$TSC" --noEmit -p /app/cistern/tsconfig.json >/tmp/cis-tsc-plain.log 2>&1; then
  fail "tsc --noEmit -p /app/cistern/tsconfig.json failed"
  tail -8 /tmp/cis-tsc-plain.log >&2
fi
hardened none

if ! ( cd "$REPO" && "$VITEST" run --reporter=dot >/tmp/cis-vitest.log 2>&1 ); then
  fail "vitest run failed"
  tail -15 /tmp/cis-vitest.log >&2
else
  if grep -qE "[0-9]+ failed" /tmp/cis-vitest.log; then
    fail "vitest reported failed tests"
  fi
fi

# --------------------------------------------------------- hidden cases
hidden=/tests/hidden
if [ -d "$hidden" ]; then
  for case in h1 h2; do
    if [ ! -f "$hidden/$case/probe.ts" ]; then
      fail "hidden case $case missing probe.ts"
      continue
    fi
  done
  rm -rf "$REPO/src/typetests"
  mkdir -p "$REPO/src/typetests"
  cp "$hidden/h1/probe.ts" "$REPO/src/typetests/probe1.ts"
  cp "$hidden/h2/probe.ts" "$REPO/src/typetests/probe2.ts"
  if ! "$TSC" --noEmit -p /app/cistern/tsconfig.json >/tmp/cis-tsc-h.log 2>&1; then
    fail "hidden probes do not compile under the delivered tsconfig"
    tail -12 /tmp/cis-tsc-h.log >&2
  fi
  hardened hidden
fi

# ---------------------------------------------------------------- verdict
if [ "$FAILED" = 1 ]; then
  echo "VERDICT: FAIL" >&2
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi
echo "VERDICT: PASS (strict + hardened tsc, vitest and hidden probes all green)" >&2
echo 1 > /logs/verifier/reward.txt
exit 0