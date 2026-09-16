package cobra

import (
	"fmt"
	"reflect"
	"testing"
)

// Authored hidden case for cistern-anchor.
//
// Exercises exactly the same Find() path as the overlaid upstream regression
// test (TestFind) but with argument layouts the upstream test does not use:
// the subcommand name used simultaneously as the value of more than one flag
// (long and short, and a flag that carries a default value), so the misplaced
// --flag/value pairs the bug produces differ from the correct output.
//
// Expected results are what a correct implementation MUST return; on the
// buggy parent commit the first argument equal to the subcommand name is
// mistaken for the subcommand even when it is the value of a preceding flag.

func TestHiddenFlagCollisions(t *testing.T) {
	var foo, bar string
	root := &Command{
		Use: "root",
	}
	root.PersistentFlags().StringVarP(&foo, "foo", "f", "", "the foo value")
	root.PersistentFlags().StringVarP(&bar, "bar", "b", "something", "the bar value")

	child := &Command{
		Use: "child",
	}
	root.AddCommand(child)

	other := &Command{
		Use: "other",
	}
	root.AddCommand(other)

	testCases := []struct {
		args              []string
		expectedCmd       string
		expectedFoundArgs []string
	}{
		{
			// both --foo and -f take "child" as their value; the real
			// subcommand token is the final one
			[]string{"--foo", "child", "-f", "child", "child"},
			"child",
			[]string{"--foo", "child", "-f", "child"},
		},
		{
			// short flag then long flag, both colliding with the subcommand
			[]string{"-f", "child", "--foo", "child", "child"},
			"child",
			[]string{"-f", "child", "--foo", "child"},
		},
		{
			// a third flag (-b) carries a default value, so its argument is
			// not consumed by the search as a flag value and "child" remains
			// the first candidate token before the real subcommand
			[]string{"--foo", "child", "-f", "child", "-b", "child", "child"},
			"child",
			[]string{"--foo", "child", "-f", "child", "-b", "child"},
		},
		{
			// the colliding value is the name of a *different* subcommand;
			// the actual target's name is never used as a flag value here
			[]string{"--foo", "child", "other"},
			"other",
			[]string{"--foo", "child"},
		},
		{
			// a plain non-colliding layout still resolves exactly
			[]string{"--foo", "value", "child"},
			"child",
			[]string{"--foo", "value"},
		},
	}

	for _, tc := range testCases {
		t.Run(fmt.Sprintf("args %v", tc.args), func(t *testing.T) {
			cmd, foundArgs, err := root.Find(tc.args)
			if err != nil {
				t.Fatal(err)
			}
			if cmd == nil || cmd.Use != tc.expectedCmd {
				t.Fatalf("Expected cmd to be %s, but it was not", tc.expectedCmd)
			}
			if !reflect.DeepEqual(tc.expectedFoundArgs, foundArgs) {
				t.Fatalf("Wrong args\nExpected: %v\nGot: %v", tc.expectedFoundArgs, foundArgs)
			}
		})
	}
}