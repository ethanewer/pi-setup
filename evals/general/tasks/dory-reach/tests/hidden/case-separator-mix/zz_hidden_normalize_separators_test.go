// Hidden case: separator-heavy PEP 621 dependency names (mixed `.`/`_` runs
// and runs longer than one character), constraint spacing variants, and an
// already-normalized name that must pass through unchanged.
//
// Same code path as the upstream regression test, different inputs:
// "Psycopg2_binary>=2.9" (single underscore run, capitals), "Pillow" (bare
// name, no constraint), "ruamel_yaml.clib (>=0.2)" (adjacent `_` and `.`
// runs around a mixed-case interior), "imageio-ffmpeg==0.4" (already
// normalized) and "six" (bare, normalized). The parsed dependency set must
// contain the normalized spellings only, and the already-normalized names
// must be unchanged.
package pyproject_test

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/aquasecurity/trivy/pkg/dependency/parser/python/pyproject"
	"github.com/aquasecurity/trivy/pkg/set"
)

func TestHiddenNormalizeSeparators(t *testing.T) {
	tests := []struct {
		name string
		file string
		want set.Set[string]
	}{
		{
			name: "separator runs and spacing variants normalize; plain names unchanged",
			file: "testdata/hidden_sep.toml",
			want: set.New[string]("imageio-ffmpeg", "pillow", "psycopg2-binary", "ruamel-yaml-clib", "six"),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f, err := os.Open(tt.file)
			require.NoError(t, err)
			defer f.Close()

			p := &pyproject.Parser{}
			got, err := p.Parse(f)
			require.NoError(t, err)

			assert.Equal(t, tt.want, got.Project.Dependencies.Set)
		})
	}
}