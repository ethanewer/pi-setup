#!/bin/bash
# Verifier for nock-trestle (upstream-clone regression task on trinodb/trino).
#
# Requirements, in order:
#   1. /app/src exists and is a git checkout.
#   2. The agent's change is a real modification of the parser MAIN sources:
#      git status is non-empty, at least one path is under
#      core/trino-parser/src/main/, and nothing under src/test/ or any
#      pom.xml / build file changed (kills test-deletion and build-disable
#      cheats; a tree with no change at all also fails).
#   3. The full trino-parser module test suite passes offline (the module's
#      own test runner is the arbiter of correct behaviour).
#   4. Every hidden case under /tests/hidden/<case>/, copied into the module
#      test sources and run via the module's own surefire, passes.
#   5. The /app/fix-summary.md deliverable exists and diagnoses the interval
#      regression.
#
# Reward is binary and written on every exit path (the trap covers crashes).
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

SRC=/app/src
MODULE="$SRC/core/trino-parser"
RUNLOG=/tmp/nock-trestle-verify.log
failures=""

note_fail() {
    failures="$failures
- $1"
}

# ---- 1) the checkout exists ------------------------------------------------
if [ ! -d "$SRC" ]; then
    note_fail "/app/src is missing"
elif [ ! -d "$SRC/.git" ]; then
    note_fail "/app/src is not a git checkout"
fi

# ---- 2) the fix must be a modification of the parser main sources ----------
if [ -d "$SRC/.git" ]; then
    guard=$(python3 - "$SRC" <<'PY'
import subprocess
import sys

src = sys.argv[1]
out = subprocess.run(["git", "-C", src, "status", "--porcelain"],
                     capture_output=True, text=True).stdout
paths = []
for line in out.splitlines():
    line = line.rstrip()
    if not line:
        continue
    if line.startswith("R"):
        # "R  old -> new"; guard the new side only
        if " -> " in line:
            paths.append(line.split(" -> ", 1)[1])
    else:
        paths.append(line[3:])
main = [p for p in paths if p.strip().startswith("core/trino-parser/src/main/")]
bad = []
for p in paths:
    p = p.strip()
    if not p:
        continue
    if p.endswith("pom.xml") or ".mvn/" in p or p.startswith("."):
        bad.append(p)
    if "/src/test/" in p:
        bad.append(p)
if not paths:
    print("no-change")
    sys.exit(0)
if bad:
    print("forbidden:" + ",".join(bad))
    sys.exit(0)
if not main:
    print("no-main-change")
    sys.exit(0)
print("ok:" + ",".join(main))
PY
)
    case "$guard" in
        no-change)
            note_fail "no change to the checkout at all (git status is clean); the regression is still present"
            ;;
        no-main-change)
            note_fail "the only changes are not under core/trino-parser/src/main/; the verifier requires the fix in the parser main sources"
            ;;
        forbidden:*)
            note_fail "forbidden paths changed: ${guard#forbidden:}"
            ;;
        ok:*)
            : ;;
        *)
            note_fail "could not classify the git diff guard output: $guard"
            ;;
    esac
fi

# ---- 3) full module test suite, offline, via the project's own runner -------
mvn_phase() {
    # mvn_phase <extra args...> ; returns maven's exit code in $?
    ( cd "$SRC" && mvn -B -o -f core/trino-parser/pom.xml \
        -Dmaven.source.skip=true -Dair.check.skip-all=true -Dmaven.javadoc.skip=true \
        -Dsurefire.failIfNoSpecifiedTests=false "$@" ) > "$RUNLOG" 2>&1
}

mvn_phase test
rc=$?
if [ "$rc" -ne 0 ]; then
    note_fail "full trino-parser module test suite failed (rc=$rc):"
    note_fail "$(tail -40 "$RUNLOG")"
fi

# ---- 4) hidden cases --------------------------------------------------------
# Copy each hidden JUnit class into the module's test tree, then run each
# class through the module's own surefire. The git-diff guard above ran
# BEFORE this copy, so the agent's tree is not what is being judged here.
hidden_dir=/tests/hidden
if [ -d "$hidden_dir" ]; then
    cases=$(find "$hidden_dir" -mindepth 1 -maxdepth 1 -type d | sort)
    if [ -z "$cases" ]; then
        note_fail "no hidden case directories under $hidden_dir"
    fi
    for casedir in $cases; do
        copied=""
        for javafile in "$casedir"/*.java; do
            [ -f "$javafile" ] || continue
            cp "$javafile" "$MODULE/src/test/java/io/trino/sql/parser/"
            copied="$copied $(basename "$javafile")"
        done
        if [ -z "$copied" ]; then
            note_fail "hidden case '$casedir' has no JUnit class"
            continue
        fi
        for javafile in "$casedir"/*.java; do
            [ -f "$javafile" ] || continue
            cls=$(basename "$javafile" .java)
            mvn_phase -Dtest="$cls" test
            rc=$?
            if [ "$rc" -ne 0 ]; then
                note_fail "hidden case '$casedir' ($cls) FAILED (rc=$rc):"
                note_fail "$(tail -25 "$RUNLOG")"
            fi
        done
    done
else
    note_fail "missing hidden case tree $hidden_dir"
fi

# ---- 5) deliverable /app/fix-summary.md --------------------------------------
if [ ! -f /app/fix-summary.md ]; then
    note_fail "missing deliverable /app/fix-summary.md"
else
    text=$(cat /app/fix-summary.md 2>/dev/null || true)
    if [ "${#text}" -lt 200 ]; then
        note_fail "/app/fix-summary.md is too short to be a real diagnosis"
    fi
    low=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
    n=0
    for w in interval year month; do
        case "$low" in *"$w"*) n=$((n+1));; esac
    done
    if [ "$n" -lt 2 ]; then
        note_fail "/app/fix-summary.md does not diagnose the interval-unit regression (expected at least two of: interval / year / month)"
    fi
fi

# ---- verdict ----------------------------------------------------------------
echo "== nock-trestle verifier =="
if [ -n "$failures" ]; then
    echo "FAILURES:$failures" | sed 's/^/  /'
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
echo "all checks passed"
echo "1" > /logs/verifier/reward.txt
exit 0