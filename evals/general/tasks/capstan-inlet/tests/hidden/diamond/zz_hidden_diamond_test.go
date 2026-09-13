package core_deps

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	ftypes "github.com/aquasecurity/trivy/pkg/fanal/types"
)

// Hidden generalization case 3: the root application is listed SECOND (not
// first, not last), a workspace project LibA that the root depends on, and a
// third-party package reachable both directly (from the root) and
// transitively. The root must still be identified from the reference graph,
// the workspace member must keep RelationshipWorkspace even though it is a
// direct dependency of the root, and the shared package must be Direct for
// the root's own dependency list.
func TestHiddenDiamond(t *testing.T) {
	f, err := os.Open("testdata/hidden-diamond.deps.json")
	require.NoError(t, err)
	got, gotDeps, err := NewParser().Parse(t.Context(), f)
	require.NoError(t, err)

	assert.Equal(t, 3, len(got))
	for _, pkg := range got {
		if pkg.ID == "App/4.0.0" {
			assert.Equal(t, ftypes.RelationshipRoot, pkg.Relationship)
		} else if pkg.ID == "LibA/1.0.0" {
			assert.Equal(t, ftypes.RelationshipWorkspace, pkg.Relationship)
		} else {
			assert.Equal(t, ftypes.RelationshipDirect, pkg.Relationship)
		}
	}
	assert.Equal(t, []ftypes.Dependency{
		{
			ID:        "App/4.0.0",
			DependsOn: []string{"Jackson.Core/2.18.2", "LibA/1.0.0"},
		},
		{
			ID:        "LibA/1.0.0",
			DependsOn: []string{"Jackson.Core/2.18.2"},
		},
	}, gotDeps)
}