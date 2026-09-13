package core_deps

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	ftypes "github.com/aquasecurity/trivy/pkg/fanal/types"
)

// Hidden generalization case 1: a four-library .NET workspace whose
// application project (Frontend) is listed LAST in `libraries`, with a
// two-level helper chain (Frontend -> Reporting -> Common). The root must be
// the project no other library references; every project must be reported
// with matching relationships.
func TestHiddenRotate(t *testing.T) {
	f, err := os.Open("testdata/hidden-rotate.deps.json")
	require.NoError(t, err)
	got, gotDeps, err := NewParser().Parse(t.Context(), f)
	require.NoError(t, err)

	assert.Equal(t, 4, len(got))
	for _, pkg := range got {
		if pkg.ID == "Frontend/3.1.0" {
			assert.Equal(t, ftypes.RelationshipRoot, pkg.Relationship)
		} else if pkg.ID == "Reporting/2.0.0" || pkg.ID == "Common/1.2.0" {
			assert.Equal(t, ftypes.RelationshipWorkspace, pkg.Relationship)
		} else {
			assert.Equal(t, ftypes.RelationshipDirect, pkg.Relationship)
		}
	}
	assert.Equal(t, []ftypes.Dependency{
		{
			ID:        "Frontend/3.1.0",
			DependsOn: []string{"JsonHelper/2.0.0", "Reporting/2.0.0"},
		},
		{
			ID:        "Reporting/2.0.0",
			DependsOn: []string{"Common/1.2.0"},
		},
	}, gotDeps)
}