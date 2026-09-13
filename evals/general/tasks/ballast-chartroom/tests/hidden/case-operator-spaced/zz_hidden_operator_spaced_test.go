// Hidden case: operator-only dependency entries in longer runs and with
// whitespace, which the upstream regression test does not use.
//
// Same parser path, different shapes of the meaningless entry: a four-"="
// run, two "=" separated by a space, an entry that is a space then "=" then a
// space, and real pinned packages around them. After the operators are
// replaced each of these entries leaves nothing behind (or only whitespace),
// so the parser must skip them rather than index into an empty field list.
package environment_test

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/aquasecurity/trivy/pkg/dependency/parser/conda/environment"
	ftypes "github.com/aquasecurity/trivy/pkg/fanal/types"
)

func TestHiddenOperatorSpaced(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  environment.Packages
	}{
		{
			name:  "long and spaced operator-only entries leave real packages intact",
			input: "testdata/operator-spaced-dep.yaml",
			want: environment.Packages{
				Packages: []ftypes.Package{
					{
						Name:    "pandoc",
						Version: "3.1.9",
						Locations: ftypes.Locations{
							{
								StartLine: 7,
								EndLine:   7,
							},
						},
					},
					{
						Name:    "scipy",
						Version: "1.12.0",
						Locations: ftypes.Locations{
							{
								StartLine: 9,
								EndLine:   9,
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