package doc

// Hidden case 1 for yaw-roadstead: a three-level command tree with names the
// upstream regression test never uses. The see_also entry for the leaf
// reached through a nested subcommand must carry the full command path.
// (Authored for this task; not upstream code.)

import (
	"bytes"
	"testing"

	"github.com/spf13/cobra"
)

func TestHiddenSeeAlsoDeepTree(t *testing.T) {
	leaf := &cobra.Command{
		Use:   "leaf [arg]",
		Short: "leaf util command",
		Run:   emptyRun,
	}
	mid := &cobra.Command{Use: "mid [arg]", Short: "mid level tool"}
	top := &cobra.Command{Use: "top [arg]", Short: "top level tool"}

	mid.AddCommand(leaf)
	top.AddCommand(mid)

	buf := new(bytes.Buffer)
	if err := GenYaml(mid, buf); err != nil {
		t.Fatal(err)
	}
	output := buf.String()

	checkStringContains(t, output, "- top mid leaf - leaf util command")
	checkStringOmits(t, output, "- leaf - leaf util command")
	checkStringContains(t, output, "top - top level tool")
}
