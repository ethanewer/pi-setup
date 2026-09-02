#!/bin/bash
# Verifier for tasks/larch-terrace (executes-deliverable).
#
# Rebuilds/reruns each deliverable and independently checks:
#   * /app/game.mips is a little-endian MIPS ELF that runs under qemu-user-static
#     and reproduces the additive-game answers on hidden inputs,
#   * /app/Makefile is retargeted to gfortran (does not mention the legacy
#     frontend) and cleanly rebuilds /app/main, which answers hidden inputs,
#   * /app/poly.c is a genuine C/Python polyglot (builds+prints LANG:C under gcc,
#     runs+prints LANG:PY under python3),
#   * /app/app (C arg-max autoregressive sampler) reproduces the documented
#     deterministic continuation on hidden prompts, its source /app/app.c is
#     modular (>=4 named helper functions) and stays under the compressed cap,
#   * /app/scheme.py evaluates hidden Scheme programs.
# Ends by writing a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
HALL=/tests/hidden
failures=()

note() { failures+=("$1"); }

[ -f /app/game.mips ] || note "missing /app/game.mips"
[ -f /app/main ]     || note "missing /app/main"
[ -f /app/Makefile ] || note "missing /app/Makefile"
[ -f /app/poly.c ]   || note "missing /app/poly.c"
[ -f /app/app ]      || note "missing /app/app"
[ -f /app/scheme.py ]|| note "missing /app/scheme.py"

# ---------------------------------------------------------------------
# 1) MIPS game ELF
# ---------------------------------------------------------------------
if [ -f /app/game.mips ]; then
    # Must actually be an ELF for the MIPS (little-endian) machine so that
    # qemu-mipsel-static is needed to run it under this x86_64 host.
    if ! head -c4 /app/game.mips | grep -q $'\x7fELF'; then
        note "game.mips is not an ELF"
    fi
    for d in "$HALL"/game/*/; do
        exp=$(cat "$d/expected.txt")
        got=$(QEMU_LD_PREFIX=/usr/mipsel-linux-gnu qemu-mipsel-static /app/game.mips < "$d/input.txt" 2>/dev/null | tr -d '\r')
        if [ "$got" != "$exp" ]; then
            note "game $(basename "$d"): got [$got] want [$exp]"
        fi
    done
fi

# ---------------------------------------------------------------------
# 2) Fortran via retargeted gfortran Makefile
# ---------------------------------------------------------------------
if [ -f /app/Makefile ]; then
    # textual: must target gfortran, not the legacy frontend
    if ! grep -q "gfortran" /app/Makefile; then
        note "Makefile does not use gfortran"
    fi
    if grep -qE "ifort|pgfortran|pgf90|flang" /app/Makefile; then
        note "Makefile still references the legacy frontend"
    fi
    # rebuild cleanly from source to prove the Makefile is real
    ( cd /app && make -s -f Makefile clean >/dev/null 2>&1; make -s -f Makefile >/dev/null 2>&1 ) \
        || note "make with /app/Makefile failed"
fi
if [ -x /app/main ]; then
    for d in "$HALL"/fortran/*/; do
        exp=$(cat "$d/expected.txt")
        got=$(/app/main < "$d/input.txt" 2>/dev/null | tr -d '\r' | grep -v '^$' | tail -1)
        if [ "$got" != "$exp" ]; then
            note "fortran $(basename "$d"): got [$got] want [$exp]"
        fi
    done
else
    note "/app/main not executable"
fi

# ---------------------------------------------------------------------
# 3) C/Python polyglot
# ---------------------------------------------------------------------
if [ -f /app/poly.c ]; then
    if gcc -x c -o /tmp/polybuild /app/poly.c 2>/dev/null; then
        c_out=$(/tmp/polybuild | tr -d '\r')
        [ "$c_out" = "LANG:C" ] || note "poly C output [$c_out] != LANG:C"
    else
        note "poly.c does not compile under gcc"
    fi
    py_out=$(python3 /app/poly.c 2>/dev/null | tr -d '\r')
    [ "$py_out" = "LANG:PY" ] || note "poly python output [$py_out] != LANG:PY"
    rm -f /tmp/polybuild
fi

# ---------------------------------------------------------------------
# 4) Arg-max autoregressive sampler (C) on hidden prompts
# ---------------------------------------------------------------------
if [ -f /app/app ] && [ -x /app/app ]; then
    for d in "$HALL"/sampler/*/; do
        exp=$(cat "$d/expected.txt")
        got=$(/app/app < "$d/input.txt" 2>/dev/null | tr -d '\r')
        [ "$got" = "$exp" ] || note "sampler $(basename "$d"): got [$got] want [$exp]"
    done
else
    note "/app/app not runnable"
fi
# modularity + compressed source cap on /app/app.c
if [ -f /app/app.c ]; then
    nfn=$(grep -cE '^[[:space:]]*(static[[:space:]]+)?(int|void|long|double)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(' /app/app.c)
    [ "$nfn" -ge 4 ] || note "app.c too few helper functions ($nfn)"
    gz=$(gzip -c /app/app.c | wc -c)
    [ "$gz" -lt 3000 ] || note "app.c too large under gzip ($gz bytes)"
else
    note "missing /app/app.c for modularity/cap checks"
fi

# ---------------------------------------------------------------------
# 5) Scheme metacircular evaluator
# ---------------------------------------------------------------------
if [ -f /app/scheme.py ]; then
    for d in "$HALL"/scheme/*/; do
        exp=$(cat "$d/expected.txt")
        got=$(python3 /app/scheme.py < "$d/program.scm" 2>/dev/null | tr -d '\r')
        [ "$got" = "$exp" ] || note "scheme $(basename "$d"): got [$got] want [$exp]"
    done
else
    note "/app/scheme.py missing"
fi

if [ ${#failures[@]} -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
    echo "ALL CHECKS PASS"
else
    echo "0" > /logs/verifier/reward.txt
    printf 'FAILED:\n'
    printf '  - %s\n' "${failures[@]}"
fi
