# internal/token package: vocabulary, keyword table, operator tiers, canonical keys.

KINDS_GO = """\
// Package token defines the vocabulary of the bh query language: token
// kinds, the reserved-word table, operator tier metadata and the canonical
// field-key folding shared by every package that compares or indexes field
// names. The operator tiers in op.go are the package's public contract;
// consumers parse and plan against them, so they never special-case boolean
// grouping locally.
package token

import "strconv"
import "strings"

// Kind identifies every token the lexer may produce.
type Kind int

// Kinds produced by the lexer for structural and literal tokens.
const (
	KindEOF      Kind = 0
	KindIllegal  Kind = 1
	KindIdent    Kind = 2
	KindString   Kind = 3
	KindNumber   Kind = 4
)

// Kinds emitted for statement-level keywords.
const (
	KindSelect   Kind = 10
	KindFrom     Kind = 11
	KindWhere    Kind = 12
	KindGroupBy  Kind = 13
	KindOrderBy  Kind = 14
	KindHaving   Kind = 15
	KindLimit    Kind = 16
	KindOffset   Kind = 17
	KindAs       Kind = 18
	KindDistinct Kind = 19
)

// Kinds emitted for predicate and boolean keywords.
const (
	KindAnd      Kind = 20
	KindOr       Kind = 21
	KindNot      Kind = 22
	KindIn       Kind = 23
	KindLike     Kind = 24
	KindNotLike  Kind = 25
	KindBetween  Kind = 26
	KindIs       Kind = 27
	KindNull     Kind = 28
	KindTrue     Kind = 29
	KindFalse    Kind = 30
)

// Kinds produced by the operator scanner.
const (
	KindEquals     Kind = 40
	KindNotEquals  Kind = 41
	KindLess       Kind = 42
	KindLessEq     Kind = 43
	KindGreater    Kind = 44
	KindGreaterEq  Kind = 45
)

// Punctuation kinds.
const (
	KindLParen  Kind = 60
	KindRParen  Kind = 61
	KindComma   Kind = 62
	KindStar    Kind = 63
)

// Aggregate function kinds.
const (
	KindCount  Kind = 70
	KindSum    Kind = 71
	KindAvg    Kind = 72
	KindMin    Kind = 73
	KindMax    Kind = 74
)

// Join kinds, reserved for query forms the 0.4 parser does not yet accept.
const (
	KindJoin      Kind = 80
	KindInnerJoin Kind = 81
	KindLeftJoin  Kind = 82
	KindRightJoin Kind = 83
	KindOn        Kind = 84
)

// String returns the canonical spelling of the kind, used by diagnostics and
// by the canonical condition formatter.
func (k Kind) String() string {
	switch k {
	case KindEOF:
		return "eof"
	case KindIllegal:
		return "illegal"
	case KindIdent:
		return "ident"
	case KindString:
		return "string"
	case KindNumber:
		return "number"
	case KindSelect:
		return "select"
	case KindFrom:
		return "from"
	case KindWhere:
		return "where"
	case KindGroupBy:
		return "groupby"
	case KindOrderBy:
		return "orderby"
	case KindHaving:
		return "having"
	case KindLimit:
		return "limit"
	case KindOffset:
		return "offset"
	case KindAs:
		return "as"
	case KindDistinct:
		return "distinct"
	case KindAnd:
		return "and"
	case KindOr:
		return "or"
	case KindNot:
		return "not"
	case KindIn:
		return "in"
	case KindLike:
		return "like"
	case KindNotLike:
		return "notlike"
	case KindBetween:
		return "between"
	case KindIs:
		return "is"
	case KindNull:
		return "null"
	case KindTrue:
		return "true"
	case KindFalse:
		return "false"
	case KindEquals:
		return "eq"
	case KindNotEquals:
		return "ne"
	case KindLess:
		return "lt"
	case KindLessEq:
		return "le"
	case KindGreater:
		return "gt"
	case KindGreaterEq:
		return "ge"
	case KindLParen:
		return "lparen"
	case KindRParen:
		return "rparen"
	case KindComma:
		return "comma"
	case KindStar:
		return "star"
	case KindCount:
		return "count"
	case KindSum:
		return "sum"
	case KindAvg:
		return "avg"
	case KindMin:
		return "min"
	case KindMax:
		return "max"
	case KindJoin:
		return "join"
	case KindInnerJoin:
		return "innerjoin"
	case KindLeftJoin:
		return "leftjoin"
	case KindRightJoin:
		return "rightjoin"
	case KindOn:
		return "on"
	}
	return "kind(" + strconv.Itoa(int(k)) + ")"
}

// Token is a single lexeme with its source offset.
type Token struct {
	Kind Kind
	Lit  string
	Pos  int
}

// New builds a token.
func New(k Kind, lit string, pos int) Token {
	return Token{ Kind: k, Lit: lit, Pos: pos }
}

// String renders a token for diagnostics: KIND('lit')@pos.
func (t Token) String() string {
	return t.Kind.String() + "('" + t.Lit + "')@" + strconv.Itoa(t.Pos)
}

// Dump renders a token slice for lexer tests and debugging.
func Dump(ts []Token) string {
	parts := []string{}
	for _, t := range ts {
		parts = append(parts, t.String())
	}
	return strings.Join(parts, " ")
}
"""

KEYWORDS_GO = """\
// The reserved-word table. Bare identifiers resolve through Keywords();
// spellings that match are bound to their keyword kind case-insensitively;
// everything else stays a field name.
package token

import "strings"

// Keyword is one reserved spelling bound to a token kind.
type Keyword struct {
	Text string
	Kind Kind
}

// Keywords returns the full reserved-word table used by the lexer.
func Keywords() []Keyword {
	return []Keyword{
		{ Text: "select", Kind: KindSelect },
		{ Text: "from", Kind: KindFrom },
		{ Text: "where", Kind: KindWhere },
		{ Text: "group", Kind: KindGroupBy },
		{ Text: "order", Kind: KindOrderBy },
		{ Text: "having", Kind: KindHaving },
		{ Text: "limit", Kind: KindLimit },
		{ Text: "offset", Kind: KindOffset },
		{ Text: "as", Kind: KindAs },
		{ Text: "distinct", Kind: KindDistinct },
		{ Text: "and", Kind: KindAnd },
		{ Text: "or", Kind: KindOr },
		{ Text: "not", Kind: KindNot },
		{ Text: "in", Kind: KindIn },
		{ Text: "like", Kind: KindLike },
		{ Text: "between", Kind: KindBetween },
		{ Text: "is", Kind: KindIs },
		{ Text: "null", Kind: KindNull },
		{ Text: "true", Kind: KindTrue },
		{ Text: "false", Kind: KindFalse },
		{ Text: "count", Kind: KindCount },
		{ Text: "sum", Kind: KindSum },
		{ Text: "avg", Kind: KindAvg },
		{ Text: "min", Kind: KindMin },
		{ Text: "max", Kind: KindMax },
		{ Text: "join", Kind: KindJoin },
		{ Text: "inner", Kind: KindInnerJoin },
		{ Text: "left", Kind: KindLeftJoin },
		{ Text: "right", Kind: KindRightJoin },
		{ Text: "on", Kind: KindOn },
	}
}

// LookupIdent resolves s to its keyword kind. An unresolvable spelling
// returns KindIdent with ok == false, letting the lexer keep the word as a
// plain field name.
func LookupIdent(s string) (Kind, bool) {
	w := strings.ToLower(s)
	for _, kw := range Keywords() {
		if kw.Text == w {
			return kw.Kind, true
		}
	}
	return KindIdent, false
}

// IsReserved reports whether the spelling is currently in the keyword table.
func IsReserved(s string) bool {
	_, ok := LookupIdent(s)
	return ok
}

// ExtensionWords lists spellings set aside for future keyword use. They are
// NOT reserved today: stores may use them as field names, and the promised
// spellings are pinned by tests so a future reservation is a visible change.
func ExtensionWords() []string {
	return []string{
		"active", "after", "all", "any", "array", "at", "author", "auto",
		"before", "begin", "cascade", "case", "cast", "checksum", "coerce",
		"collate", "compress", "container", "create", "database", "desc",
		"domain", "end", "engine", "event", "except", "exists", "expire",
		"export", "facet", "fail", "filter", "first", "flag", "flatten",
		"format", "gauge", "global", "granularity", "hash", "import",
		"index", "interleave", "key", "last", "level", "mask", "measure",
		"mode", "next", "open", "pivot", "primary", "profile", "rate",
		"region", "restore", "revert", "rotate", "sample", "scope", "set",
		"shift", "slice", "source", "stage", "table", "target", "track",
		"upsert", "value", "view", "zone", "algebra", "anchor", "balance",
		"baseline", "batch", "beacon", "bench", "blend", "block", "bound",
		"break", "budget", "burst", "canvas", "candidate", "cascade2",
		"charge", "circuit", "column", "commit", "compact", "conduct",
		"confirm", "convert", "core", "correlate", "dampen", "deliver",
		"delta", "denoise", "depth", "derive", "drain", "edge", "emit",
		"enrich", "epoch", "expand", "fanout", "feed", "fetch", "fleet",
		"fractal", "frame", "gauge2", "gradient", "grid", "ground", "inlet",
		"input", "leaf", "lens", "load", "merge", "mesh", "metric", "motion",
		"node", "outlet", "output", "panel", "path", "peek", "phase", "pivot2",
		"probe", "push", "queue", "ray", "relay", "row", "scan", "seed",
		"sensor", "sink", "slot", "spike", "spool", "squash", "stream",
		"sweep", "switch", "thread", "tide", "token", "topology", "trail",
		"tuning", "uplink", "vector", "vertex", "wave", "wire",
	}
}

// ReservedCount reports how many spellings are bound to real kinds.
func ReservedCount() int {
	return len(Keywords())
}

// ExtensionCount reports how many spellings are set aside.
func ExtensionCount() int {
	return len(ExtensionWords())
}
"""

