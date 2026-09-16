#!/bin/bash
# repro.sh (oracle) for shroud-bulkhead: reproduces the pnpm multi-document
# lockfile misreport by driving the repository's own pnpm lockfile module
# tests against a scratch copy of the tree plus the fixture
# /app/repro-fixture.yaml (a two-document pnpm 11 lockfile: the package
# manager's own environment first, the project's dependencies second).
#
# Usage: /app/repro.sh [REPO]
#   REPO   root of a checkout of the trivy tree (default /app/src)
#
# Exits 0 iff the module parses the fixture correctly: exactly the project's
# declared dependency ("left-pad@2.3.1") is reported and no package-manager
# component is. Any other outcome exits nonzero.
set -u

REPO="${1:-/app/src}"
FIXTURE=/app/repro-fixture.yaml
export PATH=/opt/go/bin:$PATH
export CGO_ENABLED=0 GOEXPERIMENT=jsonv2 GOMAXPROCS=1

SCRATCH="$(mktemp -d /tmp/repro.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

# 1. scratch copy of the tree - never modify REPO itself
cp -a "$REPO/." "$SCRATCH/"

# 2. inject our fixture and a small module test into the scratch copy
P="$SCRATCH/pkg/dependency/parser/nodejs/pnpm"
cp "$FIXTURE" "$P/testdata/repro_fixture.yaml"

cat > "$P/repro_verify_test.go" <<'GOTEOF'
package pnpm

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"

	ftypes "github.com/aquasecurity/trivy/pkg/fanal/types"
)

func TestReproMultiDocument(t *testing.T) {
	f, err := os.Open("testdata/repro_fixture.yaml")
	require.NoError(t, err)

	got, _, err := NewParser().Parse(t.Context(), f)
	require.NoError(t, err)

	// The project document declares exactly one dependency (left-pad 2.3.1).
	// The package manager's own environment (pnpm, @pnpm/*, @reflink/*,
	// detect-libc) must not be reported as project dependencies.
	require.Len(t, got, 1)
	require.Equal(t, "left-pad", got[0].Name)
	require.Equal(t, "2.3.1", got[0].Version)
	require.Equal(t, ftypes.RelationshipDirect, got[0].Relationship)
}
GOTEOF

# 3. run the module's own test harness, restricted to our test
cd "$SCRATCH"
go test -v -short -run 'TestReproMultiDocument' ./pkg/dependency/parser/nodejs/pnpm/...