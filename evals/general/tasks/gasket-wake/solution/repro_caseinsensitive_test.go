package gin

import (
	"testing"
)

// Reproduction for the case-insensitive fixed-path lookup panic.
// The registered routes mix a static leaf and a parameter child under one
// prefix, so the routing tree contains a node that has both static children
// and a wildcard (param) child. A lookup whose remaining path does not
// match any static child must not crash the process with
// "panic: invalid node type"; it must either match the param child or
// report "not found".

func TestReproCaseInsensitivePathStaticAndParam(t *testing.T) {
	tree := &node{}

	routes := [...]string{
		"/panel/:tab",
		"/panel/about",
	}
	for _, route := range routes {
		recv := catchPanic(func() {
			tree.addRoute(route, fakeHandler(route))
		})
		if recv != nil {
			t.Fatalf("panic inserting route '%s': %v", route, recv)
		}
	}

	// exact static leaf
	if out, found := tree.findCaseInsensitivePath("/panel/about", false); !found {
		t.Error("exact static route not found")
	} else if string(out) != "/panel/about" {
		t.Errorf("wrong static result: %s", string(out))
	}

	// wrong-case static leaf, must be corrected to the canonical path
	if out, found := tree.findCaseInsensitivePath("/PANEL/ABOUT", false); !found {
		t.Error("wrong-case static route not found")
	} else if string(out) != "/panel/about" {
		t.Errorf("wrong case-insensitive result: %s", string(out))
	}

	// param route must still match arbitrary segment values
	if out, found := tree.findCaseInsensitivePath("/panel/billing", false); !found {
		t.Error("param route not matched")
	} else if string(out) != "/panel/billing" {
		t.Errorf("wrong param result: %s", string(out))
	}
}

func TestReproCaseInsensitivePathNotFound(t *testing.T) {
	tree := &node{}

	routes := [...]string{
		"/aa/aa",
		"/:bb/aa",
	}
	for _, route := range routes {
		recv := catchPanic(func() {
			tree.addRoute(route, fakeHandler(route))
		})
		if recv != nil {
			t.Fatalf("panic inserting route '%s': %v", route, recv)
		}
	}

	// A lookup that matches no static child and no handler must report
	// "not found", not kill the process.
	if _, found := tree.findCaseInsensitivePath("/aa", false); found {
		t.Error("'/aa' unexpectedly matched")
	}
	if _, found := tree.findCaseInsensitivePath("/bb/cc/dd", false); found {
		t.Error("'/bb/cc/dd' unexpectedly matched")
	}
}