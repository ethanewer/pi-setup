// Hidden case: operator-only dependency entries interspersed between real
// packages.
//
// Same code path as the upstream regression test (an environment.yml whose
// dependencies list contains entries made up only of version operators, with
// no package name), different inputs: the meaningless entries appear both
// before and in the middle of the list, in runs of one, two and three "="
// characters, and real pinned packages (with both "=" and "==") must still be
// reported exactly, together with the file's prefix.
package environment_test

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/aquasecurity/trivy/pkg/dependency/parser/conda/environment"
	ftypes "github.com/aquasecurity/trivy/pkg/fanal/types"
)

func TestHiddenOperatorRun(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  environment.Packages
	}{
		{
			name:  "operator-only entries interspersed between pinned packages",
			input: "testdata/operator-run-dep.yaml",
			want: environment.Packages{
				Packages: []ftypes.Package{
					{
						Name:    "numpy",
						Version: "1.26.4",
						Locations: ftypes.Locations{
							{
								StartLine: 6,
								EndLine:   6,
							},
						},
					},
					{
						Name:    "zope.interface",
						Version: "6.2",
						Locations: ftypes.Locations{
							{
								StartLine: 8,
								EndLine:   8,
							},
						},
					},
				},
				Prefix: "/opt/conda/envs/test-env",
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f, err := os.Open(tt.input)
			require.NoError(t, err)
			defer f.Close()

			got, err := environment.NewParser().Parse(f)
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}