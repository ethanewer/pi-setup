# internal/query package: normalization, evaluation, selection.
# query_test.go contains TestConditionGrouping, the test that regressed when
# the token precedence tiers were folded.

QUERY_GO = """\
// Package query owns condition normalization, evaluation and row selection.
// Normalization folds field references through token.CanonKey so the parser,
// the store, the index planner and the report all agree on one key space,
// and the canonical formatter is the dialect tests compare against.
package query

import "bh/internal/ast"
import "bh/internal/store"
import "bh/internal/token"
import "strconv"

// NormalizeCondition canonicalizes every field reference in a condition and
// the SELECT-list keys of embedded queries, in place. It is idempotent.
func NormalizeCondition(n *ast.Node) *ast.Node {
	if n == nil {
		return nil
	}
	switch n.Kind {
	case ast.FieldRef:
		n.Name = token.CanonKey(n.Name)
	case ast.Binary:
		n.Left = NormalizeCondition(n.Left)
		n.Right = NormalizeCondition(n.Right)
	case ast.Like:
		n.Left = NormalizeCondition(n.Left)
	case ast.IsNull:
		n.Left = NormalizeCondition(n.Left)
	case ast.InList:
		n.Left = NormalizeCondition(n.Left)
	case ast.Between:
		n.Left = NormalizeCondition(n.Left)
	case ast.Query:
		for i := range n.Fields {
			n.Fields[i] = token.CanonKey(n.Fields[i])
		}
		n.Cond = NormalizeCondition(n.Cond)
	}
	return n
}

// NormalizeQuery is the query-level wrapper of NormalizeCondition.
func NormalizeQuery(n *ast.Node) *ast.Node {
	return NormalizeCondition(n)
}

// Canonical renders the parsed-and-normalized form of a condition source;
// it is the CLI's canon command and the test suite's shared vocabulary.
func Canonical(src string) (string, string) {
	n, errs := ParseNormalized(src)
	if errs != "" {
		return "", errs
	}
	return n.Format(), ""
}

// NormalizeBatch canonicalizes a batch of condition trees in place.
func NormalizeBatch(nodes []*ast.Node) []*ast.Node {
	for i, n := range nodes {
		nodes[i] = NormalizeCondition(n)
	}
	return nodes
}

// EvaluateRows evaluates a condition against a whole row set, returning one
// boolean per row.
func EvaluateRows(rows []*store.Row, n *ast.Node) []bool {
	out := make([]bool, len(rows))
	for i, row := range rows {
		out[i] = EvaluateCondition(row, n)
	}
	return out
}

// SelectCount counts the matching rows of a query.
func SelectCount(s *store.RowStore, q *ast.Node) int {
	if s == nil || q == nil {
		return 0
	}
	return len(Match(s.Scan(), q.Cond))
}

// Explain returns a one-line descriptor of how a condition will be
// evaluated: the canonical form plus the boolean structure depth.
func Explain(n *ast.Node) string {
	form := "()"
	if n != nil {
		form = n.Format()
	}
	return "condition " + strconv.Itoa(len(form)) + " chars, depth " +
		strconv.Itoa(depthOf(n))
}

func depthOf(n *ast.Node) int {
	if n == nil {
		return 0
	}
	d := 1
	if n.Left != nil && d < n.Left.Depth() + 1 {
		d = n.Left.Depth() + 1
	}
	if n.Right != nil && d < n.Right.Depth() + 1 {
		d = n.Right.Depth() + 1
	}
	return d
}

// ParseNormalized parses a condition and canonicalizes it.
func ParseNormalized(src string) (*ast.Node, string) {
	n, errs := parserParse(src)
	if errs != "" {
		return nil, errs
	}
	return NormalizeCondition(n), ""
}
"""

QUERY_HELPERS_GO = """\
// Parse helpers kept out of the main file to keep the import surface local.
package query

import "bh/internal/ast"
import "bh/internal/parser"

func parserParse(src string) (*ast.Node, string) {
	return parser.ParseCondition(src)
}
"""

