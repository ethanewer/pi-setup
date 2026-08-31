#!/bin/bash
# Verifier for briar-anvil: enforces the one-file/no-hack rules, recompiles the
# deliverable from /app/src/ledger.c, and EXECUTES /app/src/memledger under
# valgrind --leak-check=full on the visible sample and on every hidden ledger
# in /tests/hidden, comparing stdout byte-for-byte and requiring zero definite
# leaks and exit status 0. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_UTIL_C_SHA="a621731f44ca66845ca3570c33311e1ed6deada57c2abc63ff08d31072becb6e"
PRISTINE_UTIL_H_SHA="2bc268de9d43f5b55ca11f6ce3553993b4e4e1d0cde4b6c0182e7ebb9e039d2a"
PRISTINE_MAKEFILE_SHA="60d507e04bdaa48ad5c7e3b8b246e71fed50e04045ca1c0bbe98479c3e101a67"
PRISTINE_SAMPLE_SHA="01554e0bd5dcf06acc2ccdb9a31922f8c4941cd67b4f3abd44ddb86771c4849a"

failures=""

check_sha() {
    path="$1"; want="$2"; label="$3"
    if [ ! -f "$path" ]; then
        failures="$failures $label-missing"
        return
    fi
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        failures="$failures $label-modified"
    fi
}
check_sha /app/src/util.c "$PRISTINE_UTIL_C_SHA" util.c
check_sha /app/src/util.h "$PRISTINE_UTIL_H_SHA" util.h
check_sha /app/src/Makefile "$PRISTINE_MAKEFILE_SHA" Makefile
check_sha /app/sample.ledger "$PRISTINE_SAMPLE_SHA" sample.ledger

# Hygiene: the repaired lifecycle must unwind by normal returns — no
# exit/abort shortcuts in the sanctioned file.
if [ -f /app/src/ledger.c ]; then
    if grep -nE '\b(exit|_exit|_Exit|abort)[[:space:]]*\(' /app/src/ledger.c >/dev/null 2>&1; then
        failures="$failures ledger.c-calls-exit/abort"
    fi
else
    failures="$failures ledger.c-missing"
fi

# Rebuild the deliverable binary from the delivered source.
rm -f /app/src/memledger
if ! make -C /app/src > /tmp/briar_make.log 2>&1 || [ ! -x /app/src/memledger ]; then
    failures="$failures build-failed"
    tail -20 /tmp/briar_make.log >&2 || true
fi

run_case() {
    # $1 = ledger file, $2 = expected stdout file
    local input="$1" expected="$2"
    local out=/tmp/briar_stdout.txt
    local vlog=/tmp/briar_valgrind.txt

    rm -f "$out" "$vlog"
    # -k 100: keep going after errors; leak-check=full; error exit code 97.
    if ! valgrind --leak-check=full --show-leak-kinds=definite,indirect \
         --errors-for-leak-kinds=definite,indirect --error-exitcode=97 \
         -q /app/src/memledger "$input" > "$out" 2> "$vlog"; then
        echo "case '$input': nonzero/valgrind-error exit status" >&2
        cat "$vlog" >&2 || true
        return 1
    fi
    # Guarded parse of the valgrind summary (defense in depth alongside
    # --error-exitcode): must explicitly say no leaks are possible.
    if ! grep -q "All heap blocks were freed -- no leaks are possible" "$vlog"; then
        echo "case '$input': valgrind summary does not confirm zero leaks" >&2
        cat "$vlog" >&2 || true
        return 1
    fi
    if ! grep -q "ERROR SUMMARY: 0 errors" "$vlog"; then
        echo "case '$input': valgrind reported errors" >&2
        cat "$vlog" >&2 || true
        return 1
    fi
    if ! cmp -s "$out" "$expected"; then
        echo "case '$input': stdout mismatch" >&2
        diff "$expected" "$out" >&2 || true
        return 1
    fi
    return 0
}

if [ -z "$failures" ] && [ -x /app/src/memledger ]; then
    # --- visible case ---
    if ! run_case /app/sample.ledger /tests/expected_visible.txt; then
        failures="$failures visible-case"
    fi
    # --- hidden cases ---
    if [ ! -d /tests/hidden ] || [ -z "$(ls -A /tests/hidden 2>/dev/null)" ]; then
        failures="$failures no-hidden-cases"
    else
        for d in /tests/hidden/*/; do
            input="${d}input.ledger"
            expected="${d}expected.txt"
            if [ ! -f "$input" ] || [ ! -f "$expected" ]; then
                failures="$failures hidden-malformed($(basename "$d"))"
                continue
            fi
            if ! run_case "$input" "$expected"; then
                failures="$failures hidden($(basename "$d"))"
            fi
        done
    fi
else
    failures="$failures precondition"
fi

echo "verify failures:$failures" >&2
if [ -z "$failures" ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
