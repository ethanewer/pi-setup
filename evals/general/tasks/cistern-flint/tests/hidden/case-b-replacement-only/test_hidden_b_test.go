// Hidden case B for cistern-flint.
// An explicit empty regex replacement must survive a YAML round-trip even when
// the separator and regex are the defaults/non-empty.  Before the fix,
// `replacement: ""` was omitted on re-serialization and the rule silently fell
// back to the "$1" default after a reload.
package relabel

import (
	"testing"

	"go.yaml.in/yaml/v2"
	"github.com/stretchr/testify/require"
)

func TestHidden_EmptyReplacementOnly_YAMLRoundtrip(t *testing.T) {
	t.Run("empty replacement only", func(t *testing.T) {
		var cfg Config
		input := `source_labels: [a, b]
separator: ;
target_label: t
replacement: ""
action: replace
`
		err := yaml.Unmarshal([]byte(input), &cfg)
		require.NoError(t, err)
		out, err := yaml.Marshal(&cfg)
		require.NoError(t, err)
		require.Equal(t, input, string(out))
	})
	t.Run("empty replacement survives a reload", func(t *testing.T) {
		var cfg Config
		err := yaml.Unmarshal([]byte("source_labels: [a]\ntarget_label: t\nreplacement: \"\"\naction: replace\n"), &cfg)
		require.NoError(t, err)
		out, err := yaml.Marshal(&cfg)
		require.NoError(t, err)
		var cfg2 Config
		err = yaml.Unmarshal(out, &cfg2)
		require.NoError(t, err)
		require.Equal(t, "", cfg2.Replacement)
		out2, err := yaml.Marshal(&cfg2)
		require.NoError(t, err)
		require.Equal(t, string(out), string(out2))
	})
}