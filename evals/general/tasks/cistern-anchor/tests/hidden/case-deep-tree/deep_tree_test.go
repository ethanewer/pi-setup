package cobra

import (
	"fmt"
	"reflect"
	"testing"
)

// Authored hidden case for cistern-anchor.
//
// Exercises the Find() subcommand-resolution path from a two-level command
// tree (root -> child -> grandchild) where the flag-value/subcommand-name
// collision has to be resolved at a deeper level than the upstream regression
// test reaches, and where the parent commit's mis-removal ripples into a
// different result for the deeper descent.

func TestHiddenDeepTree(t *testing.T) {
	var foo string
	root := &Command{
		Use: "root",
	}
	root.PersistentFlags().StringVarP(&foo, "foo", "f", "", "the foo value")

	child := &Command{
		Use: "child",
	}
	root.AddCommand(child)

	grandchild := &Command{
		Use: "grandchild",
	}
	child.AddCommand(grandchild)

	testCases := []struct {
		args              []string
		expectedCmd       string
		expectedFoundArgs []string
	}{
		{
			// both -f flags take "child" as their value; removing the wrong
			// "child" at the root level also shifts what the deeper level
			// sees, so the deeper descent distinguishes the two behaviours
			[]string{"-f", "child", "-f", "child", "child"},
			"child",
			[]string{"-f", "child", "-f", "child"},
		},
		{
			// a deep flag value: --foo takes the leaf's name as its value while
			// the subcommand actually chosen is the intermediate one
			[]string{"--foo", "grandchild", "child"},
			"child",
			[]string{"--foo", "grandchild"},
		},
		{
			// the collision at the root level must not break a subsequent
			// descent all the way to the leaf; the flag value is consumed at
			// every level of the descent
			[]string{"--foo", "x", "mid", "leaf"},
			"leaf",
			[]string{"--foo", "x"},
		},
	}
	// the third case needs a deeper literal tree: root -> mid -> leaf
	mid := &Command{
		Use: "mid",
	}
	root.AddCommand(mid)
	leaf := &Command{
		Use: "leaf",
	}
	mid.AddCommand(leaf)

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