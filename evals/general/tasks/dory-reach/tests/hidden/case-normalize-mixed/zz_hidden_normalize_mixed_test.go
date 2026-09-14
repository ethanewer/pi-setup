// Hidden case: PEP 621 dependency names needing BOTH case and separator
// normalization, with extras, operators and version pins the upstream
// regression test does not use.
//
// Same code path as the upstream regression (the `[project].dependencies`
// list form of the pyproject parser), different inputs: a capitalised name
// ("Django"), a name with a run of mixed separators ("My.Pkg_One"), extras
// plus a constraint ("FastAPI[all]>=0.100") and a plain dotted name
// ("zope.Interface"). The parsed dependency set must contain the normalized
// spellings only.
package pyproject_test

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/aquasecurity/trivy/pkg/dependency/parser/python/pyproject"
	"github.com/aquasecurity/trivy/pkg/set"
)

func TestHiddenNormalizeMixed(t *testing.T) {
	tests := []struct {
		name string
		file string
		want set.Set[string]
	}{
		{
			name: "case and separators normalize together with extras and constraints",
			file: "testdata/hidden_mixed.toml",
			want: set.New[string]("django", "fastapi", "my-pkg-one", "zope-interface"),
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