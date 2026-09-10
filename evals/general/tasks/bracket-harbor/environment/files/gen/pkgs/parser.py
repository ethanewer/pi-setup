# internal/parser package.

PARSER_GO = """\
// Package parser builds the condition/query tree from lexer output using
// precedence climbing. The operator ladder is owned by package token
// (Kind.Precedence); this file never re-implements grouping locally, because
// the ladder is the contract consumers are tested against.
package parser

import "bh/internal/ast"
import "bh/internal/lexer"
import "bh/internal/token"

// Parser walks the lexer token stream. Tokens are consumed from a slice;
// the parser is a value object that the parse functions advance implicitly.
type Parser struct {
	toks []token.Token
	pos  int
}

// NewParser wraps a token slice.
func NewParser(ts []token.Token) *Parser {
	return &Parser{ toks: ts, pos: 0 }
}

// ParseCondition parses a complete boolean condition from source text and
// returns the tree plus an error message (empty on success).
func ParseCondition(src string) (*ast.Node, string) {
	ts, errs := lexer.Lex(src)
	if errs != "" {
		return nil, errs
	}
	p := NewParser(ts)
	n, err := p.parseBool(0)
	if err != "" {
		return nil, err
	}
	if !p.at(token.KindEOF) {
		return nil, "trailing input: " + p.peek().String()
	}
	return n, ""
}

// ParseQuery parses the supported SELECT subset:
//
//	SELECT <field list> [FROM <source>] [WHERE <condition>]
//
// GROUP BY / ORDER BY / LIMIT are lexed and reserved but not yet accepted;
// the 0.4 parser reports them as unsupported clauses.
func ParseQuery(src string) (*ast.Node, string) {
	ts, errs := lexer.Lex(src)
	if errs != "" {
		return nil, errs
	}
	p := NewParser(ts)
	return p.parseQuery()
}

// peek returns the current token, synthesising an EOF past the end.
func (p *Parser) peek() token.Token {
	if p.pos < len(p.toks) {
		return p.toks[p.pos]
	}
	return token.New(token.KindEOF, "", 0)
}

// next consumes and returns the current token.
func (p *Parser) next() token.Token {
	t := p.peek()
	p.pos++
	return t
}

// at reports whether the current token has the given kind.
func (p *Parser) at(k token.Kind) bool {
	return p.peek().Kind == k
}

// accept consumes the current token iff it has the given kind.
func (p *Parser) accept(k token.Kind) bool {
	if p.at(k) {
		p.next()
		return true
	}
	return false
}

// atNext reports whether the token after the cursor has the given kind,
// used for two-token operators such as NOT LIKE.
func (p *Parser) atNext(k token.Kind) bool {
	if p.pos+1 < len(p.toks) {
		return p.toks[p.pos+1].Kind == k
	}
	return false
}

// ParseConditions parses a batch of condition sources, stopping at the
// first failure. The nodes are returned in input order.
func ParseAll(srcs []string) ([]*ast.Node, string) {
	out := []*ast.Node{}
	for _, src := range srcs {
		n, errs := ParseCondition(src)
		if errs != "" {
			return nil, "in batch entry: " + errs
		}
		out = append(out, n)
	}
	return out, ""
}

// ParseConditionOrQuery accepts either a bare condition or a SELECT query
// and reports which form it was through the node kind.
func ParseConditionOrQuery(src string) (*ast.Node, string) {
	if n, errs := ParseCondition(src); errs == "" {
		return n, ""
	}
	return ParseQuery(src)
}

// parseQuery implements the SELECT subset described above.
func (p *Parser) parseQuery() (*ast.Node, string) {
	if !p.accept(token.KindSelect) {
		return nil, "expected SELECT"
	}
	fields := []*ast.Node{}
	for {
		f, err := p.parseOperand()
		if err != "" {
			return nil, err
		}
		fields = append(fields, f)
		if p.accept(token.KindComma) {
			continue
		}
		break
	}
	source := ""
	if p.accept(token.KindFrom) {
		t := p.next()
		if t.Kind != token.KindIdent {
			return nil, "expected source name after FROM"
		}
		source = t.Lit
	}
	var cond *ast.Node
	if p.accept(token.KindWhere) {
		c, err := p.parseBool(0)
		if err != "" {
			return nil, err
		}
		cond = c
	}
	if p.at(token.KindGroupBy) || p.at(token.KindOrderBy) ||
		p.at(token.KindLimit) {
		return nil, "clause not supported by the 0.4 parser: " + p.peek().String()
	}
	keys := make([]string, len(fields))
	for i := 0; i < len(fields); i++ {
		keys[i] = fields[i].Name
	}
	return ast.QueryNode(keys, source, cond), ""
}

// parseBool is the precedence-climbing core for conditions. The loop
// consults Kind.Precedence() for every operator; a tier greater than minPrec
// extends the current expression, anything at minPrec or below ends it
// (left-associative). Parentheses nest a fresh boolean expression.
func (p *Parser) parseBool(minPrec int) (*ast.Node, string) {
	var lhs *ast.Node
	if p.at(token.KindLParen) {
		p.next()
		inner, err := p.parseBool(0)
		if err != "" {
			return nil, err
		}
		if !p.accept(token.KindRParen) {
			return nil, "expected ')' at " + p.peek().String()
		}
		lhs = inner
	} else {
		base, err := p.parseRelational()
		if err != "" {
			return nil, err
		}
		lhs = base
	}
	for {
		k := p.peek().Kind
		if !k.IsOperator() {
			break
		}
		prec := k.Precedence()
		if prec <= minPrec {
			break
		}
		p.next()
		rhs, err := p.parseBool(prec)
		if err != "" {
			return nil, err
		}
		lhs = ast.Bin(k, lhs, rhs)
	}
	return lhs, ""
}

// parseRelational parses one comparison, membership, pattern, range or null
// test: the operand forms the whole relational tier.
func (p *Parser) parseRelational() (*ast.Node, string) {
	lhs, err := p.parseOperand()
	if err != "" {
		return nil, err
	}
	k := p.peek().Kind
	switch k {
	case token.KindEquals, token.KindNotEquals, token.KindLess,
		token.KindLessEq, token.KindGreater, token.KindGreaterEq:
		p.next()
		rhs, rerr := p.parseOperand()
		if rerr != "" {
			return nil, rerr
		}
		return ast.Bin(k, lhs, rhs), ""
	case token.KindIn:
		p.next()
		if !p.accept(token.KindLParen) {
			return nil, "expected '(' after IN"
		}
		items := []*ast.Node{}
		for {
			it, ierr := p.parseOperand()
			if ierr != "" {
				return nil, ierr
			}
			items = append(items, it)
			if p.accept(token.KindComma) {
				continue
			}
			break
		}
		if !p.accept(token.KindRParen) {
			return nil, "expected ')' after IN list"
		}
		return ast.InExpr(lhs, items), ""
	case token.KindLike:
		p.next()
		pat, perr := p.parseOperand()
		if perr != "" {
			return nil, perr
		}
		return ast.LikeExpr(token.KindLike, lhs, pat), ""
	case token.KindNot:
		// The only supported NOT form is the two-token NOT LIKE.
		if !p.atNext(token.KindLike) {
			return nil, "unsupported NOT form at " + p.peek().String()
		}
		p.next()
		p.next()
		pat, perr := p.parseOperand()
		if perr != "" {
			return nil, perr
		}
		return ast.LikeExpr(token.KindNotLike, lhs, pat), ""
	case token.KindBetween:
		p.next()
		lo, loerr := p.parseOperand()
		if loerr != "" {
			return nil, loerr
		}
		if !p.accept(token.KindAnd) {
			return nil, "expected AND in BETWEEN"
		}
		hi, hierr := p.parseOperand()
		if hierr != "" {
			return nil, hierr
		}
		return ast.BetweenExpr(lhs, lo, hi), ""
	case token.KindIs:
		p.next()
		not := p.accept(token.KindNot)
		if !p.accept(token.KindNull) {
			return nil, "expected NULL after IS"
		}
		return ast.IsNullExpr(lhs, not), ""
	}
	return lhs, ""
}

// parseOperand parses a primary: a field reference, a literal, a boolean
// keyword or an aggregate call.
func (p *Parser) parseOperand() (*ast.Node, string) {
	k := p.peek().Kind
	switch k {
	case token.KindNumber, token.KindString:
		t := p.next()
		return ast.Lit(t.Lit), ""
	case token.KindStar:
		p.next()
		return ast.Field("*"), ""
	case token.KindTrue:
		p.next()
		return ast.Lit("true"), ""
	case token.KindFalse:
		p.next()
		return ast.Lit("false"), ""
	case token.KindIdent:
		t := p.next()
		return ast.Field(t.Lit), ""
	case token.KindCount, token.KindSum, token.KindAvg,
		token.KindMin, token.KindMax:
		return p.parseAggregate()
	default:
		return nil, "unexpected token " + p.peek().String()
	}
}

// parseAggregate parses name(operand) into a call cell.
func (p *Parser) parseAggregate() (*ast.Node, string) {
	fn := p.next()
	if !p.accept(token.KindLParen) {
		return nil, "expected '(' after aggregate"
	}
	var arg *ast.Node
	if p.at(token.KindStar) {
		p.next()
		arg = ast.Field("*")
	} else {
		a, aerr := p.parseOperand()
		if aerr != "" {
			return nil, aerr
		}
		arg = a
	}
	if !p.accept(token.KindRParen) {
		return nil, "expected ')' after aggregate"
	}
	return ast.CallOf(fn.Lit, arg), ""
}
"""

