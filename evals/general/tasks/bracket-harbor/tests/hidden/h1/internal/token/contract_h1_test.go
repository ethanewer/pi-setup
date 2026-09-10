// Hidden contract suite H1 for the token package. These cases pin the exact
// operator-tier ladder and the canonical-key surface that the visible tests
// deliberately only shape-check. They are mounted by the verifier and must
// hold under the documented contract in op.go.
package token_test

import "bh/internal/token"
import "testing"

func TestHiddenPrecedenceLadder(t *testing.T) {
	cases := []struct {
		k    token.Kind
		tier int
	}{
		{ token.KindOr, 2 },
		{ token.KindAnd, 3 },
		{ token.KindEquals, 4 },
		{ token.KindNotEquals, 4 },
		{ token.KindLess, 4 },
		{ token.KindLessEq, 4 },
		{ token.KindGreater, 4 },
		{ token.KindGreaterEq, 4 },
		{ token.KindIn, 4 },
		{ token.KindLike, 4 },
		{ token.KindNotLike, 4 },
		{ token.KindBetween, 4 },
	}
	for _, c := range cases {
		if got := c.k.Precedence(); got != c.tier {
			t.Errorf("hidden h1: %s precedence = %d, want %d (contract ladder)", c.k.String(), got, c.tier)
		}
	}
}

func TestHiddenBooleanOrdering(t *testing.T) {
	if got := token.KindAnd.Precedence(); got <= token.KindOr.Precedence() {
		t.Errorf("hidden h1: AND(%d) must bind strictly tighter than OR(%d)", got, token.KindOr.Precedence())
	}
}

func TestHiddenCanonKeys(t *testing.T) {
	eq := func(a, b string) {
		if g := token.CanonKey(a); g != b {
			t.Errorf("hidden h1: CanonKey(%q) = %q, want %q", a, g, b)
		}
	}
	eq("  Mixed  Spacing ", "mixed spacing")
	eq("user_name", "user_name")
	eq("User.Name", "user.name")
	eq("P.*", "p.*")
	eq("a\t\nb", "a b")
	eq("\t edge \t", "edge")
}

func TestHiddenTierLabels(t *testing.T) {
	if got := token.TierLabel(4); got != "relational" {
		t.Errorf("hidden h1: TierLabel(4) = %q, want \"relational\"", got)
	}
	if got := token.TierLabel(2); got != "boolean-or" {
		t.Errorf("hidden h1: TierLabel(2) = %q, want \"boolean-or\"", got)
	}
	if got := token.TierLabel(3); got != "boolean-and" {
		t.Errorf("hidden h1: TierLabel(3) = %q, want \"boolean-and\"", got)
	}
}

func TestHiddenKeywordSurface(t *testing.T) {
	if _, ok := token.LookupIdent("OR"); !ok {
		t.Errorf("hidden h1: OR must resolve")
	}
	if k, ok := token.LookupIdent("between"); !ok || k != token.KindBetween {
		t.Errorf("hidden h1: between must resolve to the range kind")
	}
	if _, ok := token.LookupIdent("and"); !ok {
		t.Errorf("hidden h1: and must resolve")
	}
}