package pnpm

import (
	"os"
	"sort"
	"testing"

	"github.com/stretchr/testify/require"

	ftypes "github.com/aquasecurity/trivy/pkg/fanal/types"
)

func TestHiddenThreeDocuments(t *testing.T) {
	f, err := os.Open("testdata/hidden_three_documents.yaml")
	require.NoError(t, err)

	got, deps, err := NewParser().Parse(t.Context(), f)
	require.NoError(t, err)

	// Two stacked environment documents come before the project document;
	// both must be skipped, and only the project's dependency reported.
	want := []ftypes.Package{
		{
			ID:           "is-negative@2.0.0",
			Name:         "is-negative",
			Version:      "2.0.0",
			Relationship: ftypes.RelationshipDirect,
		},
	}

	sort.Sort(ftypes.Packages(got))
	sort.Sort(ftypes.Packages(want))
	require.Equal(t, want, got)
	if deps != nil {
		require.Len(t, deps, 0)
	}
}