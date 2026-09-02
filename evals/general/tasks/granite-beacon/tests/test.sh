#!/bin/bash
# Verifier for tasks/granite-beacon (executes-deliverable).
# Re-runs every deliverable and checks behavior against hidden inputs plus
# an independent CompCert recompile.  Writes numeric reward to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

# Bring the CompCert toolchain onto PATH if a switch is configured.
export OPAMROOT=${OPAMROOT:-/root/.opam}
eval "$(opam env --switch=default 2>/dev/null)" || true

H=/tests/hidden
FAIL=false
failadd(){ echo "FAIL: $1"; FAIL=true; }

# ---------------------------------------------------------------------------
# 1) /app/modernized/  -> rebuild with cmake + g++, run choron on hidden lines
# ---------------------------------------------------------------------------
if [ ! -f /app/modernized/CMakeLists.txt ]; then
    failadd "modernized project missing"
else
    if cmake -S /app/modernized -B /tmp/rb_modern \
             -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=/tmp/rb_modern >/tmp/rb.log 2>&1 \
       && cmake --build /tmp/rb_modern >>/tmp/rb.log 2>&1; then
        choron=/tmp/rb_modern/choron
        for c in cpp1 cpp2 cpp3; do
            "$choron" < "$H/$c/input.txt" > /tmp/out.txt 2>/dev/null
            if ! cmp -s /tmp/out.txt "$H/$c/expected.txt"; then
                failadd "choron $c mismatch"
            fi
        done
    else
        failadd "modernized cmake build failed"
    fi
fi

# ---------------------------------------------------------------------------
# 2) /app/compressor/ + /app/compressor_tests.log
# ---------------------------------------------------------------------------
if [ ! -f /app/compressor/Cargo.toml ]; then
    failadd "compressor crate missing"
else
    if grep -qE "todo!|unimplemented!|panic!" /app/compressor/src/lib.rs; then
        failadd "placeholder body remains in compressor lib.rs"
    fi
    if [ -f /app/compressor_tests.log ] && grep -q "0 failed" /app/compressor_tests.log \
       && grep -q "test result: ok" /app/compressor_tests.log; then
        :
    else
        failadd "compressor_tests.log not green"
    fi
fi
# independent re-run of cargo test + probe on hidden pack inputs
if ! (
    cd /app/compressor && cargo test >/tmp/ct2.log 2>&1
) || ! grep -q "test result: ok" /tmp/ct2.log; then
    failadd "cargo test did not pass on re-run"
fi
probe=/app/compressor/target/release/probe
if [ ! -x "$probe" ]; then
    failadd "no probe binary"
else
    for p in pack1/pattern.bin pack2/skew.bin; do
        line=$("$probe" "$H/$p")
        orig=$(printf '%s' "$line" | sed -n 's/.*"original_len":\([0-9]*\).*/\1/p')
        comp=$(printf '%s' "$line" | sed -n 's/.*"compressed_len":\([0-9]*\).*/\1/p')
        ok=$(printf '%s' "$line" | sed -n 's/.*"roundtrip_ok":\(true\|false\).*/\1/p')
        if [ "$ok" != "true" ]; then failadd "probe $p roundtrip failed"; fi
        if [ -n "${comp:-}" ] && [ -n "${orig:-}" ]; then
            if [ "$comp" -ge "$orig" ]; then failadd "probe $p did not compress"; fi
        else
            failadd "probe $p bad json: $line"
        fi
    done
    line=$("$probe" "$H/pack3/empty.bin")
    ok=$(printf '%s' "$line" | sed -n 's/.*"roundtrip_ok":\(true\|false\).*/\1/p')
    orig=$(printf '%s' "$line" | sed -n 's/.*"original_len":\([0-9]*\).*/\1/p')
    if [ "$ok" != "true" ] || [ "$orig" != "0" ]; then
        failadd "probe empty file failed: $line"
    fi
fi

# ---------------------------------------------------------------------------
# 3) headless legacy tool build (/app/legacy_build.log + /app/legacy_tool/bin)
# ---------------------------------------------------------------------------
if ! grep -q "HEADLESS_BUILD_OK" /app/legacy_build.log 2>/dev/null; then
    failadd "legacy_build.log missing HEADLESS_BUILD_OK marker"
fi
if [ ! -x /app/legacy_tool/bin/transwc ]; then
    failadd "legacy headless binary not installed"