EVALUATE_GO = """\
// Row-based evaluation of normalized conditions.
package query

import "bh/internal/ast"
import "bh/internal/store"
import "bh/internal/token"
import "strconv"
import "strings"

// ValueAt reads the value for a field key from a row, honouring canonical
// folding on both the lookup key and the row's own field list.
func ValueAt(row *store.Row, key string) string {
	if row == nil {
		return ""
	}
	for i, f := range row.Fields {
		if token.CanonKey(f) == key {
			return row.Values[i]
		}
	}
	return ""
}

// operand resolves a node to its comparison value: a field's cell or a
// literal's text.
func operandValue(row *store.Row, n *ast.Node) string {
	if n == nil {
		return ""
	}
	if n.Kind == ast.FieldRef {
		return ValueAt(row, n.Name)
	}
	return n.Val
}

// EvaluateCondition tests a normalized condition against a row. The store is
// not consulted: every cell lookup goes through the row's own field list.
func EvaluateCondition(row *store.Row, n *ast.Node) bool {
	if n == nil || row == nil {
		return n == nil
	}
	switch n.Kind {
	case ast.Binary:
		// Boolean combinators recurse; comparison operators compare the two
		// operand values.
		if n.Op == token.KindAnd {
			return EvaluateCondition(row, n.Left) && EvaluateCondition(row, n.Right)
		}
		if n.Op == token.KindOr {
			return EvaluateCondition(row, n.Left) || EvaluateCondition(row, n.Right)
		}
		l := operandValue(row, n.Left)
		r := operandValue(row, n.Right)
		return compareOp(n.Op, l, r)
	case ast.Like:
		matched := LikeMatch(operandValue(row, n.Left), n.Right.Val)
		if n.Op == token.KindNotLike {
			return !matched
		}
		return matched
	case ast.InList:
		got := operandValue(row, n.Left)
		for _, it := range n.Items {
			if operandValue(row, it) == got {
				return true
			}
		}
		return false
	case ast.IsNull:
		isNull := operandValue(row, n.Left) == ""
		if n.Not {
			return !isNull
		}
		return isNull
	case ast.Between:
		if len(n.Items) != 2 {
			return false
		}
		v := operandValue(row, n.Left)
		return lessEq(n.Items[0].Val, v) && lessEq(v, n.Items[1].Val)
	}
	return true
}

// CompareOp applies a comparison operator to two text values, numeric when
// both sides parse as numbers, lexicographic otherwise.
func CompareOp(op token.Kind, l, r string) bool {
	return compareOp(op, l, r)
}

func compareOp(op token.Kind, l, r string) bool {
	lf, lok := tryNumber(l)
	rf, rok := tryNumber(r)
	if lok && rok {
		switch op {
		case token.KindEquals:
			return lf == rf
		case token.KindNotEquals:
			return lf != rf
		case token.KindLess:
			return lf < rf
		case token.KindLessEq:
			return lf <= rf
		case token.KindGreater:
			return lf > rf
		case token.KindGreaterEq:
			return lf >= rf
		}
		return false
	}
	switch op {
	case token.KindEquals:
		return l == r
	case token.KindNotEquals:
		return l != r
	case token.KindLess:
		return l < r
	case token.KindLessEq:
		return l <= r
	case token.KindGreater:
		return l > r
	case token.KindGreaterEq:
		return l >= r
	}
	return false
}

func tryNumber(v string) (float64, bool) {
	if v == "" {
		return 0, false
	}
	f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
	return f, err == nil
}

func lessEq(a, b string) bool {
	af, aok := tryNumber(a)
	bf, bok := tryNumber(b)
	if aok && bok {
		return af <= bf
	}
	return a <= b
}

// LikeMatch implements '%'-wildcard pattern matching: '%' matches any run
// of characters, everything else matches literally.
func LikeMatch(value, pattern string) bool {
	i, j := 0, 0
	star := -1
	mark := 0
	for i < len(value) {
		if j < len(pattern) && pattern[j] == value[i] {
			i++
			j++
		} else if j < len(pattern) && pattern[j] == '%' {
			star = j
			j++
			mark = i
		} else if star >= 0 {
			j = star + 1
			mark++
			i = mark
		} else {
			return false
		}
	}
	for j < len(pattern) && pattern[j] == '%' {
		j++
	}
	return j == len(pattern)
}
"""

