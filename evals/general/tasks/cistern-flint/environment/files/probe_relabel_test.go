// Reproduction probe for cistern-flint.
//
// Round-trips a relabel rule that deliberately configures an empty separator
// and an empty regex replacement through YAML serialize/load. A correct
// checkout must re-serialize the identical YAML: the empty values are real,
// deliberate configuration and must not be replaced by the built-in defaults
// (";" separator, "$1" replacement, "(.*)" regex).
//
// This file is copied over model/relabel/relabel_test.go by
// /app/probe_relabel.sh (which restores the original afterwards), so it lives
// in the same package and can exercise the real production code.
package relabel

import (
	"testing"

	"go.yaml.in/yaml/v2"
	"github.com/stretchr/testify/require"
)

func TestProbe_EmptySeparatorAndReplacementRoundtrip(t *testing.T) {
	var cfg Config
	input := `source_labels: [namespace, k8s_app]
separator: ""
regex: ""
target_label: target_cluster
replacement: ""
action: replace
`
	err := yaml.Unmarshal([]byte(input), &cfg)
	require.NoError(t, err)

	out, err := yaml.Marshal(&cfg)
	require.NoError(t, err)
	require.Equal(t, input, string(out))
}