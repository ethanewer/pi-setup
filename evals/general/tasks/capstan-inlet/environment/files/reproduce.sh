#!/bin/bash
# Reproducer for the .NET multi-project workspace bug in trivy's core_deps
# parser. Self-cleaning: it temporarily drops an authored fixture and a
# scratch test into the real package, runs the project's own test command,
# and removes both again on exit (the graded tree must contain no scratch
# files, so the cleanup matters).
#
# Exit status: non-zero while the bug is present, zero once the tree is fixed.
set -u
cd /app/src || { echo "reproduce.sh: /app/src missing" >&2; exit 1; }

P=pkg/dependency/parser/dotnet/core_deps
FIXTURE=$P/testdata/repro-workspace.deps.json
SCRATCH=$P/zz_repro_test.go

cleanup() {
  rm -f "$FIXTURE" "$SCRATCH"
  git checkout -- "$P/parse_test.go" 2>/dev/null
}
trap cleanup EXIT

cp /app/repro/repro-workspace.deps.json "$FIXTURE"
cat > "$SCRATCH" <<'EOF'
package core_deps

import (
	"os"
	"sort"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Repro: a four-library .NET workspace (three sibling projects plus one
// third-party package) where the application project is NOT the first
// library in the file. Every library must be reported.
func TestReproWorkspace(t *testing.T) {
	f, err := os.Open("testdata/repro-workspace.deps.json")
	require.NoError(t, err)
	got, _, err := NewParser().Parse(t.Context(), f)
	require.NoError(t, err)

	var ids []string
	for _, pkg := range got {
		ids = append(ids, pkg.ID)
	}
	sort.Strings(ids)
	assert.Equal(t, 4, len(got))
	assert.Equal(t, []string{"Common/1.1.0", "JsonNeat/2.1.0", "Pay/1.1.0", "WebStore/3.0.0"}, ids)
}
EOF

export PATH=/opt/go/bin:$PATH CGO_ENABLED=0 GOEXPERIMENT=jsonv2
go test -v -short ./pkg/dependency/parser/dotnet/core_deps/