PARSER_TEST_GO = """\
// Unit tests for the parser. Conditions here deliberately avoid mixing AND
// with OR in one chain: the boolean-tier grouping contract that arbitrates
// those is asserted by the query package (TestConditionGrouping) and by the
// hidden contract suites.
package parser_test

import "bh/internal/ast"
import "bh/internal/parser"
import "testing"

func mustParse(t *testing.T, src, want string) {
	n, errs := parser.ParseCondition(src)
	if errs != "" {
		t.Errorf("%q: parse failed: %s", src, errs)
		return
	}
	if got := n.Format(); got != want {
		t.Errorf("%q: Format() = %q, want %q", src, got, want)
	}
}

func mustErr(t *testing.T, src string) {
	_, errs := parser.ParseCondition(src)
	if errs == "" {
		t.Errorf("%q: expected a parse error", src)
	}
}

func TestConditions(t *testing.T) {
	mustParse(t, "p = 1", "eq(p, 1)")
	mustParse(t, "a = 1 OR b = 2", "or(eq(a, 1), eq(b, 2))")
	mustParse(t, "a = 1 AND b = 2", "and(eq(a, 1), eq(b, 2))")
	mustParse(t, "x IN (1, 2, 3)", "in(x, [1, 2, 3])")
	mustParse(t, "name LIKE 'jo%'", "like(name, 'jo%')")
	mustParse(t, "n NOT LIKE 'x%'", "notlike(n, 'x%')")
	mustParse(t, "deleted IS NULL", "isnull(deleted)")
	mustParse(t, "deleted IS NOT NULL", "isnotnull(deleted)")
	mustParse(t, "n BETWEEN 1 AND 5", "between(n, 1, 5)")
	mustParse(t, "(a = 1 OR b = 2)", "or(eq(a, 1), eq(b, 2))")
	mustParse(t, "Active = true", "eq(Active, true)")
	mustParse(t, "score > -1", "gt(score, -1)")
	mustParse(t, "u.field_x = 'v1'", "eq(u.field_x, 'v1')")
	mustParse(t, "x = 1 AND y = 2 AND z = 3", "and(and(eq(x, 1), eq(y, 2)), eq(z, 3))")
}

func TestChainedSameTier(t *testing.T) {
	// Same-tier chains are left-associative, which is fixed behavior
	// regardless of the exact tier numbers.
	mustParse(t, "a = 1 OR b = 2 OR c = 3", "or(or(eq(a, 1), eq(b, 2)), eq(c, 3))")
	mustParse(t, "a = 1 AND b = 2 AND c = 3", "and(and(eq(a, 1), eq(b, 2)), eq(c, 3))")
}

func TestMixedRelational(t *testing.T) {
	mustParse(t, "a = 1 AND b LIKE 'x%'", "and(eq(a, 1), like(b, 'x%'))")
	mustParse(t, "a LIKE 'x%' OR b = 2", "or(like(a, 'x%'), eq(b, 2))")
	mustParse(t, "(a IN (1, 2) OR b = 3) AND c NOT LIKE 'z%'",
		"and(or(in(a, [1, 2]), eq(b, 3)), notlike(c, 'z%'))")
}

func TestAggregates(t *testing.T) {
	mustParse(t, "count(*) > 5", "gt(count(*), 5)")
	mustParse(t, "avg(score) >= 3.5", "ge(avg(score), 3.5)")
}

func TestBatchWrappers(t *testing.T) {
	nodes, errs := parser.ParseAll([]string{"a = 1", "b = 2", "c = 3"})
	if errs != "" {
		t.Fatalf("ParseAll failed: %s", errs)
	}
	if len(nodes) != 3 {
		t.Errorf("ParseAll returned %d nodes", len(nodes))
	}
	if _, errs := parser.ParseAll([]string{"a = 1", "b =="}); errs == "" {
		t.Errorf("ParseAll must stop at the first failure")
	}
	n, errs := parser.ParseConditionOrQuery("p = 1")
	if errs != "" || n.Kind != ast.Binary {
		t.Errorf("ParseConditionOrQuery(condition) = %v, %q", n, errs)
	}
	q, errs := parser.ParseConditionOrQuery("SELECT a FROM t")
	if errs != "" || q.Kind != ast.Query {
		t.Errorf("ParseConditionOrQuery(query) = %v, %q", q, errs)
	}
}

func TestErrors(t *testing.T) {
	mustErr(t, "a =")
	mustErr(t, "a = 1 OR")
	mustErr(t, "a >< 1")
	mustErr(t, "a IN (1")
	mustErr(t, "(a = 1")
	mustErr(t, "a = 1 )")
	mustErr(t, "1 = p garbage")
	mustErr(t, "NOT p = 1")
}

func TestQueries(t *testing.T) {
	q, errs := parser.ParseQuery("SELECT a, b FROM events WHERE a = 1")
	if errs != "" {
		t.Fatalf("query failed: %s", errs)
	}
	if got := q.Format(); got != "query([a, b] from events where eq(a, 1))" {
		t.Errorf("query = %q", got)
	}

	q, errs = parser.ParseQuery("SELECT * FROM t")
	if errs != "" {
		t.Fatalf("query failed: %s", errs)
	}
	if got := q.Format(); got != "query([*] from t)" {
		t.Errorf("query = %q", got)
	}

	q, errs = parser.ParseQuery("SELECT a FROM t WHERE a = 1 AND b = 2")
	if errs != "" {
		t.Fatalf("query failed: %s", errs)
	}
	if got := q.Format(); got != "query([a] from t where and(eq(a, 1), eq(b, 2)))" {
		t.Errorf("query = %q", got)
	}

	if _, errs := parser.ParseQuery("b = 2"); errs == "" {
		t.Errorf("bare condition must not parse as a query")
	}
	if _, errs := parser.ParseQuery("SELECT a FROM t ORDER BY a"); errs == "" {
		t.Errorf("ORDER BY must be rejected by the 0.4 parser")
	}
}
"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/parser/parser.go": ("parser", _f(PARSER_GO)),
    "internal/parser/parser_test.go": ("parser", _f(PARSER_TEST_GO)),
}