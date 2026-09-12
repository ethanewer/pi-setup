// Hidden case C for cistern-flint.
// A deliberately empty regex string must survive a YAML round-trip.  Before
// the fix the regexp marshaller dropped any regex whose source string was
// empty, so `regex: ""` vanished and the rule silently used "(.*)" after a
// reload -- a different matching rule even though the configuration file had
// not changed.
package relabel

import (
	"testing"

	"go.yaml.in/yaml/v2"
	"github.com/stretchr/testify/require"
)

func TestHidden_EmptyRegex_YAMLRoundtrip(t *testing.T) {
	t.Run("empty regex only", func(t *testing.T) {
		var cfg Config
		input := `source_labels: [a, b]
separator: ;
regex: ""
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
	t.Run("empty regex survives a reload", func(t *testing.T) {
		var cfg Config
		err := yaml.Unmarshal([]byte("source_labels: [a]\nregex: \"\"\ntarget_label: t\nreplacement: $1\naction: replace\n"), &cfg)
		require.NoError(t, err)
		out, err := yaml.Marshal(&cfg)
		require.NoError(t, err)
		var cfg2 Config
		err = yaml.Unmarshal(out, &cfg2)
		require.NoError(t, err)
		require.Equal(t, "", cfg2.Regex.String())
		out2, err := yaml.Marshal(&cfg2)
		require.NoError(t, err)
		require.Equal(t, string(out), string(out2))
	})
}