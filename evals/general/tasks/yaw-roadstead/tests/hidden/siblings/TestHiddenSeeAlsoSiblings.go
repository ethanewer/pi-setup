package doc

// Hidden case 2 for yaw-roadstead: sibling subcommands under a long
// command name; see_also for each must show the full path, and a sibling's
// bare name must not be emitted for another sibling's path.

import (
	"bytes"
	"testing"

	"github.com/spf13/cobra"
)

func TestHiddenSeeAlsoSiblings(t *testing.T) {
	alpha := &cobra.Command{Use: "alpha [x]", Short: "alpha action", Run: emptyRun}
	beta := &cobra.Command{Use: "beta [y]", Short: "beta action", Run: emptyRun}
	gamma := &cobra.Command{Use: "gamma [z]", Short: "gamma action", Run: emptyRun}
	base := &cobra.Command{Use: "superbase [a]", Short: "superbase command"}

	base.AddCommand(alpha)
	base.AddCommand(beta)
	base.AddCommand(gamma)

	buf := new(bytes.Buffer)
	if err := GenYaml(base, buf); err != nil {
		t.Fatal(err)
	}
	output := buf.String()

	checkStringContains(t, output, "- superbase alpha - alpha action")
	checkStringContains(t, output, "- superbase beta - beta action")
	checkStringContains(t, output, "- superbase gamma - gamma action")
	checkStringOmits(t, output, "- beta - beta action")
}
