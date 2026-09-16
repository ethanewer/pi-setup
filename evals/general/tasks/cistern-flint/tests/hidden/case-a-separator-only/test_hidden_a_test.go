// Hidden case A for cistern-flint.
// The relabel configuration marshal must not drop an explicit empty separator,
// even when it is the ONLY empty value in the rule (real regex, real
// replacement, real target label).  Before the fix, `separator: ""` was
// treated as "unset" and omitted, so a reload silently fell back to the ";"
// default.
package relabel

import (
	"testing"

	"go.yaml.in/yaml/v2"
	"github.com/stretchr/testify/require"
)

func TestHidden_EmptySeparatorOnly_YAMLRoundtrip(t *testing.T) {
	t.Run("empty separator only", func(t *testing.T) {
		var cfg Config
		input := `source_labels: [a, b]
separator: ""
regex: (.*)
target_label: t
replacement: $1
action: replace
`
		err := yaml.Unmarshal([]byte(input), &cfg)
		require.NoError(t, err)
		out, err := yaml.Marshal(&cfg)
		require.NoError(t, err)
		require.Equal(t, input, string(out))
	})
	t.Run("empty separator survives a reload", func(t *testing.T) {
		var cfg Config
		err := yaml.Unmarshal([]byte("source_labels: [a]\nseparator: \"\"\ntarget_label: t\nreplacement: $1\naction: replace\n"), &cfg)
		require.NoError(t, err)
		out, err := yaml.Marshal(&cfg)
		require.NoError(t, err)
		var cfg2 Config
		err = yaml.Unmarshal(out, &cfg2)
		require.NoError(t, err)
		require.Equal(t, "", cfg2.Separator)
		out2, err := yaml.Marshal(&cfg2)
		require.NoError(t, err)
		require.Equal(t, string(out), string(out2))
	})
}