// Oracle-authored reproduction for the dory-reach task: a PEP 621
// pyproject.toml dependency list spelled non-canonically must come out
// normalized (PEP 503: lowercase, runs of `.`/`_`/`-` collapsed to `-`).
// With the buggy parser (parent commit) this test FAILS with a testify
// "Not equal" assertion mismatch; with the fix applied it passes.
package pyproject_test

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/aquasecurity/trivy/pkg/dependency/parser/python/pyproject"
	"github.com/aquasecurity/trivy/pkg/set"
)

func TestReproNormalizedNames(t *testing.T) {
	tests := []struct {
		name string
		file string
		want set.Set[string]
	}{
		{
			name: "pep 621 list dependency names are normalized (case and separators)",
			file: "testdata/repro.toml",
			want: set.New[string]("check-wheel-contents", "flask", "ruamel-yaml", "typing-extensions"),
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