// Unit tests for the query package.
//
// TestConditionGrouping pins the boolean-tier grouping contract: it must
// parse "p = 1 OR q = 2 AND r = 3" with AND binding tighter than OR. The
// parser delegates every grouping decision to token.Precedence, so this test
// is the visible referee for the operator-tier table in internal/token.
package query_test

import "bh/internal/parser"
import "bh/internal/query"
import "bh/internal/store"
import "strings"
import "testing"

func TestConditionGrouping(t *testing.T) {
	cases := []struct {
		expr string
		want string
	}{
		{"p = 1 OR q = 2 AND r = 3", "or(eq(p, 1), and(eq(q, 2), eq(r, 3)))"},
		{"p = 1 OR q = 2 OR r = 3 AND s = 4", "or(or(eq(p, 1), eq(q, 2)), and(eq(r, 3), eq(s, 4)))"},
		{"p = 1 AND q = 2 OR r = 3", "or(and(eq(p, 1), eq(q, 2)), eq(r, 3))"},
		{"(p = 1 OR q = 2) AND r = 3", "and(or(eq(p, 1), eq(q, 2)), eq(r, 3))"},
	}
	for i, c := range cases {
		n, errs := parser.ParseCondition(c.expr)
		if errs != "" {
			t.Errorf("case %d: %q: parse failed: %s", i, c.expr, errs)
			continue
		}
		n = query.NormalizeCondition(n)
		if got := n.Format(); got != c.want {
			t.Errorf("case %d: %q groups as %q, want %q", i, c.expr, got, c.want)
		}
	}
}

func TestNormalizeFields(t *testing.T) {
	n, errs := parser.ParseCondition("Platform = 'linux' OR  Status  = 'ok'")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	n = query.NormalizeCondition(n)
	if got := n.Format(); got != "or(eq(platform, 'linux'), eq(status, 'ok'))" {
		t.Errorf("normalized = %q", got)
	}
}

func TestEvaluateEquality(t *testing.T) {
	s := store.New("t", []string{"a", "b"})
	s.Insert([]string{"1", "x"})
	s.Insert([]string{"2", "y"})
	row, _ := s.Get(0)
	cond, errs := parser.ParseCondition("a = 1 AND b = 'x'")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	cond = query.NormalizeCondition(cond)
	if !query.EvaluateCondition(row, cond) {
		t.Errorf("row 0 should match")
	}
	row2, _ := s.Get(1)
	cond2, _ := parser.ParseCondition("a = 1")
	if query.EvaluateCondition(row2, query.NormalizeCondition(cond2)) {
		t.Errorf("row 1 should not match a = 1")
	}
}

func TestEvaluateInAndLike(t *testing.T) {
	row := &store.Row{ Fields: []string{"name", "score"}, Values: []string{"alice", "85"} }
	cond, errs := parser.ParseCondition("name IN ('alice', 'bob') AND score > 80")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	cond = query.NormalizeCondition(cond)
	if !query.EvaluateCondition(row, cond) {
		t.Errorf("IN + gt should match")
	}
	like, errs := parser.ParseCondition("name LIKE 'al%'")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	like = query.NormalizeCondition(like)
	if !query.EvaluateCondition(row, like) {
		t.Errorf("LIKE should match")
	}
	notlike, errs := parser.ParseCondition("name NOT LIKE 'bo%'")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	notlike = query.NormalizeCondition(notlike)
	if !query.EvaluateCondition(row, notlike) {
		t.Errorf("NOT LIKE should match")
	}
}

func TestEvaluateNullAndRange(t *testing.T) {
	row := &store.Row{ Fields: []string{"deleted", "n"}, Values: []string{"", "42"} }
	cond, errs := parser.ParseCondition("deleted IS NULL AND n BETWEEN 40 AND 50")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	cond = query.NormalizeCondition(cond)
	if !query.EvaluateCondition(row, cond) {
		t.Errorf("null+between should match")
	}
	notNull, errs := parser.ParseCondition("deleted IS NOT NULL")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	if query.EvaluateCondition(row, query.NormalizeCondition(notNull)) {
		t.Errorf("empty cell is null")
	}
}

func TestMatchRows(t *testing.T) {
	s := store.New("t", []string{"a", "b"})
	s.Insert([]string{"1", "x"})
	s.Insert([]string{"2", "y"})
	s.Insert([]string{"1", "z"})
	cond, errs := parser.ParseCondition("a = 1")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	sel := query.Match(s.Scan(), query.NormalizeCondition(cond))
	if len(sel) != 2 || sel[0] != 0 || sel[1] != 2 {
		t.Errorf("Match = %v", sel)
	}
}

func TestPlanHint(t *testing.T) {
	s := store.New("u", []string{"name", "city"})
	s.Insert([]string{"alice", "berlin"})
	s.Insert([]string{"bob", "berlin"})
	s.Insert([]string{"cara", "rome"})
	ix := idxBuild(s, "city")
	q, errs := parser.ParseQuery("SELECT * FROM u WHERE city = 'berlin'")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	out := query.PlanHint(s, query.NormalizeQuery(q), ix)
	if len(out) != 2 {
		t.Errorf("PlanHint found %d rows", len(out))
	}
}

func TestExplain(t *testing.T) {
	n, errs := query.ParseNormalized("p = 1 OR q = 2")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	if got := query.Explain(n); !strings.Contains(got, "condition") {
		t.Errorf("Explain = %q", got)
	}
}

func TestCanonicalHelper(t *testing.T) {
	got, errs := query.Canonical("p = 1 OR q = 2")
	if errs != "" {
		t.Fatalf("canonical failed: %s", errs)
	}
	if got != "or(eq(p, 1), eq(q, 2))" {
		t.Errorf("Canonical = %q", got)
	}
	if _, errs := query.Canonical("p =="); errs == "" {
		t.Errorf("invalid condition must error")
	}
}
