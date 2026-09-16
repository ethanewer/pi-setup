package pnpm

import (
	"os"
	"sort"
	"testing"

	"github.com/stretchr/testify/require"

	ftypes "github.com/aquasecurity/trivy/pkg/fanal/types"
)

func TestHiddenScopedMixed(t *testing.T) {
	f, err := os.Open("testdata/hidden_scoped_mixed.yaml")
	require.NoError(t, err)

	got, deps, err := NewParser().Parse(t.Context(), f)
	require.NoError(t, err)

	// The project document declares one production dependency (scoped) and
	// one dev dependency; the package manager's own environment
	// (pnpm, @pnpm/*) must not appear.
	want := []ftypes.Package{
		{
			ID:           "@corp/widget@3.1.0",
			Name:         "@corp/widget",
			Version:      "3.1.0",
			Relationship: ftypes.RelationshipDirect,
		},
		{
			ID:           "lint-checks@0.9.4",
			Name:         "lint-checks",
			Version:      "0.9.4",
			Relationship: ftypes.RelationshipDirect,
			Dev:          true,
		},
	}

	sort.Sort(ftypes.Packages(got))
	sort.Sort(ftypes.Packages(want))
	require.Equal(t, want, got)
	if deps != nil {
		require.Len(t, deps, 0)
	}
}