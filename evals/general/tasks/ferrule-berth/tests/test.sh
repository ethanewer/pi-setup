#!/bin/bash
# Verifier for ferrule-berth (upstream-clone SAT-solver task against
# arminbiere/cadical). Checks, in order:
#   1. deliverables exist: /app/driver.sh (executable) and /app/cadical
#      (the agent-built solver binary),
#   2. /app/cadical is really CaDiCaL at the pinned commit,
#   3. /app/driver.sh actually invokes /app/cadical, and the agent really
#      built its solver (its /app/src/build/cadical exists; the image ships
#      only warm objects, never a finished solver binary, so the only way to
#      have a genuine solver is to run the project's own `make`),
#   4. the driver, run on every hidden fixture, reports the exact expected
#      verdict; every reported SAT model satisfies every clause of its own
#      input (independent clause-by-clause check); every unsatisfiable plain
#      CNF ships a non-empty ASCII LRAT proof whose last derived clause is
#      the empty clause, and that proof is accepted by the project's OWN
#      standalone proof checker lrat-trim (compiled from the pinned clone at
#      image build time into /opt/lrat-trim). lrat-trim validates the proof
#      independently of anything the agent built or placed on disk, so a
#      forged or corrupted proof can never self-validate through the agent's
#      own binary.
# Reward is binary and written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
failures=0

PIN_SHA=c60730422e758ef1cebe7aeddf2dda31c996bf04
BIN=/app/cadical
DRIVER=/app/driver.sh
LRAT_TRIM=/opt/lrat-trim   # the project's own independent proof checker

# ---- 1. deliverables --------------------------------------------------------
if [ ! -x "$DRIVER" ]; then
    echo "FAIL: deliverable $DRIVER missing or not executable" >&2
    failures=1
fi
if [ ! -x "$BIN" ]; then
    echo "FAIL: deliverable $BIN (agent-built solver) missing" >&2
    failures=1
fi
if [ ! -x "$LRAT_TRIM" ]; then
    echo "FAIL: reference proof checker $LRAT_TRIM missing" >&2
    failures=1
fi

# ---- 2. the binary must be the pinned solver, not an impostor --------------
if [ -x "$BIN" ]; then
    ident_log="$(mktemp)"
    if "$BIN" /app/cases/simple-sat.cnf "$ident_log.lrat" 2>/dev/null \
       | grep -m1 '^c Version 3.0.1' | grep -qF "$PIN_SHA"; then
        echo "cadical identity: ok (3.0.1 @ $PIN_SHA)"
    else
        echo "FAIL: $BIN is not CaDiCaL 3.0.1 of the pinned commit" >&2
        failures=1
    fi
    rm -f "$ident_log.lrat"
fi
if [ ! -f /app/src/src/cadical.cpp ] || [ ! -x /app/src/configure ]; then
    echo "FAIL: /app/src is not the CaDiCaL source tree" >&2
    failures=1
fi
# the source tree must still be the pinned commit (no committed tampering)
if [ -d /app/src/.git ] && ! { "$(command -v git)" -C /app/src rev-parse HEAD 2>/dev/null | grep -qxF "$PIN_SHA"; }; then
    echo "FAIL: /app/src is not at the pinned commit" >&2
    failures=1
fi
# ...and no tracked source file may have been edited (an unmodified tree is
# what 'pinned source' means for the build). Untracked build artifacts are fine.
if [ -d /app/src/.git ] \
   && { "$(command -v git)" -C /app/src status --porcelain --untracked-files=no 2>/dev/null | grep -q .; }; then
    echo "FAIL: /app/src has tracked modifications" >&2
    failures=1
fi

# ---- 3. the driver must drive the built solver, and the solver must have
#        been built in-trial from the phone source. The image ships only
#        warm object files, never a finished solver binary, so a genuine
#        /app/cadical can only exist if the agent ran the project's own
#        `make` (which produces /app/src/build/cadical).
if [ -f "$DRIVER" ] && ! grep -qF "$BIN" "$DRIVER"; then
    echo "FAIL: $DRIVER does not invoke $BIN" >&2
    failures=1
fi
if [ ! -x /app/src/build/cadical ]; then
    echo "FAIL: /app/src/build/cadical does not exist -- the solver was not built" >&2
    echo "      in-trial by the project's own build system" >&2
    failures=1
fi

