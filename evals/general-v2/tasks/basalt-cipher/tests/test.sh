#!/usr/bin/env bash
# Verifier for basalt-cipher. Executes every deliverable against an independent
# oracle; ends by writing the reward to /logs/verifier/reward.txt.
set -uo pipefail
reward=1
mkdir -p /logs/verifier
TIMEOUT=90

fail(){ echo "FAIL: $*"; reward=0; }

# ---------------------------------------------------------------- 1. rebuild three
rm -rf /app/bin
if [ ! -f /app/Makefile ]; then
  fail "deliverable /app/Makefile missing"
fi
if ! make -C /app -f /app/Makefile >/tmp/make.log 2>&1; then
  fail "single Makefile failed to rebuild from clean"
fi
for b in prog weft selftest; do
  if [ ! -x "/app/bin/$b" ]; then fail "/app/bin/$b missing after make"; fi
done

# -------------------------------------------------------------- 2. zero external deps
for b in prog weft selftest; do
  ldout=$(ldd "/app/bin/$b" 2>&1)
  if echo "$ldout" | grep -q "not a dynamic executable"; then
    continue                                  # static => no shared deps
  fi
  bad=$(echo "$ldout" | grep -Eo "/[^ ]+\.so[^ ]*" \
        | grep -Ev "^(/lib/|/usr/lib/|/usr/lib64/|/lib64/)" || true)
  if [ -n "$bad" ]; then fail "$b carries external library deps: $bad"; fi
done

# ------------------------------------------------------------ 3. bare PATH invocation
prog_bin=$(command -v prog || true)
if [ -z "$prog_bin" ] || [ ! -x "$prog_bin" ]; then
  fail "prog is not bare-invocable via PATH"
fi

# execute the deliverable binary directly (not merely via the PATH symlink)
lp=$( (cd /tmp && /app/bin/prog xor 5a 1f0f) 2>/dev/null )
if [ "$lp" != "4555" ]; then
  fail "/app/bin/prog did not produce the exact expected byte output"
fi

# ------------------------------------------------------------------ 4. self-test sentinel
st=$( (cd /tmp && timeout "$TIMEOUT" selftest) 2>/dev/null ); strc=$?
if [ "$strc" -ne 0 ] || ! echo "$st" | grep -q "SELFTEST_OK"; then
  fail "untouched self-test did not return success sentinel"
fi

# ------------------------------------------------------------ 5. hidden cases (python)
if ! python3 /tests/hidden/_check.py /tests/hidden >/tmp/hidden.out 2>/tmp/hidden.err; then
  fail "hidden-case run failed"; echo "$reward" > /logs/verifier/reward.txt; exit 0
fi
if ! grep -q "ALL_HIDDEN_OK" /tmp/hidden.out; then
  fail "hidden cases: $(cat /tmp/hidden.out)"; fi

# ------------------------------------------------------ 6. strict fixed order
ab=$( (cd /tmp && prog xor 0203 01) 2>/dev/null )
ba=$( (cd /tmp && prog xor 01 0302) 2>/dev/null )
if [ -z "$ab" ] || [ "$ab" = "$ba" ]; then
  fail "prog does not honor strict fixed (positional) argument order"
fi

# ------------------------------------------------------ 7. build.sh reproducibility
if ! timeout "$TIMEOUT" /app/build.sh >/tmp/b1.log 2>&1; then
  fail "build.sh run #1 failed"
fi
[ -f /app/dist/basalt-src.tar.zst ] || fail "build.sh produced no dist/basalt-src.tar.zst"
magic=$(od -An -tx1 -N4 /app/dist/basalt-src.tar.zst | tr -d ' \n')
[ "$magic" = "28b52ffd" ] || fail "archive is not zstd-compressed"
if ! zstd -dc /app/dist/basalt-src.tar.zst 2>/dev/null \
    | tar -tf - 2>/dev/null | grep -q "basalt-1.2/src/prog.c"; then
  fail "archive listing is not a gnu tar containing the sources"
fi
h1=$(md5sum /app/dist/basalt-src.tar.zst 2>/dev/null | cut -d' ' -f1)
rm -rf /app/dist
if ! timeout "$TIMEOUT" /app/build.sh >/tmp/b2.log 2>&1; then
  fail "build.sh run #2 failed"
fi
h2=$(md5sum /app/dist/basalt-src.tar.zst 2>/dev/null | cut -d' ' -f1)
if [ -z "$h1" ] || [ "$h1" != "$h2" ]; then
  fail "build.sh archive is not reproducible run-to-run"
fi

# ---------------------------------------------------------------- result
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt