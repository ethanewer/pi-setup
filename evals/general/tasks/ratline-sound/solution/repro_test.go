package cobra

import (
	"testing"
)

// ratline-sound oracle reproduction.
//
// A child command declares its own flag --drop that shadows the parent's
// persistent --drop. Help for the child must show the child's flag in the
// child's "Flags:" section and must NOT show the shadowed parent flag under
// "Global Flags:". At the pinned parent commit this test FAILS (the child's
// --drop is missing and the parent's --drop is shown under Global Flags);
// once command.go's local-flags computation stops dropping a shadowing flag,
// it PASSES.

func TestShadowedFlagHelpAndSplit(t *testing.T) {
	parent := &Command{Use: "parent", Run: emptyRun}
	child := &Command{Use: "child", Run: emptyRun}
	parent.AddCommand(child)

	parent.PersistentFlags().Bool("keep", false, "parent keep usage")
	parent.PersistentFlags().Bool("drop", false, "parent drop usage")
	child.Flags().Bool("drop", false, "child drop usage") // shadows parent's --drop
	child.Flags().Bool("own", false, "child own usage")

	output, err := executeCommand(parent, "help", "child")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	expected := `Usage:
  parent child [flags]

Flags:
      --drop   child drop usage
  -h, --help   help for child
      --own    child own usage

Global Flags:
      --keep   parent keep usage
`
	if output != expected {
		t.Errorf("Help text mismatch.\nExpected:\n%s\n\nGot:\n%s\n", expected, output)
	}

	// The shadowed flag must be a local flag of the child, not an inherited one.
	inherited := child.InheritedFlags()
	local := child.LocalFlags()
	if local.Lookup("drop") == nil {
		t.Error(`LocalFlags expected to contain "drop"`)
	}
	if inherited.Lookup("drop") != nil {
		t.Errorf(`InheritedFlags should not contain shadowed flag "drop"`)
	}
	if local.Lookup("own") == nil {
		t.Error(`LocalFlags expected to contain "own"`)
	}
	if inherited.Lookup("keep") == nil {
		t.Error(`InheritedFlags expected to contain "keep"`)
	}
}