#!/usr/bin/env bash
# willow-wharf verifier entrypoint. Every deliverable under /app is executed
# directly here (or by a helper in this directory that is invoked from here)
# and, for the generalizing deliverables, against the hidden inputs in
# /tests/hidden. Ends by writing 1 or 0 to /logs/verifier/reward.txt.
set -uo pipefail

mkdir -p /logs/verifier
failures=0

chk() { # chk <name> <ok(0)=pass>
    if [ "$2" = "0" ]; then
        echo "  [ok]   $1"
    else
        echo "  [FAIL] $1"
        failures=$((failures + 1))
    fi
}
have() { [ -e "$1" ] && echo 0 || echo 1; }

# =====================================================================
# 1. Coq proof: /app/proof.v, /app/proof-check.log
# =====================================================================
rm -rf /tmp/cq && mkdir -p /tmp/cq
if [ -f /app/proof.v ]; then
    cp /app/proof.v /tmp/cq/
    cd /tmp/cq
    coqc proof.v > /tmp/cq/coqc_out.log 2>&1
    chk "coqc compiles /app/proof.v" "$?"
    chk "proof.vo is produced" "$(have /tmp/cq/proof.vo)"
    # must contain no admission keywords
    if grep -Eq '\bAdmitted\b|\ba[d]+[m][i][t]\b|\bOops\b' /app/proof.v; then
        chk "no admitted obligations in source" 1
    else
        chk "no admitted obligations in source" 0
    fi
    # must terminate with a closing proof command
    if grep -Eq 'Qed\.|Defined\.' /app/proof.v; then
        chk "proof ends with closing command" 0
    else
        chk "proof ends with closing command" 1
    fi
    # dependent files use the compiled module
    vdeps=$(ls /tests/hidden/proof_dep_*.v 2>/dev/null | wc -l)
    if [ "$vdeps" -gt 0 ]; then
        ok=0
        for dep in /tests/hidden/proof_dep_*.v; do
            b=$(basename "$dep" .v)
            cp "$dep" /tmp/cq/
            if coqc -Q /tmp/cq "" "$b.v" >/tmp/cq/"$b".log 2>&1; then
                ok=$((ok + 1))
            else
                echo "      dep $b failed"
            fi
            rm -f "/tmp/cq/$b.v"
        done
        chk "hidden coq dependents compile" "$([ "$ok" = "$vdeps" ] && echo 0 || echo 1)"
    fi
else
    chk "coqc compiles /app/proof.v" 1
fi
# proof-check.log deliverable (any size: a clean coqc emits no output)
chk "/app/proof-check.log present" "$(have /app/proof-check.log)"

# =====================================================================
# 2. sympy integral: /app/integral.py, /app/integral.txt + hidden re-runs
# =====================================================================
cd /app
chk "/app/integral.py present" "$(have /app/integral.py)"
chk "/app/integral.txt present" "$(have /app/integral.txt)"
if python3 /tests/verifier_int.py >/tmp/int_out.log 2>&1; then
    chk "integral hidden cases pass" 0
else
    chk "integral hidden cases pass" 1
    cat /tmp/int_out.log
fi

# =====================================================================
# 3. R sampler: /app/sampler.R, /app/selftest.log + hidden sampler cases
# =====================================================================
chk "/app/sampler.R present" "$(have /app/sampler.R)"
if python3 /tests/verifier_r.py >/tmp/r_out.log 2>&1; then
    chk "R sampler hidden cases pass" 0
else
    chk "R sampler hidden cases pass" 1
    cat /tmp/r_out.log
fi

# =====================================================================
# 4. LaTeX report: /app/report.tex, .pdf, pdflatex.log
# =====================================================================
chk "/app/report.tex present" "$(have /app/report.tex)"
chk "/app/report.pdf present" "$(have /app/report.pdf)"
chk "/app/pdflatex.log present" "$(have /app/pdflatex.log)"
if [ -f /app/report.tex ]; then
    rm -rf /tmp/pd && mkdir -p /tmp/pd
    cp /app/report.tex /tmp/pd/
    cd /tmp/pd
    pdflatex -interaction=nonstopmode -halt-on-error report.tex >/tmp/pd/out.log 2>&1
    chk "pdflatex builds report.pdf fresh" "$(have /tmp/pd/report.pdf)"
    if grep -q 'Overfull \\hbox' /tmp/pd/report.log 2>/dev/null; then
        chk "fresh build has no over-full hbox warnings" 1
    else
        chk "fresh build has no overfull hbox warnings" 0
    fi
    # protection: over-wide unbreakable token must be absent
    if grep -q 'electrohydrodynamicelectrohydrodynamicelectrohydrodynamicelectrohydrodynamicelectrohydrodynamic' /app/report.tex; then
        chk "over-wide token is not used" 1
    else
        chk "over-wide token is not used" 0
    fi
    # protection: no \texttt{...} longer than 24 characters
    if grep -EqE '\\texttt\{[^}]{25,}\}' /app/report.tex; then
        chk "no long monospaced token" 1
    else
        chk "no long monospaced token" 0
    fi
    # /app/pdflatex.log must itself be warning-free
    if grep -q 'Overfull \hbox' /app/pdflatex.log 2>/dev/null; then
        chk "shipped pdflatex.log warning-free" 1
    else
        chk "shipped pdflatex.log warning-free" 0
    fi
fi

# =====================================================================
echo "=== willow-wharf verifier failures=$failures ==="
reward=0; [ "$failures" -eq 0 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"
exit 0