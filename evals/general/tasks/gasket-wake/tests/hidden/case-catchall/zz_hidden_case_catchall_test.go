package gin

import (
	"testing"
)

// Hidden case: a static leaf sharing a node with a catch-all route. The
// catch-all is a wildcard child, so the mixed node has a static child and a
// wildcard child, the same crash condition as the param variant but through
// the catchAll code path. The upstream regression tests use param
// placeholders only. The expected results below were measured against the
// upstream-fixed build (they match what the normal router's getValue
// produces for the same tree).

func TestHiddenCaseCatchAll(t *testing.T) {
	tree := &node{}

	routes := [...]string{
		"/assets/images/logo.png",
		"/assets/:path...",
	}
	for _, route := range routes {
		recv := catchPanic(func() {
			tree.addRoute(route, fakeHandler(route))
		})
		if recv != nil {
			t.Fatalf("panic inserting route '%s': %v", route, recv)
		}
	}

	// exact static leaf, both case variants
	if out, found := tree.findCaseInsensitivePath("/assets/images/logo.png", false); !found {
		t.Error("exact static leaf not found")
	} else if string(out) != "/assets/images/logo.png" {
		t.Errorf("wrong static result: %s", string(out))
	}

	if out, found := tree.findCaseInsensitivePath("/ASSETS/IMAGES/LOGO.PNG", false); !found {
		t.Error("wrong-case static leaf not found")
	} else if string(out) != "/assets/images/logo.png" {
		t.Errorf("wrong case-insensitive result: %s", string(out))
	}

	// a path under the prefix that the catch-all does not claim: no panic,
	// the lookup simply reports not-found
	if _, found := tree.findCaseInsensitivePath("/assets/unversioned/blob.bin", true); found {
		t.Error("unclaimed deep path unexpectedly matched")
	}

	// slash-only remainder: not-found, no panic
	if _, found := tree.findCaseInsensitivePath("/assets/", true); found {
		t.Error("slash-only remainder unexpectedly matched")
	}

	// wrong case on such a path: not-found, no panic
	if _, found := tree.findCaseInsensitivePath("/ASSETS/UNVERSIONED/BLOB.BIN", false); found {
		t.Error("wrong-case unclaimed deep path unexpectedly matched")
	}

	// the catch-all still claims single-segment remainders: it appends the
	// remainder to the corrected prefix
	if out, found := tree.findCaseInsensitivePath("/assets/nope", false); !found {
		t.Error("catch-all did not claim /assets/nope")
	} else if string(out) != "/assets/nope" {
		t.Errorf("wrong catch-all result: %s", string(out))
	}

	if out, found := tree.findCaseInsensitivePath("/assets/images", true); !found {
		t.Error("catch-all did not claim /assets/images")
	} else if string(out) != "/assets/images" {
		t.Errorf("wrong catch-all result: %s", string(out))
	}

	// lookup below the static leaf must not match and must not panic
	if _, found := tree.findCaseInsensitivePath("/assets/images/logo.png/x", false); found {
		t.Error("static leaf with extra segment unexpectedly matched")
	}
}