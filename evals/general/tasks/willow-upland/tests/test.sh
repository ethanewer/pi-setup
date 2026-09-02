#!/bin/bash
# Willow Upland verifier. Runs as root after the agent finishes; /tests is
# mounted read-only. Writes a numeric reward to /logs/verifier/reward.txt.
mkdir -p /logs/verifier

fail_count=0
p(){ echo "PASS: $1"; }
f(){ echo "FAIL: $1"; fail_count=$((fail_count+1)); }

# ---------- 1. static checks on /app/fix.sh --------------------------------
if python3 /tests/sanitize.py; then
    p "static (shebang, LF-only, allowlist)"
else
    f "static (shebang / LF-only / allowlist)"
fi

# ---------- helpers ---------------------------------------------------------
check_summary(){  # $1 = logs dir to score against
    python3 /tests/severity_ref.py "$1" > /tmp/expected.sum
    if cmp -s /tmp/expected.sum /app/out/summary/severity_counts.txt; then
        p "severity_counts matches for $1"
    else
        f "severity_counts mismatch for $1"
        echo "  expected:"; sed 's/^/    /' /tmp/expected.sum
        echo "  got:"; sed 's/^/    /' /app/out/summary/severity_counts.txt
    fi
}

stage_clean(){  # every remaining /app/stage top-level file is allowed; scratch kept
    local bad=0
    for f in /app/stage/*; do
        if [ -f "$f" ]; then
            case "$f" in
                *.proof) ;;
                */MANIFEST) ;;
                *) f "stage still has disallowed file: $f"; bad=1 ;;
            esac
        fi
    done
    if [ -d /app/stage/scratch ]; then
        p "scratch dir preserved"
    else
        f "scratch dir missing / removed"
        bad=1
    fi
    [ "$bad" -eq 0 ] && p "stage cleaned to allowed set"
}

check_make(){
    cd /app
    if [ -s /app/Makefile ]; then p "Makefile present"; else f "Makefile missing / empty"; fi
    make -f /app/Makefile clean >/dev/null 2>&1 || true
    if make -f /app/Makefile >/dev/null 2>&1; then
        p "make default build ok"
    else
        f "make default build failed"
        return 1
    fi
    if [ -x bin/serial ] && [ -x bin/pgen ]; then
        p "bin/serial and bin/pgen present"
    else
        f "missing bin/serial or bin/pgen"
        return 1
    fi
    ./bin/serial | grep -q SERIAL || f "serial output lacks SERIAL"
    ./bin/pgen   | grep -q PGEN   || f "pgen output lacks PGEN"
    if make -f /app/Makefile >/dev/null 2>&1; then p "make up-to-date no-op ok"; else f "make up-to-date failed"; fi
    make -f /app/Makefile clean >/dev/null 2>&1
    if make -f /app/Makefile -j2 >/dev/null 2>&1 && [ -x bin/serial ] && [ -x bin/pgen ]; then
        p "make -j2 rebuild ok"
    else
        f "make -j2 rebuild failed"
    fi
}

reset_work(){
    rm -rf /app/logs /app/out /app/stage
    mkdir -p /app/logs /app/out /app/stage
}
seed_case(){  # $1 = hidden case dir
    reset_work
    if [ -d "$1/logs" ]; then cp -a "$1/logs/." /app/logs/; fi
    if [ -d "$1/stage-in" ]; then cp -a "$1/stage-in/." /app/stage/; fi
    if [ -d "$1/out_seed" ]; then mkdir -p /app/out; cp -a "$1/out_seed/." /app/out/; fi
}

# ---------- 2. visible run (shipped /app fixtures as-is) --------------------
if bash /app/fix.sh; then p "visible fix exit 0"; else f "visible fix exit 0"; fi
if [ -s /app/out/summary/severity_counts.txt ]; then p "summary non-empty"; else f "summary non-empty"; fi
check_summary /app/logs
[ -d /app/out/records ] && p "out/records created" || f "out/records created"
stage_clean

# visible idempotency
cp /app/out/summary/severity_counts.txt /tmp/s1
if bash /app/fix.sh; then p "visible rerun exit 0"; else f "visible rerun exit 0"; fi
cmp -s /tmp/s1 /app/out/summary/severity_counts.txt && p "visible rerun identical" || f "visible rerun identical"

check_make

# ---------- 3. hidden cases ------------------------------------------------
for case_dir in /tests/hidden/*/; do
    case_dir=${case_dir%/}
    [ -d "$case_dir" ] || continue
    name=$(basename "$case_dir")
    case "$name" in
        h_severity|h_empty)
            seed_case "$case_dir"
            bash /app/fix.sh || f "$name fix exit 0"
            python3 /tests/severity_ref.py /app/logs > /tmp/exp
            cmp -s /tmp/exp "$case_dir/expected/severity.txt" \
                && p "$name stored-expected self-check" \
                || f "$name stored-expected stale"
            cmp -s /tmp/exp /app/out/summary/severity_counts.txt \
                && p "$name severity counts" \
                || f "$name severity counts"
            ;;
        h_clean)
            seed_case "$case_dir"
            bash /app/fix.sh || f "h_clean fix exit 0"
            ( cd /app/stage && find . -type f | sed 's|^\./||' | LC_ALL=C sort ) > /tmp/remain
            sort "$case_dir/expected/files.txt" > /tmp/exp2
            if cmp -s /tmp/exp2 /tmp/remain; then
                p "h_clean stage reduced to allowed set"
            else
                f "h_clean stage wrong set"
                echo "  expected:"; sed 's/^/    /' /tmp/exp2
                echo "  got:"; sed 's/^/    /' /tmp/remain
            fi
            ;;
        h_idem)
            seed_case "$case_dir"
            if bash /app/fix.sh; then p "h_idem run0 exit 0"; else f "h_idem run0 exit 0"; fi
            cp /app/out/summary/severity_counts.txt /tmp/i1
            grep -q 'sentinel urgently' /app/out/records/keep.txt \
                && p "h_idem sentinel survives first run" \
                || f "h_idem sentinel survives first run"
            if bash /app/fix.sh; then p "h_idem run1 exit 0"; else f "h_idem run1 exit 0"; fi
            cmp -s /tmp/i1 /app/out/summary/severity_counts.txt \
                && p "h_idem rerun identical" \
                || f "h_idem rerun identical"
            grep -q 'sentinel urgently' /app/out/records/keep.txt \
                && p "h_idem sentinel survives second run" \
                || f "h_idem sentinel survives second run"
            ;;
        *) f "unknown hidden case dir: $name" ;;
    esac
done

if [ "$fail_count" -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
echo "willow-upland verifier reward=$reward (fail_count=$fail_count)" >&2
exit 0