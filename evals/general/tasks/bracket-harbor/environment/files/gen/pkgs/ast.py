# internal/ast package.

AST_GO = """\
// Package ast is the condition/query tree built by the parser. Nodes are
// tagged by Kind and carry the minimal payload needed for canonical
// formatting, normalization and evaluation. The canonical formatter is the
// lingua franca of the test suite: conditions compare as strings.
package ast

import "bh/internal/token"
import "strings"

// NodeKind classifies the tree cells.
type NodeKind int

// Node kinds.
const (
	None      NodeKind = 0
	FieldRef  NodeKind = 1
	Literal   NodeKind = 2
	Binary    NodeKind = 3
	InList    NodeKind = 4
	Like      NodeKind = 5
	IsNull    NodeKind = 6
	Between   NodeKind = 7
	Query     NodeKind = 8
	Call      NodeKind = 9
)

// Node is one tree cell. Trees are built with pointers (Left/Right); Items
// holds the operand lists for IN and BETWEEN; Query carries the SELECT-list
// keys, the source name and the WHERE condition.
type Node struct {
	Kind   NodeKind
	Name   string   // field name or source name
	Val    string   // literal text
	Op     token.Kind
	Not    bool     // IS NOT NULL marker
	Left   *Node
	Right  *Node
	Items  []*Node
	Fields []string // canonical SELECT-list keys (Query)
	Cond   *Node    // WHERE condition (Query)
}

// Field builds a field reference cell.
func Field(name string) *Node {
	return &Node{ Kind: FieldRef, Name: name }
}

// Lit builds a literal cell (number or quoted string text).
func Lit(val string) *Node {
	return &Node{ Kind: Literal, Val: val }
}

// Bin builds a comparison or boolean cell.
func Bin(op token.Kind, l, r *Node) *Node {
	return &Node{ Kind: Binary, Op: op, Left: l, Right: r }
}

// InExpr builds "lhs IN (items...)".
func InExpr(lhs *Node, items []*Node) *Node {
	return &Node{ Kind: InList, Left: lhs, Items: items }
}

// LikeExpr builds "lhs LIKE pat" (op KindLike or KindNotLike).
func LikeExpr(op token.Kind, lhs, pat *Node) *Node {
	return &Node{ Kind: Like, Op: op, Left: lhs, Right: pat }
}

// IsNullExpr builds "lhs IS [NOT] NULL".
func IsNullExpr(lhs *Node, not bool) *Node {
	return &Node{ Kind: IsNull, Left: lhs, Not: not }
}

// BetweenExpr builds "lhs BETWEEN lo AND hi".
func BetweenExpr(lhs, lo, hi *Node) *Node {
	return &Node{ Kind: Between, Left: lhs, Items: []*Node{ lo, hi } }
}

// CallOf builds an aggregate-function cell like count(*).
func CallOf(name string, arg *Node) *Node {
	return &Node{ Kind: Call, Name: name, Left: arg }
}

// QueryNode builds a SELECT cell.
func QueryNode(fields []string, source string, cond *Node) *Node {
	return &Node{ Kind: Query, Fields: fields, Name: source, Cond: cond }
}

// IsEmpty reports whether the node is the zero cell.
func (n *Node) IsEmpty() bool {
	return n == nil || n.Kind == None
}

// IsLeaf reports whether the node carries only a Name or Val payload.
func (n *Node) IsLeaf() bool {
	if n == nil {
		return false
	}
	return n.Kind == FieldRef || n.Kind == Literal
}

// Equal compares two trees structurally.
func Equal(a, b *Node) bool {
	if a == nil || b == nil {
		return a == b
	}
	if a.Kind != b.Kind || a.Op != b.Op || a.Not != b.Not ||
		a.Name != b.Name || a.Val != b.Val {
		return false
	}
	if !Equal(a.Left, b.Left) || !Equal(a.Right, b.Right) {
		return false
	}
	if len(a.Items) != len(b.Items) {
		return false
	}
	for i := 0; i < len(a.Items); i++ {
		if !Equal(a.Items[i], b.Items[i]) {
			return false
		}
	}
	if len(a.Fields) != len(b.Fields) {
		return false
	}
	for i := 0; i < len(a.Fields); i++ {
		if a.Fields[i] != b.Fields[i] {
			return false
		}
	}
	return Equal(a.Cond, b.Cond)
}

// opName maps an operator kind to its canonical writer.
func opName(k token.Kind) string {
	return k.String()
}

// isNumericLiteral reports whether v is a plain or negative number, which
// the canonical formatter renders bare instead of quoted.
func isNumericLiteral(v string) bool {
	if v == "" {
		return false
	}
	start := 0
	if v[0] == '-' {
		start = 1
		if len(v) == 1 {
			return false
		}
	}
	digits := 0
	for i := start; i < len(v); i++ {
		if v[i] >= '0' && v[i] <= '9' {
			digits++
			continue
		}
		if v[i] == '.' {
			continue
		}
		return false
	}
	return digits > 0
}

// literalText renders a literal value canonically: numbers and the boolean
// keywords stay bare, everything else is single-quoted.
func literalText(v string) string {
	if isNumericLiteral(v) {
		return v
	}
	if v == "true" || v == "false" {
		return v
	}
	return "'" + v + "'"
}

// Format renders the deterministic, canonical spelling of the tree. It is
// the exchange format used by the test suite and the CLI.
func (n *Node) Format() string {
	if n == nil {
		return "()"
	}
	switch n.Kind {
	case FieldRef:
		return n.Name
	case Literal:
		return literalText(n.Val)
	case Binary:
		return opName(n.Op) + "(" + n.Left.Format() + ", " + n.Right.Format() + ")"
	case Like:
		return opName(n.Op) + "(" + n.Left.Format() + ", " + n.Right.Format() + ")"
	case InList:
		items := []string{}
		for _, it := range n.Items {
			items = append(items, it.Format())
		}
		return "in(" + n.Left.Format() + ", [" + strings.Join(items, ", ") + "])"
	case IsNull:
		op := "isnull"
		if n.Not {
			op = "isnotnull"
		}
		return op + "(" + n.Left.Format() + ")"
	case Between:
		if len(n.Items) != 2 {
			return "between(<invalid>)"
		}
		return "between(" + n.Left.Format() + ", " + n.Items[0].Format() + ", " + n.Items[1].Format() + ")"
	case Call:
		if n.Left == nil {
			return n.Name + "()"
		}
		return n.Name + "(" + n.Left.Format() + ")"
	case Query:
		buf := "query([" + strings.Join(n.Fields, ", ") + "] from " + n.Name
		if n.Cond != nil {
			buf += " where " + n.Cond.Format()
		}
		return buf + ")"
	}
	return "nil"
}

// Depth returns the longest root-to-leaf path length of the tree.
func (n *Node) Depth() int {
	if n == nil {
		return 0
	}
	max := 1
	child := func(c *Node) {
		if d := c.Depth() + 1; d > max {
			max = d
		}
	}
	child(n.Left)
	child(n.Right)
	child(n.Cond)
	for _, it := range n.Items {
		child(it)
	}
	return max
}

// LeafCount returns the number of leaf cells (fields and literals).
func (n *Node) LeafCount() int {
	if n == nil {
		return 0
	}
	if n.IsLeaf() {
		return 1
	}
	total := 0
	total += n.Left.LeafCount()
	total += n.Right.LeafCount()
	total += n.Cond.LeafCount()
	for _, it := range n.Items {
		total += it.LeafCount()
	}
	return total
}

// FieldNames collects the canonical field names referenced anywhere in a
// tree.
func (n *Node) FieldNames() []string {
	out := []string{}
	n.Walk(func(x *Node) {
		if x != nil && x.Kind == FieldRef {
			out = append(out, x.Name)
		}
	})
	return out
}

// IsComparison reports whether the node is a value comparison cell.
func (n *Node) IsComparison() bool {
	return n != nil && n.Kind == Binary && n.Op.IsComparison()
}

// Operator returns the node's operator kind (zero for non-operator cells).
func (n *Node) Operator() token.Kind {
	if n == nil {
		return 0
	}
	return n.Op
}

// Walk visits the tree in pre-order.
func (n *Node) Walk(fn func(*Node)) {
	if n == nil {
		return
	}
	fn(n)
	n.Left.Walk(fn)
	n.Right.Walk(fn)
	n.Cond.Walk(fn)
	for _, it := range n.Items {
		it.Walk(fn)
	}
}

// FormatString is a convenience wrapper around Format.
func FormatString(n *Node) string {
	return n.Format()
}

// Clone deep-copies the tree so consumers can normalize without mutating
// the parser's output.
func Clone(n *Node) *Node {
	if n == nil {
		return nil
	}
	c := new(Node)
	c.Kind = n.Kind
	c.Name = n.Name
	c.Val = n.Val
	c.Op = n.Op
	c.Not = n.Not
	c.Left = Clone(n.Left)
	c.Right = Clone(n.Right)
	c.Fields = n.Fields
	c.Cond = Clone(n.Cond)
	c.Items = make([]*Node, len(n.Items))
	for i := 0; i < len(n.Items); i++ {
		c.Items[i] = Clone(n.Items[i])
	}
	return c
}
"""

AST_TEST_GO = """\
// Unit tests for the ast formatter.
package ast_test

import "bh/internal/ast"
import "bh/internal/token"
import "testing"

func must(t *testing.T, got, want string) {
	if got != want {
		t.Errorf("Format() = %q, want %q", got, want)
	}
}

func TestLeafCells(t *testing.T) {
	must(t, ast.Field("p").Format(), "p")
	must(t, ast.Lit("1").Format(), "1")
	must(t, ast.Lit("-3.5").Format(), "-3.5")
	must(t, ast.Lit("x").Format(), "'x'")
	must(t, ast.Lit("true").Format(), "true")
	must(t, ast.Lit("").Format(), "''")
}

func TestBinary(t *testing.T) {
	n := ast.Bin(token.KindEquals, ast.Field("p"), ast.Lit("1"))
	must(t, n.Format(), "eq(p, 1)")
	o := ast.Bin(token.KindOr, n, ast.Bin(token.KindAnd,
		ast.Bin(token.KindEquals, ast.Field("q"), ast.Lit("2")),
		ast.Bin(token.KindEquals, ast.Field("r"), ast.Lit("3"))))
	must(t, o.Format(), "or(eq(p, 1), and(eq(q, 2), eq(r, 3)))")
}

func TestInLikeNull(t *testing.T) {
	inNode := ast.InExpr(ast.Field("x"), []*ast.Node{
		ast.Lit("1"), ast.Lit("2"), ast.Lit("3"),
	})
	must(t, inNode.Format(), "in(x, [1, 2, 3])")

	like := ast.LikeExpr(token.KindLike, ast.Field("name"), ast.Lit("jo%"))
	must(t, like.Format(), "like(name, 'jo%')")

	nl := ast.LikeExpr(token.KindNotLike, ast.Field("name"), ast.Lit("x%"))
	must(t, nl.Format(), "notlike(name, 'x%')")

	must(t, ast.IsNullExpr(ast.Field("flag"), false).Format(), "isnull(flag)")
	must(t, ast.IsNullExpr(ast.Field("flag"), true).Format(), "isnotnull(flag)")
}

func TestBetween(t *testing.T) {
	b := ast.BetweenExpr(ast.Field("n"), ast.Lit("1"), ast.Lit("5"))
	must(t, b.Format(), "between(n, 1, 5)")
}

func TestQuery(t *testing.T) {
	cond := ast.Bin(token.KindEquals, ast.Field("a"), ast.Lit("1"))
	q := ast.QueryNode([]string{"a", "b"}, "events", cond)
	must(t, q.Format(), "query([a, b] from events where eq(a, 1))")
	eq := ast.QueryNode([]string{"*"}, "t", nil)
	must(t, eq.Format(), "query([*] from t)")
}

func TestNilAndEmpty(t *testing.T) {
	var unset *ast.Node
	if !unset.IsEmpty() {
		t.Errorf("nil node must be empty")
	}
	z := new(ast.Node)
	if !z.IsEmpty() {
		t.Errorf("zero node must be empty")
	}
	if ast.Field("x").IsEmpty() {
		t.Errorf("field node must not be empty")
	}
	if !ast.Field("x").IsLeaf() {
		t.Errorf("field should be a leaf")
	}
	if ast.Bin(token.KindAnd, ast.Field("a"), ast.Field("b")).IsLeaf() {
		t.Errorf("binary should not be a leaf")
	}
	if !ast.Equal(unset, unset) {
		t.Errorf("nil must equal nil")
	}
	if ast.Equal(unset, ast.Field("x")) {
		t.Errorf("nil must not equal a field")
	}
}

func TestPredicates(t *testing.T) {
	eq := ast.Bin(token.KindEquals, ast.Field("a"), ast.Lit("1"))
	if !eq.IsComparison() {
		t.Errorf("equality must be a comparison")
	}
	bo := ast.Bin(token.KindAnd, eq, eq)
	if bo.IsComparison() {
		t.Errorf("boolean node is not a comparison")
	}
	if eq.Operator() != token.KindEquals {
		t.Errorf("Operator = %d", eq.Operator())
	}
	if ast.Field("x").Operator() != 0 {
		t.Errorf("field operator must be zero")
	}
}

func TestTreeMetrics(t *testing.T) {
	tree := ast.Bin(token.KindAnd,
		ast.Bin(token.KindEquals, ast.Field("a"), ast.Lit("1")),
		ast.Bin(token.KindOr,
			ast.Bin(token.KindEquals, ast.Field("b"), ast.Lit("2")),
			ast.Bin(token.KindEquals, ast.Field("c"), ast.Lit("3"))))
	if got := tree.Depth(); got != 4 {
		t.Errorf("Depth = %d, want 4", got)
	}
	if got := tree.LeafCount(); got != 6 {
		t.Errorf("LeafCount = %d, want 6", got)
	}
	fields := tree.FieldNames()
	if len(fields) != 3 {
		t.Errorf("FieldNames = %v", fields)
	}
	count := 0
	tree.Walk(func(x *ast.Node) {
		if x != nil && x.Kind == ast.Binary {
			count++
		}
	})
	if count != 5 {
		t.Errorf("Walk saw %d binary nodes, want 5", count)
	}
}

func TestEqualAndClone(t *testing.T) {
	a := ast.Bin(token.KindAnd, ast.Field("a"), ast.Lit("1"))
	b := ast.Clone(a)
	if !ast.Equal(a, b) {
		t.Errorf("clone must equal original")
	}
	b.Left = ast.Field("z")
	if ast.Equal(a, b) {
		t.Errorf("mutated clone must differ")
	}
}

"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/ast/ast.go": ("ast", _f(AST_GO)),
    "internal/ast/ast_test.go": ("ast", _f(AST_TEST_GO)),
}