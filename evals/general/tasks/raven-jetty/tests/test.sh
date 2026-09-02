#!/bin/bash
# Verifier for tasks/raven-jetty (executes-deliverable).
#
# Independently re-executes every deliverable from a clean state and checks the
# four competency gates:
#   * C-b45b6939  the static clone is rebuilt in a clean scratch dir and
#                 byte-exact on hidden binary inputs (empty/NUL/short/large)
#   * C-d4f27a42  the engine header resolves via a configured include path
#                 (and never via a bare clang -E)
#   * C-583195c6  distinct flag sets reproduce distinct build-mode behavior
#                 and coverage artifacts appear only for the --coverage build
#   * C-8aca263c  the (repaired) toy compiler rejects real VLAs with a non-zero
#                 error on hidden VLA sources and still accepts honest sources
# Writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
FAIL=()

fail() { FAIL+=("$1"); }

SCRATCH=$(mktemp -d /tmp/vrfy.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

HALL=/tests/hidden

# ---------------------------------------------------------------------------
# A. Clone: clean-scratch static rebuild + byte-exact hidden transform checks
# ---------------------------------------------------------------------------
has() { [ -f "$1" ]; }
if ! has /app/clone/app.c || ! has /app/clone/Makefile || ! has /app/clone/app; then
    fail "A0: clone deliverables missing (/app/clone/app.c|Makefile|app)"
else
    # Rebuild ONLY from the source in a pristine scratch directory.
    cd "$SCRATCH" || exit 1
    rm -rf clonescr && mkdir clonescr && cd clonescr
    cp /app/clone/app.c /app/clone/Makefile ./
    if ! make >make.log 2>&1; then
        fail "A1: clean-scratch make failed: $(tail -3 make.log)"
    else
        if [ ! -x ./app ]; then
            fail "A2: make did not produce ./app in scratch dir"
        else
            if ! file ./app | grep -q "statically linked"; then
                fail "A3: ./app is not statically linked: $(file ./app)"
            fi
            # sanity: source must not depend on the /app tree or the legacy
            # loader, and only uses standard headers.
            if grep -q "/app" /app/clone/app.c; then
                fail "A4: app.c references /app (not self-contained)"
            fi
            if grep -E '^\s*#include' /app/clone/app.c | grep -vE '^\s*#include\s*<(stdio\.h|stdlib\.h|stdint\.h|string\.h|unistd\.h|fcntl\.h|errno\.h|stdbool\.h|stddef\.h|inttypes\.h)>';
            then
                fail "A4b: app.c uses a non-standard include"
            fi
            if grep -qiE 'tx-71|legacy loader' /app/clone/app.c; then
                fail "A4c: app.c references the original loader"
            fi
            # Run on every hidden transform fixture and cmp byte-exact.
            for c in "$HALL"/transform/c*; do
                [ -d "$c" ] || continue
                name=$(basename "$c")
                timeout 20 ./app < "$c/in.bin" > out.bin 2>err.txt
                rc=$?
                if [ "$rc" -ne 0 ]; then
                    fail "A5: $name rc=$rc"
                elif ! cmp -s out.bin "$c/out.bin"; then
                    fail "A6: $name byte mismatch (got $(wc -c <out.bin) want $(wc -c < "$c/out.bin"))"
                fi
            done
            # Explicit edge: empty input must map to empty output, exit 0.
            : > empty.bin
            timeout 20 ./app < empty.bin > eout.bin 2>/dev/null
            if [ $? -ne 0 ] || [ -s eout.bin ]; then
                fail "A7: empty-input handling broken"
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# B. Engine header on the preprocessor include path
# ---------------------------------------------------------------------------
if ! has /app/include-path.sh; then
    fail "B0: /app/include-path.sh missing"
else
    [ -x /app/include-path.sh ] || fail "B0b: /app/include-path.sh not executable"
    cd "$SCRATCH" || exit 1
    rm -rf incscr && mkdir incscr && cd incscr
    # Causality probe: patch the engine header to a sentinel level, then
    # re-run include-path.sh. A genuine include-path wiring compiles the probe
    # against the real header and must report the SENTINEL value; a proof log
    # that was hard-coded (never compiled) keeps reporting the original 9.
    HEADER=/app/engine/include/hull/engine.h
    if [ -r "$HEADER" ]; then
        cp "$HEADER" "$SCRATCH/engine.h.bak"
        sed -i 's/#define HULL_LEVEL 9/#define HULL_LEVEL 983/' "$HEADER"
    else
        fail "B1b: engine header not found ($HEADER)"
    fi
    if ! bash /app/include-path.sh >/dev/null 2>im.log; then
        fail "B1: include-path.sh failed: $(tail -3 im.log)"
    else
        if [ ! -f include-proof.log ]; then
            fail "B2: include-path.sh did not write include-proof.log"
        elif ! grep -q 'hull_level=983' include-proof.log; then
            fail "B3: include-proof.log is not derived from a live clang compile "\
                 "through the include path (expected hull_level=983): "\
                 "$(head -2 include-proof.log)"
        elif ! grep -q 'raven-weave' include-proof.log; then
            fail "B3b: include-proof.log missing engine tag: $(head -2 include-proof.log)"
        else
            # The proof must really come through the include path: without it,
            # clang must NOT find <hull/engine.h>.
            cat > bare.c <<'EOF'
#include <hull/engine.h>
int main(void){ return HULL_LEVEL; }
EOF
            if env -u CPATH -u C_INCLUDE_PATH clang bare.c -o /dev/null 2>/dev/null; then
                fail "B4: <hull/engine.h> resolved WITHOUT an include path"
            fi
        fi
    fi
    # restore the engine header exactly
    if [ -f "$SCRATCH/engine.h.bak" ]; then
        cp "$SCRATCH/engine.h.bak" "$HEADER"
    fi
    # deliverable proof log from the authoring run (original header values)
    if ! grep -qE "probe|hull_level=9" /app/include-proof.log 2>/dev/null; then
        fail "B5: /app/include-proof.log deliverable invalid"
    fi
fi

# ---------------------------------------------------------------------------
# C. Distinct build modes: fresh-range logs + coverage only for --coverage
# ---------------------------------------------------------------------------
if ! has /app/build-modes.sh; then
    fail "C0: /app/build-modes.sh missing"
else
    cd "$SCRATCH" || exit 1
    rm -rf bmscr && mkdir bmscr && cd bmscr
    if ! bash /app/build-modes.sh 1001 2000 >/dev/null 2>bm.log; then
        fail "C1: build-modes.sh failed: $(tail -3 bm.log)"
    else
        for f in mode-fast.log mode-debug.log bm_fast bm_debug bm_release bm_trace; do
            [ -f "$f" ] || fail "C2: build-modes.sh did not create $f"
        done
        if [ ! -f mode-fast.log ] || [ ! -f mode-debug.log ]; then
            :
        else
            fast=$(cat mode-fast.log)
            dbg=$(cat mode-debug.log)
            case "$fast" in
                *"lo=1001"*hi=2000*|*mode=SAILOR*) ;;
                *) fail "C3: mode-fast.log unexpected: $fast" ;;
            esac
            if ! echo "$fast" | grep -q "acc=1500500"; then
                fail "C4: fast log wrong acc: $fast"
            fi
            if ! echo "$dbg"  | grep -q "acc=1500500"; then
                fail "C4b: debug log wrong acc: $dbg"
            fi
            if [ "$fast" = "$dbg" ]; then
                fail "C5: fast and debug logs identical (no mode behavior)"
            fi
            # mode-specific value difference exactly as documented
            case "$dbg" in *"value=1500507"*) ;; *) fail "C5b: debug mode value wrong: $dbg" ;; esac
            case "$fast" in *"value=1500500"*) ;; *) fail "C5c: fast mode value wrong: $fast" ;; esac
        fi
        # coverage artifacts must exist (instrumented build compiled and ran)
        if [ ! -f bmsrc.gcno ] || [ ! -f bmsrc.gcda ]; then
            fail "C6: coverage artifacts missing (gcno=$(ls bmsrc.gcno 2>/dev/null || echo no) gcda=$(ls bmsrc.gcda 2>/dev/null || echo no))"
        fi
    fi
    # deliverable logs from the authoring run (default 1..100)
    if ! grep -q "acc=5050" /app/mode-fast.log 2>/dev/null \
       || ! grep -q "value=5050" /app/mode-fast.log 2>/dev/null; then
        fail "C7: /app/mode-fast.log deliverable invalid: $(head -1 /app/mode-fast.log)"
    fi
    if ! grep -q "value=5057" /app/mode-debug.log 2>/dev/null; then
        fail "C8: /app/mode-debug.log deliverable invalid: $(head -1 /app/mode-debug.log)"
    fi