# ---- 4. hidden fixtures -----------------------------------------------------
run_cases=0
for case_dir in /tests/hidden/*/; do
    [ -d "$case_dir" ] || continue
    run_cases=$((run_cases + 1))
    name="$(basename "$case_dir")"
    expected="$(cat "$case_dir/expected.verdict")"
    if [ -f "$case_dir/input.cnf" ]; then
        input="$case_dir/input.cnf"; kind=plain
    else
        input="$case_dir/input.icnf"; kind=incremental
    fi

    case_log="$(mktemp -d)"
    if ! "$DRIVER" "$input" "$case_log" > "$case_log/driver.out" 2>&1; then
        echo "FAIL case $name: $DRIVER exited nonzero" >&2
        tail -5 "$case_log/driver.out" >&2
        failures=1
        continue
    fi

    got="$(cat "$case_log/verdict" 2>/dev/null || true)"
    if [ "$got" != "$expected" ]; then
        echo "FAIL case $name: verdict '$got' != expected '$expected'" >&2
        failures=1
    fi

    if [ "$expected" = "s SATISFIABLE" ]; then
        # every reported model literal set must satisfy every clause
        if [ ! -s "$case_log/model" ]; then
            echo "FAIL case $name: no model in $case_log/model" >&2
            failures=1
        else
            if python3 - "$input" "$case_log/model" <<'PY'
import sys
cnf, model_path = sys.argv[1], sys.argv[2]
def clauses_of(path):
    out = []
    for ln in open(path):
        ln = ln.strip()
        if not ln or ln[0] in "cp":
            continue
        if ln[0] == 'a':
            continue
        lits = [int(x) for x in ln.split()[:-1]]
        if lits:
            out.append(lits)
    return out
clauses = clauses_of(cnf)
toks = [t for ln in open(model_path) if ln.startswith("v ") for t in ln.split() if t != "v"]
lits = [int(x) for x in toks[:-1]]
assigned = {abs(l): l > 0 for l in lits}
model_set = set(lits)
bad = [c for c in clauses
       if not any(l in model_set and (l > 0) == assigned[abs(l)] for l in c)]
if bad:
    print("MODEL-CHECK FAIL %d of %d clauses unsatisfied" % (len(bad), len(clauses)))
    for c in bad[:3]:
        print("  clause", " ".join(str(x) for x in c))
    sys.exit(1)
print("model-check ok: %d clauses, %d literals" % (len(clauses), len(lits)))
PY
            then
                :
            else
                echo "FAIL case $name: reported model does not satisfy input clauses" >&2
                failures=1
            fi
        fi
        # sanity: the fixture really is satisfiable for the real solver
        "$BIN" -q "$input" >/dev/null 2>&1
        rc=$?
        if [ $rc -ne 10 ]; then
            echo "FAIL case $name: fixture sanity (solver exit $rc, expected 10=SAT)" >&2
            failures=1
        fi
    fi

    if [ "$expected" = "s UNSATISFIABLE" ]; then
        if [ "$kind" = "plain" ]; then
            proof="$case_log/proof.lrat"
            if [ ! -s "$proof" ]; then
                echo "FAIL case $name: empty or missing $proof" >&2
                failures=1
            else
                last="$(tail -n1 "$proof")"
                if ! printf '%s' "$last" | grep -qE '^[0-9]+ 0([[:space:]]|$)'; then
                    echo "FAIL case $name: proof does not end in the empty clause" >&2
                    failures=1
                fi
                # reference: validate the proof with the project's OWN
                # standalone checker lrat-trim (compiled from the pinned clone
                # into /opt/lrat-trim). It verifies the whole derivation
                # against the formula independently of anything the agent
                # placed on disk.
                "$LRAT_TRIM" "$input" "$proof" > "$case_log/lrat.out" 2>&1
                if ! grep -q '^s VERIFIED' "$case_log/lrat.out"; then
                    echo "FAIL case $name: proof rejected by the project's lrat-trim checker" >&2
                    tail -3 "$case_log/lrat.out" >&2
                    failures=1
                else
                    echo "case $name: proof accepted by project lrat-trim (s VERIFIED)" 
                fi
            fi
        else
            # incremental: only the joint verdict matters
            "$BIN" -q "$input" >/dev/null 2>&1
            rc=$?
            if [ $rc -ne 20 ]; then
                echo "FAIL case $name: fixture sanity (solver exit $rc, expected 20=UNSAT)" >&2
                failures=1
            fi
        fi
    fi
    echo "case $name: verdict '$got' ok"
done

if [ "$run_cases" -lt 2 ]; then
    echo "FAIL: fewer than 2 hidden cases ran" >&2
    failures=1
fi

# ---- reward ---------------------------------------------------------------
if [ $failures -eq 0 ]; then
    echo "VERIFIER: all checks passed, reward=1"
    echo 1 > /logs/verifier/reward.txt
else
    echo "VERIFIER: failures present, reward=0" >&2
    echo 0 > /logs/verifier/reward.txt
fi
exit 0