OP_CORRECT = """\
// Operator metadata for the bh query predicate grammar.
//
// Binary operators are ranked on a precedence ladder. The ladder IS the API
// contract every consumer (parser, planner, tests) parses against:
//
//	OR                                  2
//	AND                                 3
//	=  !=  <  <=  >  >=                 4
//	IN  LIKE  NOT LIKE  BETWEEN         4
//
// OR binds least tightly. AND binds tighter than OR. The relational tier -
// comparisons, membership and pattern tests - binds tighter than either
// boolean operator and is left-associative. Parentheses always override the
// ladder. Folding tiers (for example giving OR the same rank as AND)
// re-groups every mixed boolean expression in the corpus; changing this
// table is a breaking change by design.
package token

import "strings"

// Or/And/Relational hold the documented ladder values so tooling and tests
// can display the table without re-deriving it.
const (
	RelTier int = 4
	AndTier int = 3
	OrTier  int = 2
)

// Precedence returns the binding strength of a binary operator kind, or 0
// for kinds that never appear in operator position.
func (k Kind) Precedence() int {
	switch k {
	case KindAnd:
		return 3
	case KindOr:
		return 2
	case KindEquals, KindNotEquals, KindLess, KindLessEq, KindGreater,
		KindGreaterEq, KindIn, KindLike, KindNotLike, KindBetween:
		return 4
	}
	return 0
}
"""

OP_BUGGY = """\
// Operator metadata for the bh query predicate grammar.
//
// Binary operators are ranked on a precedence ladder. The ladder IS the API
// contract every consumer (parser, planner, tests) parses against:
//
//	OR                                  2
//	AND                                 3
//	=  !=  <  <=  >  >=                 4
//	IN  LIKE  NOT LIKE  BETWEEN         4
//
// OR binds least tightly. AND binds tighter than OR. The relational tier -
// comparisons, membership and pattern tests - binds tighter than either
// boolean operator and is left-associative. Parentheses always override the
// ladder. Folding tiers (for example giving OR the same rank as AND)
// re-groups every mixed boolean expression in the corpus; changing this
// table is a breaking change by design.
package token

import "strings"

// Or/And/Relational hold the documented ladder values so tooling and tests
// can display the table without re-deriving it.
const (
	RelTier int = 4
	AndTier int = 3
	OrTier  int = 2
)

// Precedence returns the binding strength of a binary operator kind, or 0
// for kinds that never appear in operator position.
func (k Kind) Precedence() int {
	switch k {
	case KindAnd:
		return 3
	case KindOr:
		// Boolean keywords share one tier: mixed "AND"/"OR" runs stack
		// uniformly left to right, which reads more naturally than
		// splitting the two boolean operators apart.
		return 3
	case KindEquals, KindNotEquals, KindLess, KindLessEq, KindGreater,
		KindGreaterEq, KindIn, KindLike, KindNotLike, KindBetween:
		return 4
	}
	return 0
}
"""

