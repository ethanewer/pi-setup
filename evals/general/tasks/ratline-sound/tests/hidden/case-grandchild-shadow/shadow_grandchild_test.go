package cobra

import (
	"testing"
)

// ratline-sound hidden case C: a THREE-LEVEL command tree (root -> middle ->
// leaf) where the leaf shadows an Int persistent flag declared at the ROOT,
// two levels up; help is requested through the multi-segment command path
// ("root help middle leaf"). The upstream regression tests only reach a
// two-level tree.

func TestHiddenGrandchildShadowsRootFlag(t *testing.T) {
	root := &Command{Use: "root", Run: emptyRun}
	middle := &Command{Use: "middle", Run: emptyRun}
	leaf := &Command{Use: "leaf", Run: emptyRun}
	root.AddCommand(middle)
	middle.AddCommand(leaf)

	root.PersistentFlags().Int("jobs", -1, "root jobs usage")
	leaf.Flags().Int("jobs", 4, "leaf jobs usage") // shadows root's persistent --jobs

	got, err := executeCommand(root, "help", "middle", "leaf")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	expected := `Usage:
  root middle leaf [flags]

Flags:
  -h, --help       help for leaf
      --jobs int   leaf jobs usage (default 4)
`
	if got != expected {
		t.Errorf("Help text mismatch.\nExpected:\n%s\n\nGot:\n%s\n", expected, got)
	}

	inherited := leaf.InheritedFlags()
	local := leaf.LocalFlags()
	if inherited.Lookup("jobs") != nil {
		t.Errorf(`InheritedFlags should not contain shadowed flag "jobs"`)
	}
	if local.Lookup("jobs") == nil {
		t.Error(`LocalFlags expected to contain "jobs"`)
	}
}