package gin

import (
	"testing"
)

// Hidden case: a deeper mixed static/param subtree under a long prefix.
// The mixed node (/api/v1/users) carries one static child (/me) and one
// param child (/:id). Lookups from the upstream regression tests do not use
// this layout, this depth, or these segment values.

func TestHiddenCaseDeep(t *testing.T) {
	tree := &node{}

	routes := [...]string{
		"/api/v1/users/:id",
		"/api/v1/users/me",
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
	if out, found := tree.findCaseInsensitivePath("/api/v1/users/me", false); !found {
		t.Error("exact static route not found")
	} else if string(out) != "/api/v1/users/me" {
		t.Errorf("wrong static result: %s", string(out))
	}

	// wrong-case static leaf, must be corrected to the canonical path
	if out, found := tree.findCaseInsensitivePath("/API/V1/USERS/ME", false); !found {
		t.Error("wrong-case static route not found")
	} else if string(out) != "/api/v1/users/me" {
		t.Errorf("wrong case-insensitive result: %s", string(out))
	}

	// param route still matches arbitrary segment values
	if out, found := tree.findCaseInsensitivePath("/api/v1/users/1729", false); !found {
		t.Error("param route not matched")
	} else if string(out) != "/api/v1/users/1729" {
		t.Errorf("wrong param result: %s", string(out))
	}

	// wrong-case segment value goes through the param fallback, no panic
	if out, found := tree.findCaseInsensitivePath("/API/V1/USERS/UNK", false); !found {
		t.Error("wrong-case param fallback did not match")
	} else if string(out) != "/api/v1/users/UNK" {
		t.Errorf("wrong param fallback result: %s", string(out))
	}

	// a longer path beyond the static leaf must not match and must not panic
	if _, found := tree.findCaseInsensitivePath("/api/v1/users/me/extra", false); found {
		t.Error("static leaf with extra segment unexpectedly matched")
	}

	// trailing-slash handling: a trailing slash on the param route is
	// fixed by the lookup (slash consumed), never a panic
	if out, found := tree.findCaseInsensitivePath("/api/v1/users/1729/", true); !found {
		t.Error("trailing-slash fix on the param route did not match")
	} else if string(out) != "/api/v1/users/1729" {
		t.Errorf("wrong trailing-slash result: %s", string(out))
	}

	// same for the static leaf
	if out, found := tree.findCaseInsensitivePath("/api/v1/users/me/", true); !found {
		t.Error("trailing-slash fix on the static leaf did not match")
	} else if string(out) != "/api/v1/users/me" {
		t.Errorf("wrong trailing-slash static result: %s", string(out))
	}

	// uppercase rune on the path segment that reaches the mixed node,
	// trailing slash active, still a not-match and no panic
	if _, found := tree.findCaseInsensitivePath("/api/v1/users/ME/extra", true); found {
		t.Error("uppercase leaf with extra segment unexpectedly matched")
	}
}