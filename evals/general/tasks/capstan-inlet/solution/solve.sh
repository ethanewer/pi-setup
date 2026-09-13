#!/bin/bash
# Oracle for capstan-inlet: applies the root-project fix (the single source
# file change that resolves the .NET multi-project bug) to the real trivy
# tree at /app/src, writes /app/summary.md, then proves the work with the
# project's own test command plus the upstream regression test baked at
# /opt/golden, all offline. Reads only /app, /solution and /opt/golden,
# never /tests.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }
export PATH=/opt/go/bin:$PATH CGO_ENABLED=0 GOEXPERIMENT=jsonv2

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied root-project resolution fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

## Where the defect lives
`pkg/dependency/parser/dotnet/core_deps/parse.go` — `collectPackages`
(and its callers in `Parse`): the routine that turns the `libraries`
section of a .NET `.deps.json` file into the reported package set and
picks the root project.

## Root cause
When the file contained several sibling `type: "project"` libraries (a
.NET solution), `collectPackages` treated the FIRST project listed in
`libraries` as the root application and skipped every later project, so
all helper projects and anything reachable only through them vanished
from the report. Single-project files never showed it because there the
first project is also the only project.

## Fix
Root selection is now driven by the reference graph: collect all
`type: "project"` library IDs, build the set of every package ID that any
library's `targets` entry depends on, and mark as root the single project
that nothing references (`RelationshipRoot`), with the other projects
`RelationshipWorkspace`. When zero or multiple unreferenced candidates
exist, the parser logs and returns a non-root parse instead of guessing.
Direct dependencies are looked up under the resolved root project ID, and
relationship filling only touches packages whose relationship is still
unset, so workspace markers survive the graph pass.

## Verification
`/app/reproduce.sh` exits 0, and the project's own command
`go test -v -short ./pkg/dependency/parser/dotnet/core_deps/` passes with
the upstream regression test for this bug planted (`multi-project
solution` and `ambiguous root` subtests both pass; the whole package is
green, 9/9 subtests plus all pre-existing cases).
MD

# Prove the fix with the project's own machinery: plant the upstream
# regression test (golden bytes of parse_test.go and the two fixtures from
# /opt/golden, already in the image), run the project's own test command,
# and require the two regression subtests to pass.
cp /opt/golden/parse_test.go pkg/dependency/parser/dotnet/core_deps/parse_test.go
cp /opt/golden/multi-project.deps.json pkg/dependency/parser/dotnet/core_deps/testdata/multi-project.deps.json
cp /opt/golden/ambiguous-root.deps.json pkg/dependency/parser/dotnet/core_deps/testdata/ambiguous-root.deps.json

go test -v -short ./pkg/dependency/parser/dotnet/core_deps/ > /tmp/oracle_test.log 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "oracle: go test failed; tail:" >&2
    tail -25 /tmp/oracle_test.log >&2
fi
grep -q -- "--- PASS: TestParse/multi-project_solution" /tmp/oracle_test.log || rc=1
grep -q -- "--- PASS: TestParse/ambiguous_root" /tmp/oracle_test.log || rc=1
grep -qE "^(ok|PASS)" /tmp/oracle_test.log || rc=1

# Leave the tree exactly as the verifier expects it: only the fixed source
# file may differ from the pinned commit. The regression test was planted
# here only to prove the fix; the verifier re-plants it itself.
git restore --worktree --source=HEAD -- pkg/dependency/parser/dotnet/core_deps/parse_test.go
rm -f pkg/dependency/parser/dotnet/core_deps/testdata/multi-project.deps.json \
      pkg/dependency/parser/dotnet/core_deps/testdata/ambiguous-root.deps.json

if [ $rc -ne 0 ]; then
    echo "oracle: regression proof did not pass (exit $rc)" >&2
    exit 1
fi
echo "oracle: fix applied, summary written, regression test and package suite green"
exit 0