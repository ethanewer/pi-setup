#!/bin/bash
# dune-mantle verifier entrypoint. Runs as root after the agent finishes.
# /tests is mounted read-only; /tests/hidden holds the hidden inputs.
set -uo pipefail
reward=0
log() { echo "[verify] $*"; }

mkdir -p /logs/verifier
final() { echo "$reward" > /logs/verifier/reward.txt; exit 0; }

# ---- hard preconditions -------------------------------------------------
if [ ! -x /app/solve.py ]; then log "missing executable /app/solve.py"; final; fi
if [ ! -r /app/answer.json ]; then log "missing /app/answer.json"; final; fi
if ! command -v symxe >/dev/null 2>&1; then log "symxe not on PATH"; final; fi

# ---- independent recomputation of wcnf/qfbv/seats/answer.json/coq -------
if ! /usr/bin/python3 /tests/verify.py; then
    log "verify.py reported failures"
    final
fi

# ---- symbolic engine on the hidden bitcode modules -------------------------
compile() {
    local name=$1 expect=$2
    local src=/tests/hidden/$name/input.c
    local bc=/tmp/dune_$name.bc
    if ! clang -emit-llvm -c "$src" -o "$bc" 2>/dev/null; then
        log "clang failed for $name"; return 1
    fi
    local out
    out=$(symxe run "$bc" 2>/dev/null) || { log "symxe failed on $name"; return 1; }
    local got
    got=$(echo "$out" | awk '/^PATHS /{print $2}')
    if [ "$got" != "$expect" ]; then
        log "$name expected PATHS=$expect got=$got"; return 1
    fi
    local n_tests
    n_tests=$(echo "$out" | awk '/^TEST /{n++} END{print n+0}')
    if [ "$n_tests" -lt "$expect" ]; then
        log "$name too few TEST witnesses ($n_tests)"; return 1
    fi
    return 0
}

ok=1
compile sym_branch2 2 || ok=0
compile sym_branch3 3 || ok=0
if [ "$ok" != 1 ]; then log "symbolic engine checks failed"; final; fi

# ---- malformed / non-bitcode input must NOT be accepted ------------------------
if symxe run /tests/hidden/sym_malformed/not_bitcode.bc >/dev/null 2>&1; then
    log "symxe accepted non-bitcode input (should exit non-zero)"
    final
fi

# ---- all checks passed ----------------------------------------------------------
reward=1
final