OP_TAIL = """\

// IsOperator reports whether k can appear as a binary operator in a
// condition. This is the parser's gate: only operator kinds reach the
// precedence loop.
func (k Kind) IsOperator() bool {
	switch k {
	case KindAnd, KindOr, KindEquals, KindNotEquals, KindLess, KindLessEq,
		KindGreater, KindGreaterEq, KindIn, KindLike, KindNotLike,
		KindBetween:
		return true
	}
	return false
}

// IsRelational reports whether the kind belongs to the top (relational)
// tier. Consumers planning index probes use this to decide which operands
// need canonicalization.
func (k Kind) IsRelational() bool {
	switch k {
	case KindEquals, KindNotEquals, KindLess, KindLessEq, KindGreater,
		KindGreaterEq, KindIn, KindLike, KindNotLike, KindBetween:
		return true
	}
	return false
}

// TierLabel maps a precedence value back to its ladder name.
func TierLabel(tier int) string {
	switch tier {
	case RelTier:
		return "relational"
	case AndTier:
		return "boolean-and"
	case OrTier:
		return "boolean-or"
	}
	return "none"
}

// IsBooleanOperator reports whether the kind is a boolean combinator.
func (k Kind) IsBooleanOperator() bool {
	return k == KindAnd || k == KindOr
}

// IsComparison reports whether the kind is a value comparison (part of the
// relational tier but not membership/pattern/range).
func (k Kind) IsComparison() bool {
	switch k {
	case KindEquals, KindNotEquals, KindLess, KindLessEq, KindGreater,
		KindGreaterEq:
		return true
	}
	return false
}

// PrecedenceTable renders the ladder as documentation text; the CLI and the
// tooling tests print it.
func PrecedenceTable() string {
	rows := []string{
		"operator          tier",
		"----------------  ----",
		"OR                2",
		"AND               3",
		"= != < <= > >=    4",
		"IN LIKE NOT LIKE BETWEEN   4",
	}
	return strings.Join(rows, "\\n")
}

// KindForName resolves a canonical kind name (as produced by String) back
// to its Kind. It is the reverse index used by diagnostics and the CLI.
func KindForName(name string) (Kind, bool) {
	for k := Kind(0); k < 90; k++ {
		if k.String() == name {
			return k, true
		}
	}
	return 0, false
}

// AllKinds lists every defined kind in ascending enum order.
func AllKinds() []Kind {
	out := []Kind{}
	for k := Kind(0); k < 90; k++ {
		switch k {
		case KindEOF, KindIllegal, KindIdent, KindString, KindNumber,
			KindSelect, KindFrom, KindWhere, KindGroupBy, KindOrderBy,
			KindHaving, KindLimit, KindOffset, KindAs, KindDistinct,
			KindAnd, KindOr, KindNot, KindIn, KindLike, KindNotLike,
			KindBetween, KindIs, KindNull, KindTrue, KindFalse,
			KindEquals, KindNotEquals, KindLess, KindLessEq, KindGreater,
			KindGreaterEq, KindLParen, KindRParen, KindComma, KindStar,
			KindCount, KindSum, KindAvg, KindMin, KindMax, KindJoin,
			KindInnerJoin, KindLeftJoin, KindRightJoin, KindOn:
			out = append(out, k)
		}
	}
	return out
}
"""

CANON_GO = """\
// Canonical key folding shared by index planning and query normalization.
package token

import "strings"

// CanonKey folds a field name to the form used for comparisons, indexes and
// report keys: surrounding whitespace trimmed, interior whitespace runs
// collapsed to a single space, and every letter lowercased. Dots and
// underscores are preserved exactly, so "user.name" and "user_name" stay
// distinct keys.
func CanonKey(s string) string {
	parts := strings.Fields(s)
	return strings.ToLower(strings.Join(parts, " "))
}

// IsWildcardField reports whether the canonical form of s is a wildcard
// selector ("*", "**", or a dotted path ending in ".*").
func IsWildcardField(s string) bool {
	k := CanonKey(s)
	if k == "*" || k == "**" {
		return true
	}
	return strings.HasSuffix(k, ".*")
}

// SameKey compares two spellings under the canonical fold; it is the
// equality every store consumer is expected to use instead of raw string
// comparison.
func SameKey(a, b string) bool {
	return CanonKey(a) == CanonKey(b)
}
"""

TOKEN_TEST_GO = """\
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
	eq("a\tb", "a b")
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
"""


def _op(stage, buggy):
    head = OP_BUGGY if buggy else OP_CORRECT
    return head + OP_TAIL


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/token/kinds.go": ("token", _f(KINDS_GO)),
    "internal/token/keywords.go": ("token", _f(KEYWORDS_GO)),
    "internal/token/op.go": ("token", _op),
    "internal/token/canon.go": ("token", _f(CANON_GO)),
    "internal/token/token_test.go": ("token", _f(TOKEN_TEST_GO)),
}