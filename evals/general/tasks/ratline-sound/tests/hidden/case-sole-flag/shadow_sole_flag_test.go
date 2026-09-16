package cobra

import (
	"testing"
)

// ratline-sound hidden case B: TWO children each shadow the parent's SOLE
// persistent flag, so once the shadowing is honoured there are no inherited
// flags left and the "Global Flags:" section must vanish entirely from both
// children's help; one child additionally carries its own non-shadowing flag.
// The upstream regression tests only cover a parent that keeps an unshadowed
// persistent flag.

func TestHiddenSoleFlagsAcrossSiblings(t *testing.T) {
	parent := &Command{Use: "app", Run: emptyRun}
	parent.PersistentFlags().Bool("verbose", false, "app verbose usage")

	run := &Command{Use: "run", Run: emptyRun}
	stop := &Command{Use: "stop", Run: emptyRun}
	run.Flags().Bool("verbose", false, "run verbose usage")  // shadows --verbose
	stop.Flags().Bool("verbose", false, "stop verbose usage") // shadows --verbose
	stop.Flags().Bool("force", false, "stop force usage")
	parent.AddCommand(run)
	parent.AddCommand(stop)

	got, err := executeCommand(parent, "help", "run")
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	expectedRun := `Usage:
  app run [flags]

Flags:
  -h, --help      help for run
      --verbose   run verbose usage
`
	if got != expectedRun {
		t.Errorf("Help text mismatch for 'run'.\nExpected:\n%s\n\nGot:\n%s\n", expectedRun, got)
	}

	got2, err2 := executeCommand(parent, "help", "stop")
	if err2 != nil {
		t.Errorf("Unexpected error: %v", err2)
	}
	expectedStop := `Usage:
  app stop [flags]

Flags:
      --force     stop force usage
  -h, --help      help for stop
      --verbose   stop verbose usage
`
	if got2 != expectedStop {
		t.Errorf("Help text mismatch for 'stop'.\nExpected:\n%s\n\nGot:\n%s\n", expectedStop, got2)
	}

	// Nothing may be left as inherited once both persistent flags are shadowed.
	if run.InheritedFlags().Lookup("verbose") != nil {
		t.Errorf(`InheritedFlags of "run" should not contain shadowed flag "verbose"`)
	}
	if run.LocalFlags().Lookup("verbose") == nil {
		t.Error(`LocalFlags of "run" expected to contain "verbose"`)
	}
	if stop.LocalFlags().Lookup("force") == nil {
		t.Error(`LocalFlags of "stop" expected to contain "force"`)
	}
}