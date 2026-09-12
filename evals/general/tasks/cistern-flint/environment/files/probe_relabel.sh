#!/bin/bash
# Reproduction probe for cistern-flint.
#
# Installs a focused probe test into the model/relabel package, runs it with
# the project's own test runner, and restores the package's own test file
# afterwards. Fails (and prints the offending diff) on the buggy checkout.
set -u
SRC=/app/src
GO=/opt/go/bin/go
TEST_FILE="$SRC/model/relabel/relabel_test.go"
BAK="/tmp/probe_relabel_test.go.bak"

cp "$TEST_FILE" "$BAK"
cp /app/probe_relabel_test.go "$TEST_FILE"
trap 'cp "$BAK" "$TEST_FILE"; rm -f "$BAK"' EXIT

cd "$SRC" || exit 2
"$GO" test -v ./model/relabel -run TestProbe_EmptySeparatorAndReplacementRoundtrip