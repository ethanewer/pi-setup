// Hidden grouping suite H1 for the query package: mixed boolean chains the
// visible fixture does not exercise. These parse trees are only correct when
// AND binds strictly tighter than OR, which is the token Precedence contract.
package query_test

import "bh/internal/parser"
import "bh/internal/query"
import "testing"

func TestHiddenGroupingChains(t *testing.T) {
	cases := []struct {
		expr string
		want string
	}{
		{"a = 1 OR b IN (2, 3) AND c = 4", "or(eq(a, 1), and(in(b, [2, 3]), eq(c, 4)))"},
		{"x = 1 OR y = 2 AND z = 3 AND w = 4", "or(eq(x, 1), and(and(eq(y, 2), eq(z, 3)), eq(w, 4)))"},
		{"p = 1 AND (q = 2 OR r = 3)", "and(eq(p, 1), or(eq(q, 2), eq(r, 3)))"},
		{"a LIKE 'x%' OR b = 1 AND c = 2", "or(like(a, 'x%'), and(eq(b, 1), eq(c, 2)))"},
		{"(a = 1 OR b = 2 OR c = 3) AND d = 4", "and(or(or(eq(a, 1), eq(b, 2)), eq(c, 3)), eq(d, 4))"},
	}
	for i, c := range cases {
		n, errs := parser.ParseCondition(c.expr)
		if errs != "" {
			t.Errorf("hidden h1 %d: %q: parse failed: %s", i, c.expr, errs)
			continue
		}
		n = query.NormalizeCondition(n)
		if got := n.Format(); got != c.want {
			t.Errorf("hidden h1 %d: %q groups as %q, want %q", i, c.expr, got, c.want)
		}
	}
}

// TestHiddenParenInvariance: parenthesised expressions must keep their shape
// even when boolean tiers move; this guards against an over-aggressive fix.
func TestHiddenParenInvariance(t *testing.T) {
	n, errs := parser.ParseCondition("(a = 1 OR b = 2) AND c = 3")
	if errs != "" {
		t.Fatalf("hidden h1: parse failed: %s", errs)
	}
	if got := query.NormalizeCondition(n).Format(); got != "and(or(eq(a, 1), eq(b, 2)), eq(c, 3))" {
		t.Errorf("hidden h1: parens lost: %q", got)
	}
}