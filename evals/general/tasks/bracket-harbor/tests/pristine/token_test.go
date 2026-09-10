// Unit tests for package token. These pin the stable vocabulary surface.
// The exact precedence ladder itself is exercised by consumer packages, so
// this file validates the tiers only for shape, not for exact values.
package token_test

import "bh/internal/token"
import "strconv"
import "strings"
import "testing"

func TestTokenBuild(t *testing.T) {
	tok := token.New(token.KindIdent, "name", 4)
	if tok.Kind != token.KindIdent {
		t.Errorf("Kind = %d, want %d", tok.Kind, token.KindIdent)
	}
	if tok.Lit != "name" {
		t.Errorf("Lit = %q", tok.Lit)
	}
	if tok.Pos != 4 {
		t.Errorf("Pos = %d", tok.Pos)
	}
}

func TestKindSpellings(t *testing.T) {
	cases := []struct {
		k    token.Kind
		want string
	}{
		{ token.KindAnd, "and" },
		{ token.KindOr, "or" },
		{ token.KindEquals, "eq" },
		{ token.KindNotEquals, "ne" },
		{ token.KindNotLike, "notlike" },
		{ token.KindEOF, "eof" },
		{ token.KindSum, "sum" },
		{ token.KindIdent, "ident" },
		{ token.KindStar, "star" },
	}
	for _, c := range cases {
		if got := c.k.String(); got != c.want {
			t.Errorf("kind %s spells %q, want %q", strconv.Itoa(int(c.k)), got, c.want)
		}
	}
}

func TestKeywordResolution(t *testing.T) {
	if k, ok := token.LookupIdent("select"); !ok || k != token.KindSelect {
		t.Errorf("LookupIdent(select) = (%d, %v), want (select, true)", k, ok)
	}
	if k, ok := token.LookupIdent("SELect"); !ok || k != token.KindSelect {
		t.Errorf("LookupIdent is not case-insensitive: (%d, %v)", k, ok)
	}
	if k, ok := token.LookupIdent("selct"); ok || k != token.KindIdent {
		t.Errorf("near-miss 'selct' resolved to kind %d", k)
	}
	if _, ok := token.LookupIdent("P"); ok {
		t.Errorf("'P' should not be reserved")
	}
}

func TestCanonKeys(t *testing.T) {
	eq := func(a, b string) {
		if g := token.CanonKey(a); g != b {
			t.Errorf("CanonKey(%q) = %q, want %q", a, g, b)
		}
	}
	eq("user.name", "user.name")
	eq("USER.NAME", "user.name")
	eq("  user  name ", "user name")
	eq("user_name", "user_name")
	eq("", "")
	eq(" P.* ", "p.*")
	eq("a	b", "a b")
}

func TestWildcards(t *testing.T) {
	if !token.IsWildcardField("*") {
		t.Errorf("* should be a wildcard selector")
	}
	if !token.IsWildcardField("user.*") {
		t.Errorf("user.* should be a wildcard selector")
	}
	if token.IsWildcardField("user.name") {
		t.Errorf("user.name is not a wildcard selector")
	}
	if !token.SameKey("A B ", "a b") {
		t.Errorf("SameKey must fold case and spacing")
	}
}

func TestReservedTables(t *testing.T) {
	if token.ReservedCount() < 20 {
		t.Errorf("reserved table shrank to %d", token.ReservedCount())
	}
	if token.ExtensionCount() < 40 {
		t.Errorf("extension table shrank to %d", token.ExtensionCount())
	}
	for _, w := range token.ExtensionWords() {
		if _, ok := token.LookupIdent(w); ok {
			t.Errorf("extension word %q leaked into the live table", w)
		}
	}
}

func TestTierPredicates(t *testing.T) {
	if !token.KindAnd.IsBooleanOperator() || !token.KindOr.IsBooleanOperator() {
		t.Errorf("boolean predicates wrong")
	}
	if token.KindEquals.IsBooleanOperator() {
		t.Errorf("comparison is not boolean")
	}
	if !token.KindEquals.IsComparison() || !token.KindGreaterEq.IsComparison() {
		t.Errorf("comparison predicate wrong")
	}
	if token.KindIn.IsComparison() || token.KindLike.IsComparison() {
		t.Errorf("membership/pattern are not plain comparisons")
	}
	if got := token.PrecedenceTable(); !strings.Contains(got, "AND") {
		t.Errorf("PrecedenceTable broken: %q", got)
	}
}

func TestTierShapes(t *testing.T) {
	// Shape-level checks only: the exact ladder is a contract exercised by
	// the parser/query consumers; these assertions must hold for any sane
	// ranking and stay green across tier renumbering.
	if token.KindEquals.Precedence() <= token.KindAnd.Precedence() {
		t.Errorf("relational tier must stay strictly above the boolean tier: eq=%d and=%d", token.KindEquals.Precedence(), token.KindAnd.Precedence())
	}
	if token.KindIn.Precedence() != token.KindLike.Precedence() {
		t.Errorf("membership and pattern tiers diverged: in=%d like=%d", token.KindIn.Precedence(), token.KindLike.Precedence())
	}
	if token.KindNotLike.Precedence() != token.KindBetween.Precedence() {
		t.Errorf("pattern and range tiers diverged")
	}
	if !token.KindAnd.IsOperator() {
		t.Errorf("and is not marked as an operator")
	}
	if token.KindIdent.IsOperator() {
		t.Errorf("ident is marked as an operator")
	}
	if !token.KindNotLike.IsOperator() {
		t.Errorf("notlike is not marked as an operator")
	}
	if !token.KindNotLike.IsRelational() {
		t.Errorf("notlike must be relational")
	}
}
