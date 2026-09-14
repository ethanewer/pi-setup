package pnpm

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestHiddenEnvOnly(t *testing.T) {
	f, err := os.Open("testdata/hidden_env_only.yaml")
	require.NoError(t, err)

	got, deps, err := NewParser().Parse(t.Context(), f)
	require.NoError(t, err)

	// A lockfile holding only the package manager's own environment document
	// declares nothing about the project: no packages may be reported.
	if got != nil {
		require.Len(t, got, 0)
	}
	if deps != nil {
		require.Len(t, deps, 0)
	}
}