else
    if ldd /app/legacy_tool/bin/transwc 2>/dev/null | grep -qE "libX11|libXt"; then
        failadd "installed legacy binary links X libraries"
    fi
fi
# independent headless rebuild
if cmake -S /app/legacy_tool -B /tmp/rb_lt -DENABLE_GUI=OFF >/tmp/lt.log 2>&1 \
   && cmake --build /tmp/rb_lt >>/tmp/lt.log 2>&1; then
    ltb=/tmp/rb_lt/transwc
    if ldd "$ltb" 2>/dev/null | grep -qE "libX11|libXt"; then
        failadd "headless rebuild links X11"
    fi
    for c in legacy1 legacy2; do
        if [ "$c" = legacy2 ]; then inp="$H/legacy2/edge.txt"; else inp="$H/legacy1/in.txt"; fi
        "$ltb" < "$inp" > /tmp/out.txt 2>/dev/null
        if ! cmp -s /tmp/out.txt "$H/$c/expected.txt"; then
            failadd "transwc $c mismatch"
        fi
    done
    "$ltb" < /dev/null > /tmp/out.txt 2>/dev/null
    if [ -s /tmp/out.txt ]; then failadd "transwc empty input produced output"; fi
else
    failadd "headless legacy rebuild failed"
fi

# ---------------------------------------------------------------------------
# 4) /app/compcert_bin  (genuine CompCert ELF + execution + provenance hash)
# ---------------------------------------------------------------------------
if [ -x /app/compcert_bin ]; then
    out=$("/app/compcert_bin"; echo "__rc=$?")
    rc=$(printf '%s' "$out" | grep -o '__rc=[0-9]*' | head -1 | cut -d= -f2)
    if [ "$rc" != "0" ]; then failadd "compcert_bin nonzero exit"; fi
    printf '%s' "$out" | grep -q '^BEACON ' || failadd "compcert_bin stdout wrong"
else
    failadd "compcert_bin missing"
fi
file /app/compcert_bin 2>/dev/null | grep -q "ELF" || failadd "compcert_bin not an ELF"
if command -v ccomp >/dev/null 2>&1 && [ -f "$H/beacon/beacon.c" ]; then
    ccomp -O2 "$H/beacon/beacon.c" -o /tmp/refcc >/tmp/cc.log 2>&1
    if [ -x /tmp/refcc ]; then
        objcopy --dump-section .text=/tmp/t_del /app/compcert_bin
        objcopy --dump-section .text=/tmp/t_ref /tmp/refcc
        d1=$(md5sum < /tmp/t_del | awk '{print $1}')
        d2=$(md5sum < /tmp/t_ref | awk '{print $1}')
        if [ "$d1" != "$d2" ]; then
            failadd "compcert_bin .text does not match a fresh CompCert build"
        fi
    else
        failadd "Could not recompile beacon with ccomp"
    fi
else
    failadd "compcert toolchain or hidden beacon missing"
fi
if readelf -p .comment /app/compcert_bin 2>/dev/null | grep -qiE "gcc|clang|ubuntu"; then
    failadd "compcert_bin carries a mainstream-compiler .comment signature"
fi

# ---------------------------------------------------------------------------
# 5) /app/sizes.tsv  (accurate on-disk byte sizes)
# ---------------------------------------------------------------------------
if [ ! -f /app/sizes.tsv ]; then
    failadd "sizes.tsv missing"
else
    while IFS=$'\t' read -r p s; do
        [ -n "${p:-}" ] || continue
        if [ ! -f "$p" ]; then failadd "sizes.tsv references missing $p"; continue; fi
        real=$(stat -c %s "$p")
        if [ "$s" != "$real" ]; then
            failadd "sizes.tsv says $p=$s but file is $real"
        fi
    done < /app/sizes.tsv
    for need in /app/opt/gcc_O0 /app/opt/gcc_O2 /app/opt/clang_O2 /app/compcert_bin; do
        grep -q "$need" /app/sizes.tsv || failadd "sizes.tsv missing expected row $need"
    done
fi

# ---------------------------------------------------------------------------
# Finish: write reward
# ---------------------------------------------------------------------------
if [ "$FAIL" = true ]; then
    echo "0" > /logs/verifier/reward.txt
else
    echo "1" > /logs/verifier/reward.txt
fi
echo "REWARD=$(cat /logs/verifier/reward.txt)"
exit 0