#!/bin/bash
# Build-time smoke for yaw-roadstead: proves the shipped image state both
# ways, in scratch copies that are deleted afterwards. /app/src itself is
# left pristine at the parent commit.
#
#   buggy direction:  pristine parent tree + the golden regression test
#                     extracted from the fix commit must FAIL
#   fix direction:    pristine parent tree + the upstream one-line fix +
#                     the golden regression test must PASS
set -e
export PATH=/opt/go/bin:$PATH

cp -a /app/src /tmp/smoke-bug
cp -a /app/src /tmp/smoke-fix

# --- buggy direction: golden test overlaid on the pristine tree must fail ---
cp /opt/golden/yaml_docs_test.go /tmp/smoke-bug/doc/yaml_docs_test.go
if ( cd /tmp/smoke-bug && go test -v ./... -run TestGenYamlDoc > /tmp/smoke-bug.log 2>&1 ); then
    echo "SMOKE-FAIL: buggy tree unexpectedly green"
    exit 1
fi
grep -q "^--- FAIL: TestGenYamlDoc " /tmp/smoke-bug.log || { echo "SMOKE-FAIL: wrong failure"; tail -5 /tmp/smoke-bug.log; exit 1; }

# --- fix direction: upstream one-line fix + golden test must pass -----------
sed -i 's/child.Name()+" - "+child.Short/child.CommandPath()+" - "+child.Short/' /tmp/smoke-fix/doc/yaml_docs.go
cp /opt/golden/yaml_docs_test.go /tmp/smoke-fix/doc/yaml_docs_test.go
if ! ( cd /tmp/smoke-fix && go test -v ./... -run TestGenYamlDoc > /tmp/smoke-fix.log 2>&1 ); then
    echo "SMOKE-FAIL: fixed tree did not pass"
    tail -5 /tmp/smoke-fix.log
    exit 1
fi
grep -q "^--- PASS: TestGenYamlDoc " /tmp/smoke-fix.log || { echo "SMOKE-FAIL: test did not run"; exit 1; }

rm -rf /tmp/smoke-bug /tmp/smoke-fix
echo "SMOKE-OK: buggy tree fails the golden regression test, fixed tree passes it"