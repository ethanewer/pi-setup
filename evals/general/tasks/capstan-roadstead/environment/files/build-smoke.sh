#!/bin/bash
# Build-time smoke checks for capstan-roadstead. Proves the shipped image is
# exactly the mined state in BOTH directions, inside this image:
#   parent source + golden regression test -> the four option-related tests
#     fail and the direct repro prints 'true true';
#   fix source + golden regression test    -> 10/10 pass and the direct
#     repro prints 'true false'.
# Also proves the agent-facing /app/repro.sh fails on the buggy tree with
# the mined symptom. Runs only at image build time; the trial has no
# network. Scrubs /tmp/fix-src (the fix source) and its own scratch when
# done.
set -e
SRC=/app/src
TS=/opt/tsapp
PARENT=69b089574f10e607a93ad1b3eb56b4876e2a43fb
FIX=4a65c5aa40e31cd0aa377c33540891bc03572b16

# --- the trial clone must not be able to reach the fix commit ---------------
test "$(git -C "$SRC" rev-parse HEAD)" = "$PARENT"
if git -C "$SRC" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
  echo "smoke ERROR: fix commit reachable from /app/src" >&2; exit 1
fi
test "$(git -C "$SRC" rev-list --all --count)" = "1"
test -z "$(git -C "$SRC" status --porcelain)"
echo "smoke ok: /app/src is exactly the pinned parent commit"

make_run() {  # make_run <outdir> <globsmatcher.ts> <testfile>
  out=$1; gm=$2; tf=$3
  rm -rf "$out"; mkdir -p "$out/__tests__"
  cp "$gm" "$out/globsToMatcher.ts"
  cp "$SRC/packages/jest-util/src/replacePathSepForGlob.ts" "$out/"
  cp "$TS/tsconfig.json" "$out/"
  cp "$TS/jest.config.json" "$out/"
  ln -s "$TS/node_modules" "$out/node_modules"
  cp "$tf" "$out/__tests__/globsToMatcher.test.ts"
}

# --- direction 1: the BUGGY parent source -------------------------------------
make_run /tmp/smoke-parent "$SRC/packages/jest-util/src/globsToMatcher.ts" \
  /opt/golden/globsToMatcher.test.ts
(
  cd /tmp/smoke-parent \
  && "$TS/node_modules/.bin/tsc" -p tsconfig.json \
  && "$TS/node_modules/.bin/jest" out/__tests__/ > /tmp/smoke-parent.log 2>&1 || true
)
grep -qE "Tests:[ ]*4 failed" /tmp/smoke-parent.log \
  || { echo "smoke ERROR: golden did not fail exactly 4 at parent"; tail -20 /tmp/smoke-parent.log; exit 1; }
grep -qE "6 passed" /tmp/smoke-parent.log \
  || { echo "smoke ERROR: golden pass count != 6 at parent"; tail -20 /tmp/smoke-parent.log; exit 1; }
node -e "const g=require('/tmp/smoke-parent/out/globsToMatcher.js').default; console.log(g(['*.dotoption.js'])('.hidden.dotoption.js'), g(['*.dotoption.js'],{dot:false})('.hidden.dotoption.js'))" \
  > /tmp/smoke-parent-repro.log
grep -Fxq "true true" /tmp/smoke-parent-repro.log \
  || { echo "smoke ERROR: parent repro did not print 'true true'"; cat /tmp/smoke-parent-repro.log; exit 1; }
echo "smoke ok: parent direction -> golden fails 4/6 and repro prints 'true true'"

# --- the agent-facing repro driver must fail on the buggy tree ----------------
if bash /app/repro.sh > /tmp/smoke-reprosh.log 2>&1; then
  echo "smoke ERROR: /app/repro.sh exited 0 on the buggy tree" >&2; exit 1
fi
grep -q "true true" /tmp/smoke-reprosh.log \
  || { echo "smoke ERROR: repro.sh did not print 'true true' on the buggy tree"; cat /tmp/smoke-reprosh.log; exit 1; }
echo "smoke ok: /app/repro.sh fails on the buggy tree"

# --- direction 2: the FIX source (extracted from the fix commit) --------------
make_run /tmp/smoke-fix /tmp/fix-src/globsToMatcher.ts \
  /opt/golden/globsToMatcher.test.ts
(
  cd /tmp/smoke-fix \
  && "$TS/node_modules/.bin/tsc" -p tsconfig.json \
  && "$TS/node_modules/.bin/jest" out/__tests__/ > /tmp/smoke-fix.log 2>&1
) || { echo "smoke ERROR: tsc/jest failed on the fix source"; tail -20 /tmp/smoke-fix.log; exit 1; }
grep -qE "Tests:[ ]*10 passed" /tmp/smoke-fix.log \
  || { echo "smoke ERROR: golden did not pass 10/10 on the fix source"; tail -20 /tmp/smoke-fix.log; exit 1; }
node -e "const g=require('/tmp/smoke-fix/out/globsToMatcher.js').default; console.log(g(['*.dotoption.js'])('.hidden.dotoption.js'), g(['*.dotoption.js'],{dot:false})('.hidden.dotoption.js'))" \
  > /tmp/smoke-fix-repro.log
grep -Fxq "true false" /tmp/smoke-fix-repro.log \
  || { echo "smoke ERROR: fix repro did not print 'true false'"; cat /tmp/smoke-fix-repro.log; exit 1; }
echo "smoke ok: fix direction -> golden passes 10/10 and repro prints 'true false'"

# --- scrub the answer and the scratch out of the image ------------------------
rm -rf /tmp/fix-src /tmp/smoke-parent /tmp/smoke-fix
rm -f /tmp/smoke-*.log
echo "smoke: both directions re-confirmed inside this image"