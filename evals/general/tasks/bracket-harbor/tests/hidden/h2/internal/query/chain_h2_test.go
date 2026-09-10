// Hidden grouping suite H2 for the query package: longer chains and mixed
// relational operators. Like H1, these only pass when the boolean tier
// ladder is intact.
package query_test

import "bh/internal/parser"
import "bh/internal/query"
import "bh/internal/store"
import "testing"

func TestHiddenLongChains(t *testing.T) {
	cases := []struct {
		expr string
		want string
	}{
		{"k = 1 OR n BETWEEN 2 AND 3 AND m = 4", "or(eq(k, 1), and(between(n, 2, 3), eq(m, 4)))"},
		{"a = 1 OR b NOT LIKE 'x%' AND c = 2", "or(eq(a, 1), and(notlike(b, 'x%'), eq(c, 2)))"},
		{"x = 1 OR y = 2 OR z = 3 OR w = 4 AND v = 5", "or(or(or(eq(x, 1), eq(y, 2)), eq(z, 3)), and(eq(w, 4), eq(v, 5)))"},
		{"Flag = true OR Deep = 0 AND High = 0", "or(eq(flag, true), and(eq(deep, 0), eq(high, 0)))"},
		{"a = 1 OR b IN (1) AND (c = 2 OR d = 3)", "or(eq(a, 1), and(in(b, [1]), or(eq(c, 2), eq(d, 3))))"},
	}
	for i, c := range cases {
		n, errs := parser.ParseCondition(c.expr)
		if errs != "" {
			t.Errorf("hidden h2 %d: %q: parse failed: %s", i, c.expr, errs)
			continue
		}
		n = query.NormalizeCondition(n)
		if got := n.Format(); got != c.want {
			t.Errorf("hidden h2 %d: %q groups as %q, want %q", i, c.expr, got, c.want)
		}
	}
}

// TestHiddenEvaluationAcrossChain: evaluating a mixed chain against a row
// must follow the AND>OR grouping. With a=1, b=8 and c=0 the condition
// "a = 1 OR b = 9 AND c = 3" is true under the correct grouping and false
// under a flat left-to-right parse, so a test-only workaround cannot pass.
func TestHiddenEvaluationAcrossChain(t *testing.T) {
	row := &store.Row{
		Fields: []string{"a", "b", "c"},
		Values: []string{"1", "8", "0"},
	}
	cond, errs := parser.ParseCondition("a = 1 OR b = 9 AND c = 3")
	if errs != "" {
		t.Fatalf("hidden h2: parse failed: %s", errs)
	}
	if !query.EvaluateCondition(row, query.NormalizeCondition(cond)) {
		t.Errorf("hidden h2: mixed chain must evaluate true under AND>OR grouping")
	}
}