fi

# ---------------------------------------------------------------------------
# D. Toy compiler rejects genuine VLAs (hidden probes, recompiled source)
# ---------------------------------------------------------------------------
if ! has /app/toycc.c || ! has /app/toycc; then
    fail "D0: toycc deliverables missing (toycc.c/toycc)"
else
    gcc -Wall -Wextra -O2 -o "$SCRATCH/toycc_check" /app/toycc.c 2>"$SCRATCH/toycc_build.log" \
        || fail "D0b: /app/toycc.c does not compile"

    run_toy() { # $1 file, expect rc OK when 0 given
        res=$(timeout 20 "$SCRATCH/toycc_check" "$1" 2>"$SCRATCH/toy_err.txt")
        rc=$?
        echo "$rc:$res"
    }

    # D1: genuine variable-size VLA must REJECT (non-zero) with diagnostic.
    r=$(run_toy "$HALL/toy_probe/vla_var.c")
    rc=${r%%:*}
    out=${r#*:}
    if [ "$rc" = "0" ]; then
        fail "D1: VLA var accepted rc=0: $out"
    fi
    if ! grep -q "toycc: error:" "$SCRATCH/toy_err.txt" \
       || ! grep -qi "variable-length array" "$SCRATCH/toy_err.txt"; then
        fail "D1b: VLA var no diagnostic: $(head -1 "$SCRATCH/toy_err.txt")"
    fi
    case "$out" in *ok*) fail "D1c: VLA var still printed ok" ;; esac

    # D2: VLA via macro/expression/unsized must REJECT.
    r=$(run_toy "$HALL/toy_probe/vla_expr.c")
    rc=${r%%:*}
    out=${r#*:}
    if [ "$rc" = "0" ]; then
        fail "D2: VLA expr accepted rc=0"
    fi
    case "$out" in *ok*) fail "D2b: VLA expr still printed ok" ;; esac

    # D3: honest fixed-size-array source must ACCEPT with ok.
    r=$(run_toy "$HALL/toy_probe/ok_fixed.c")
    rc=${r%%:*}
    out=${r#*:}
    if [ "$rc" != "0" ]; then
        fail "D3: legal fixed-array source rejected rc=$rc"
    fi
    case "$out" in ok*) ;; *) fail "D3b: legal source missing ok: $out" ;; esac

    # D4: empty/trivial source must ACCEPT with ok.
    r=$(run_toy "$HALL/toy_probe/empty.c")
    rc=${r%%:*}
    out=${r#*:}
    if [ "$rc" != "0" ]; then
        fail "D4: empty source rejected rc=$rc"
    fi
    case "$out" in ok*) ;; *) fail "D4b: empty source missing ok: $out" ;; esac

    # D5: deliverable vla.c is itself rejected by the agent's binary.
    if [ ! -f /app/vla.c ]; then
        fail "D5: /app/vla.c missing"
    else
        if timeout 20 /app/toycc /app/vla.c >/dev/null 2>/dev/null; then
            fail "D5b: /app/toycc accepted /app/vla.c"
        fi
    fi

    # D6: deliverable reject.log documents the rejection.
    if [ ! -f /app/reject.log ]; then
        fail "D6: /app/reject.log missing"
    elif ! grep -q "toycc: error:" /app/reject.log; then
        fail "D6b: /app/reject.log has no diagnostic: $(head -1 /app/reject.log)"
    fi
fi

# ---------------------------------------------------------------------------
# verdict
# ---------------------------------------------------------------------------
if [ "${#FAIL[@]}" -gt 0 ]; then
    echo "FAILURES (${#FAIL[@]}):"
    printf '  - %s\n' "${FAIL[@]}"
    echo "0" > /logs/verifier/reward.txt
else
    echo "ALL PASS (raven-jetty)"
    echo "1" > /logs/verifier/reward.txt
fi
exit 0