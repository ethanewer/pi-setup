package core_deps

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	ftypes "github.com/aquasecurity/trivy/pkg/fanal/types"
)

// Hidden generalization case 2: two projects that reference each other
// (cycle). NO project is unreferenced, so the graph does not identify a
// single root and the parser must NOT guess: every library is still
// reported, but no package may carry a Root/Workspace relationship and the
// dependency edges still come from the targets graph.
func TestHiddenNoRoot(t *testing.T) {
	f, err := os.Open("testdata/hidden-noroot.deps.json")
	require.NoError(t, err)
	got, gotDeps, err := NewParser().Parse(t.Context(), f)
	require.NoError(t, err)

	assert.Equal(t, 3, len(got))
	for _, pkg := range got {
		assert.Equal(t, ftypes.RelationshipUnknown, pkg.Relationship)
	}
	assert.Equal(t, []ftypes.Dependency{
		{
			ID:        "Engine/1.0.0",
			DependsOn: []string{"Config/0.5.0", "Scheduler/1.0.0"},
		},
		{
			ID:        "Scheduler/1.0.0",
			DependsOn: []string{"Engine/1.0.0"},
		},
	}, gotDeps)
}