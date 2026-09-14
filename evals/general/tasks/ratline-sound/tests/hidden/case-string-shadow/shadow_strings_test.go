package cobra

import (
	"testing"
)

// ratline-sound hidden case A: child shadows a parent persistent *string*
// flag (upstream tests cover bool/int shadowing only), help text compared for
// exact equality, plus the LocalFlags/InheritedFlags split for the shadowed
// and the unshadowed persistent flags.

func TestHiddenStringShadowSplit(t *testing.T) {
	parent := &Command{Use: "parent", Run: emptyRun}
	child := &Command{Use: "child", Run: emptyRun}
	parent.AddCommand(child)

	parent.PersistentFlags().String("host", "", "parent host usage")
	parent.PersistentFlags().String("region", "", "parent region usage")
	child.Flags().String("host", "", "child host usage") // shadows parent's --host
	child.Flags().Bool("tls", false, "child tls usage")

	got, err := executeCommand(parent, "help", "child")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}

	expected := `Usage:
  parent child [flags]

Flags:
  -h, --help          help for child
      --host string   child host usage
      --tls           child tls usage

Global Flags:
      --region string   parent region usage
`
	if got != expected {
		t.Errorf("Help text mismatch.\nExpected:\n%s\n\nGot:\n%s\n", expected, got)
	}

	inherited := child.InheritedFlags()
	local := child.LocalFlags()
	if inherited.Lookup("region") == nil {
		t.Error(`InheritedFlags expected to contain "region"`)
	}
	if inherited.Lookup("host") != nil {
		t.Errorf(`InheritedFlags should not contain shadowed flag "host"`)
	}
	if local.Lookup("host") == nil {
		t.Error(`LocalFlags expected to contain "host"`)
	}
	if local.Lookup("tls") == nil {
		t.Error(`LocalFlags expected to contain "tls"`)
	}
}