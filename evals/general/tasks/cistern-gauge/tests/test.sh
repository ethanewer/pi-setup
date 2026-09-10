#!/bin/bash
# Verifier for cistern-gauge.
#
# Graded deliverable: the reactor working tree at /app after the agent
# implements the median-baseline behaviour change. The verifier
#   1. drops the hidden JUnit 5 fixtures into cistern-core and cistern-report,
#   2. runs the whole reactor with `mvn -o -q -B -f /app/pom.xml clean verify`
#      (offline, warmed cache),
#   3. checks that no module's public API was deleted (javap baseline vs the
#      pristine reactor surface in /tests/api-baseline.json),
#   4. checks the repository still holds its git history and its size.
# Writes 1 to /logs/verifier/reward.txt only when every gate passes.
#
# Guarantee a reward on every exit path: without this an unexpected failure
# writes nothing and the record cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

failures=()

echo "=== cistern-gauge verifier ==="

# ---- 0) structural guards -------------------------------------------------
if [ ! -f /app/pom.xml ]; then
    failures+=("missing deliverable /app/pom.xml")
fi
if [ ! -d /app/.git ]; then
    failures+=("missing git repository at /app")
fi
if [ ! -r /app/pom.xml ] || ! grep -q "cistern-reactor" /app/pom.xml; then
    failures+=("/app/pom.xml is not the cistern reactor build file")
fi
for module in cistern-model cistern-core cistern-report cistern-cli; do
    if [ ! -f "/app/$module/pom.xml" ]; then
        failures+=("missing module $module")
    fi
done

# ---- 1) drop hidden tests ------------------------------------------------
hidden=/tests/hidden
if [ ! -d "$hidden" ]; then
    failures+=("/tests/hidden missing")
fi
cases=$(find "$hidden" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
if [ -z "$cases" ]; then
    failures+=("no hidden cases found")
fi
for case in $cases; do
    name=$(basename "$case")
    if [ ! -d "$case/core" ] || [ ! -d "$case/report" ]; then
        failures+=("hidden case $name lacks core/ and report/ fixtures")
        continue
    fi
    cp -r "$case/core/." /app/cistern-core/
    cp -r "$case/report/." /app/cistern-report/
    echo "  dropped hidden tests from $name"
done

# ---- 2) reactor verify (offline) ------------------------------------------
mvn_pass=1
mvn_log=/tmp/cistern-mvn.log
if ! mvn -o -q -B -f /app/pom.xml clean verify >"$mvn_log" 2>&1; then
    mvn_pass=0
    failures+=("reactor verify failed (offline mvn clean verify exited non-zero)")
    echo "--- mvn tail (last 40 lines) ---"
    tail -40 "$mvn_log"
    echo "--- surefire failure summaries (if any) ---"
    for report in /app/*/target/surefire-reports/*.txt; do
        [ -f "$report" ] || continue
        if grep -q "FAILURE\|ERROR" "$report" 2>/dev/null; then
            echo "== $report =="
            grep -E "Tests run|FAILURE|ERROR|<<<" "$report" | head -20
        fi
    done
fi

# ---- 2b) proof the grading and shipped tests actually ran and passed -----
# A green `mvn verify` exit code is necessary but not sufficient: skews like
# surefire <skipTests>, an <includes>/<excludes> list that hides the hidden
# classes, or -Dmaven.test.failure.ignore would all exit green while grading
# nothing. Require (i) the surefire report of every hidden class to exist and
# show zero failures, (ii) no failing report anywhere in the reactor, and
# (iii) the shipped baseline test to have been updated rather than deleted.
if [ "$mvn_pass" = 1 ]; then
    for cls in \
        com.cistern.core.CisternMedianBasicsTest \
        com.cistern.core.CisternMedianEdgeTest \
        com.cistern.report.CisternReportContractTest \
        com.cistern.report.CisternReportEdgesTest \
    ; do
        rpt=$(find /app/cistern-*/target/surefire-reports -maxdepth 1 -name "$cls.txt" 2>/dev/null | head -1)
        if [ -z "$rpt" ]; then
            failures+=("hidden test class $cls did not run (no surefire report; the build may be skipping tests)")
        elif ! grep -Eq "Tests run: [0-9]+, Failures: 0, Errors: 0" "$rpt"; then
            failures+=("hidden test class $cls did not pass: $(grep -E 'Tests run' "$rpt" | head -1)")
        else
            echo "  hidden $cls ran and passed"
        fi
    done
    for report in /app/cistern-*/target/surefire-reports/*.txt; do
        [ -f "$report" ] || continue
        summary=$(grep -E "^Tests run:" "$report" | head -1)
        if [ -n "$summary" ] && ! printf '%s' "$summary" | grep -Eq "Failures: 0, Errors: 0"; then
            failures+=("surefire report shows failures: $(basename "$report") :: $summary")
        fi
    done
    if [ ! -f /app/cistern-core/src/test/java/com/cistern/core/BaselineAssessorTest.java ]; then
        failures+=("shipped BaselineAssessorTest.java was deleted; the stale test must be updated, not removed")
    fi
fi

# ---- 3) public API survival (javap vs pristine baseline) -------------------
# Only meaningful when the reactor actually built its classes.
if [ "$mvn_pass" = 0 ]; then
    echo "(api surface check skipped: reactor build failed, no fresh classes)"
elif ! python3 /tests/api_check.py /app /tests/api-baseline.json > /tmp/api-check.out 2>&1; then
    failures+=("public API deletions detected:")
    sed 's/^/    | /' /tmp/api-check.out
fi

# ---- 4) repository integrity: history and size ----------------------------
commits=$(git -C /app rev-list --count HEAD 2>/dev/null)
if [ -z "$commits" ] || [ "$commits" -lt 12 ]; then
    failures+=("git history missing or too short (commits=$commits)")
fi
java_lines=$(find /app/cistern-* -name '*.java' -not -path '*/target/*' -print0 2>/dev/null | xargs -0 cat | wc -l)
if [ "$java_lines" -lt 4000 ]; then
    failures+=("reactor shrank below 4000 lines of Java (found $java_lines)")
fi

# ---- verdict ----------------------------------------------------------------
if [ "${#failures[@]}" -gt 0 ]; then
    echo
    echo "FAILURES:"
    for f in "${failures[@]}"; do
        echo "  - $f"
    done
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
echo
echo "ALL PASS (commits=$commits java_lines=$java_lines)"
echo "1" > /logs/verifier/reward.txt
exit 0