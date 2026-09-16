// Hidden case D for cistern-flint.
// Functional check of the user-visible symptom from the bug report: a relabel
// rule that deliberately uses an empty separator and an empty replacement must
// behave identically before and after a config serialize/reload cycle.  Before
// the fix the reloaded rule silently fell back to the built-in defaults (";"
// separator, "$1" replacement), so the same rule rewrote label names
// differently even though the configuration had not changed.
package relabel

import (
	"testing"

	"github.com/prometheus/common/model"
	"go.yaml.in/yaml/v2"
	"github.com/stretchr/testify/require"

	"github.com/prometheus/prometheus/model/labels"
	"github.com/prometheus/prometheus/util/testutil"
)

func TestHidden_EmptySeparatorSemanticsSurviveReload(t *testing.T) {
	config := `- source_labels: [first, last]
  separator: ""
  regex: "(.*)"
  target_label: full
  replacement: $1
  action: replace
`
	var cfgs []*Config
	err := yaml.UnmarshalStrict([]byte(config), &cfgs)
	require.NoError(t, err)
	for _, cfg := range cfgs {
		cfg.NameValidationScheme = model.UTF8Validation
		require.NoError(t, cfg.Validate(model.UTF8Validation))
	}

	input := labels.FromMap(map[string]string{
		"first": "foo",
		"last":  "bar",
	})

	// First application: with an empty separator the concatenated value is
	// "foobar", not "foo;bar".
	lb1 := labels.NewBuilder(input)
	keep := ProcessBuilder(lb1, cfgs...)
	require.Equal(t, true, keep)
	testutil.RequireEqual(t, labels.FromMap(map[string]string{
		"first": "foo",
		"last":  "bar",
		"full":  "foobar",
	}), lb1.Labels())

	// Serialize the rules and reload them, as a configuration reload would.
	out, err := yaml.Marshal(&cfgs)
	require.NoError(t, err)
	var cfgs2 []*Config
	err = yaml.Unmarshal([]byte(string(out)), &cfgs2)
	require.NoError(t, err)
	for _, cfg := range cfgs2 {
		cfg.NameValidationScheme = model.UTF8Validation
		require.NoError(t, cfg.Validate(model.UTF8Validation))
	}

	// The reloaded rules must produce exactly the same label rewrite.
	lb2 := labels.NewBuilder(input)
	keep = ProcessBuilder(lb2, cfgs2...)
	require.Equal(t, true, keep)
	testutil.RequireEqual(t, labels.FromMap(map[string]string{
		"first": "foo",
		"last":  "bar",
		"full":  "foobar",
	}), lb2.Labels())
}