PREPARE_GO = """\
// Row selection helpers. Selection evaluates conditions row by row; the
// planner hints in package idx can shortcut equality probes.
package query

import "bh/internal/ast"
import "bh/internal/idx"
import "bh/internal/store"

// Match returns the indices of rows of s satisfying a normalized condition.
func Match(rows []*store.Row, cond *ast.Node) []int {
	out := []int{}
	for i, row := range rows {
		if EvaluateCondition(row, cond) {
			out = append(out, i)
		}
	}
	return out
}

// SelectRows evaluates a whole query against a store and returns the
// matching rows, preserving store order.
func SelectRows(s *store.RowStore, q *ast.Node) []*store.Row {
	out := []*store.Row{}
	if s == nil || q == nil {
		return out
	}
	sel := Match(s.Scan(), q.Cond)
	for _, i := range sel {
		if row, ok := s.Get(i); ok {
			out = append(out, row)
		}
	}
	return out
}

// PlanHint serves a query through an equality probe when the planner
// suggests it; otherwise it falls back to a scan. The full condition is
// always re-evaluated on candidate rows.
func PlanHint(s *store.RowStore, q *ast.Node, ix *idx.Index) []*store.Row {
	if s == nil || ix == nil || q == nil {
		return SelectRows(s, q)
	}
	c := q.Cond
	if c == nil || c.Kind != ast.Binary || c.Op != tokenEquals() {
		return SelectRows(s, q)
	}
	plan := idx.Suggest(ix, fieldOf(c), valueOf(c))
	if !plan.Indexed {
		return SelectRows(s, q)
	}
	rows := s.Scan()
	probe := plan.Recommend(ix)
	out := []*store.Row{}
	for _, ri := range probe {
		if ri < 0 || ri >= len(rows) {
			continue
		}
		if EvaluateCondition(rows[ri], c) {
			out = append(out, rows[ri])
		}
	}
	return out
}
"""

PREPARE_HELPERS_GO = """\
// Small helpers shared by the selection path.
package query

import "bh/internal/ast"
import "bh/internal/token"

func tokenEquals() token.Kind {
	return token.KindEquals
}

func fieldOf(n *ast.Node) string {
	if n == nil || n.Left == nil {
		return ""
	}
	return n.Left.Name
}

func valueOf(n *ast.Node) string {
	if n == nil || n.Right == nil {
		return ""
	}
	return n.Right.Val
}
"""

QUERY_TEST_GO = """\
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
"""

QUERY_TEST_HELPERS_GO = """\
// Local helpers for the query tests.
package query_test

import "bh/internal/idx"
import "bh/internal/store"

func idxBuild(s *store.RowStore, field string) *idx.Index {
	return idx.BuildIndex(s, field)
}
"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/query/query.go": ("query", _f(QUERY_GO)),
    "internal/query/helpers.go": ("query", _f(QUERY_HELPERS_GO)),
    "internal/query/evaluate.go": ("query", _f(EVALUATE_GO)),
    "internal/query/prepare.go": ("query", _f(PREPARE_GO)),
    "internal/query/prepare_helpers.go": ("query", _f(PREPARE_HELPERS_GO)),
    "internal/query/query_test.go": ("query", _f(QUERY_TEST_GO)),
    "internal/query/testhelpers_test.go": ("query", _f(QUERY_TEST_HELPERS_GO)),
}