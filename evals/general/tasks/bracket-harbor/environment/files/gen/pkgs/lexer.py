# internal/lexer package.

LEXER_GO = """\
// Package lexer tokenizes bh query source into a token stream terminated by
// an end-of-input marker. Keywords are resolved case-insensitively through
// the reserved-word table; identifiers that do not resolve stay field names.
package lexer

import "bh/internal/token"
import "strconv"

// Lex converts src into a slice of tokens ending with a KindEOF marker. The
// second result is an error message, empty on success.
func Lex(src string) ([]token.Token, string) {
	ts := make([]token.Token, 0, 32)
	n := len(src)
	i := 0
	for i < n {
		c := src[i]
		switch {
		case c == ' ' || c == '\\t' || c == '\\n' || c == '\\r':
			i++
		case c == '#':
			// A '#' comment runs to the end of the line; query files may
			// carry them as documentation.
			for i < n && src[i] != '\\n' {
				i++
			}
		case isAlpha(c):
			start := i
			for i < n && isWordChar(src[i]) {
				i++
			}
			lit := src[start:i]
			kind := token.KindIdent
			if w, ok := token.LookupIdent(lit); ok {
				kind = w
			}
			ts = append(ts, token.New(kind, lit, start))
		case isDigit(c):
			start := i
			for i < n && (isDigit(src[i]) || src[i] == '.') {
				i++
			}
			ts = append(ts, token.New(token.KindNumber, src[start:i], start))
		case c == '\\'' || c == '"':
			q := c
			start := i
			i++
			for i < n && src[i] != q {
				i++
			}
			if i >= n {
				return nil, "unterminated string literal at offset " + strconv.Itoa(start)
			}
			i++
			ts = append(ts, token.New(token.KindString, src[start+1:i-1], start))
		case c == '-' && i+1 < n && isDigit(src[i+1]):
			start := i
			i++
			for i < n && (isDigit(src[i]) || src[i] == '.') {
				i++
			}
			ts = append(ts, token.New(token.KindNumber, src[start:i], start))
		case c == '=':
			ts = append(ts, token.New(token.KindEquals, "=", i))
			i++
		case c == '!' && i+1 < n && src[i+1] == '=':
			ts = append(ts, token.New(token.KindNotEquals, "!=", i))
			i += 2
		case c == '<':
			if i+1 < n && src[i+1] == '=' {
				ts = append(ts, token.New(token.KindLessEq, "<=", i))
				i += 2
			} else {
				ts = append(ts, token.New(token.KindLess, "<", i))
				i++
			}
		case c == '>':
			if i+1 < n && src[i+1] == '=' {
				ts = append(ts, token.New(token.KindGreaterEq, ">=", i))
				i += 2
			} else {
				ts = append(ts, token.New(token.KindGreater, ">", i))
				i++
			}
		case c == '(':
			ts = append(ts, token.New(token.KindLParen, "(", i))
			i++
		case c == ')':
			ts = append(ts, token.New(token.KindRParen, ")", i))
			i++
		case c == ',':
			ts = append(ts, token.New(token.KindComma, ",", i))
			i++
		case c == '*':
			ts = append(ts, token.New(token.KindStar, "*", i))
			i++
		default:
			return nil, "unexpected character " + string(c) + " at offset " + strconv.Itoa(i)
		}
	}
	ts = append(ts, token.New(token.KindEOF, "", n))
	return ts, ""
}

// LexCount returns the number of non-EOF tokens produced by Lex.
func LexCount(src string) (int, string) {
	ts, errs := Lex(src)
	if errs != "" {
		return 0, errs
	}
	return len(ts) - 1, ""
}

// NonEOF strips the trailing end-of-input marker from a token stream.
func NonEOF(ts []token.Token) []token.Token {
	out := []token.Token{}
	for _, t := range ts {
		if t.Kind == token.KindEOF {
			continue
		}
		out = append(out, t)
	}
	return out
}

// FirstOf returns the first token of the given kind and its position in the
// stream, or -1 when absent. It is the lexer-side scan helper for
// statement-level clauses.
func FirstOf(ts []token.Token, k token.Kind) int {
	for i, t := range ts {
		if t.Kind == k {
			return i
		}
	}
	return -1
}

// LastOffset returns the source offset past the final character consumed.
func LastOffset(ts []token.Token) int {
	if len(ts) == 0 {
		return 0
	}
	last := ts[len(ts)-1]
	return last.Pos + len(last.Lit)
}

// Contains reports whether the stream holds a token of the given kind.
func Contains(ts []token.Token, k token.Kind) bool {
	return FirstOf(ts, k) >= 0
}

func isAlpha(c byte) bool {
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'
}

func isDigit(c byte) bool {
	return c >= '0' && c <= '9'
}

// isWordChar describes the letters that may appear inside a field name:
// letters, digits, underscores, dots, dashes and dollar signs. Keywords are
// resolved after the whole run is read, so "user.name" lexes as one ident.
func isWordChar(c byte) bool {
	return isAlpha(c) || isDigit(c) || c == '_' || c == '.' || c == '-' || c == '$'
}
"""

LEXER_TEST_GO = """\
// Unit tests for the lexer.
package lexer_test

import "bh/internal/lexer"
import "bh/internal/token"
import "testing"

func kinds(src string, t *testing.T) []token.Kind {
	ts, errs := lexer.Lex(src)
	if errs != "" {
		t.Fatalf("Lex(%q) failed: %s", src, errs)
	}
	ks := []token.Kind{}
	for _, to := range ts {
		ks = append(ks, to.Kind)
	}
	return ks
}

func sameKinds(got, want []token.Kind, t *testing.T) {
	if len(got) != len(want) {
		t.Fatalf("token count = %d, want %d (%v)", len(got), len(want), got)
	}
	for i := 0; i < len(want); i++ {
		if got[i] != want[i] {
			t.Errorf("token %d kind = %d, want %d", i, got[i], want[i])
		}
	}
}

func TestSimpleCondition(t *testing.T) {
	ks := kinds("p = 1 OR q = 2", t)
	sameKinds(ks, []token.Kind{
		token.KindIdent, token.KindEquals, token.KindNumber,
		token.KindOr, token.KindIdent, token.KindEquals, token.KindNumber,
		token.KindEOF,
	}, t)
}

func TestKeywordsCaseInsensitive(t *testing.T) {
	ks := kinds("SELECT a FROM t WHERE a = 1", t)
	sameKinds(ks, []token.Kind{
		token.KindSelect, token.KindIdent, token.KindFrom, token.KindIdent,
		token.KindWhere, token.KindIdent, token.KindEquals, token.KindNumber,
		token.KindEOF,
	}, t)
}

func TestLowercaseKeywords(t *testing.T) {
	ks := kinds("a = 1 and b < 2 or c in (3, 4)", t)
	sameKinds(ks, []token.Kind{
		token.KindIdent, token.KindEquals, token.KindNumber, token.KindAnd,
		token.KindIdent, token.KindLess, token.KindNumber, token.KindOr,
		token.KindIdent, token.KindIn, token.KindLParen, token.KindNumber,
		token.KindComma, token.KindNumber, token.KindRParen, token.KindEOF,
	}, t)
}

func TestFieldNamesWithPunctuation(t *testing.T) {
	ts, err := lexer.Lex("user.name = 'a' AND x_y = 2")
	if err != "" {
		t.Fatalf("Lex failed: %s", err)
	}
	got := token.Dump(ts)
	for _, want := range []string{"ident('user.name')", "ident('x_y')"} {
		if !stringsContains(got, want) {
			t.Errorf("dump missing %q in %q", want, got)
		}
	}
}

func stringsContains(hay, needle string) bool {
	for i := 0; i+len(needle) <= len(hay); i++ {
		if hay[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}

func TestStringLiterals(t *testing.T) {
	ts, errs := lexer.Lex("name = 'john doe'")
	if errs != "" {
		t.Fatalf("unexpected error: %s", errs)
	}
	if len(ts) < 3 || ts[2].Lit != "john doe" {
		t.Errorf("string literal = %q, want 'john doe'", ts[2].Lit)
	}
	if ts[2].Kind != token.KindString {
		t.Errorf("kind = %d, want KindString", ts[2].Kind)
	}
}

func TestNegativeNumbers(t *testing.T) {
	ts, errs := lexer.Lex("x = -7")
	if errs != "" {
		t.Fatalf("unexpected error: %s", errs)
	}
	if ts[2].Kind != token.KindNumber || ts[2].Lit != "-7" {
		t.Errorf("negative literal = (%d, %q)", ts[2].Kind, ts[2].Lit)
	}
}

func TestComments(t *testing.T) {
	ts, errs := lexer.Lex("# a comment\\np = 1")
	if errs != "" {
		t.Fatalf("unexpected error: %s", errs)
	}
	ks := []token.Kind{}
	for _, to := range ts {
		ks = append(ks, to.Kind)
	}
	sameKinds(ks, []token.Kind{
		token.KindIdent, token.KindEquals, token.KindNumber, token.KindEOF,
	}, t)
}

func TestHelperScans(t *testing.T) {
	if n, errs := lexer.LexCount("a = 1"); errs != "" || n != 3 {
		t.Errorf("LexCount = %d, %q", n, errs)
	}
	ts, _ := lexer.Lex("a = 1")
	if len(lexer.NonEOF(ts)) != 3 {
		t.Errorf("NonEOF count wrong")
	}
	if got := lexer.FirstOf(ts, token.KindEquals); got != 1 {
		t.Errorf("FirstOf(equals) = %d", got)
	}
	if lexer.Contains(ts, token.KindAnd) {
		t.Errorf("Contains(and) false positive")
	}
	if !lexer.Contains(ts, token.KindNumber) {
		t.Errorf("Contains(number) missed")
	}
	if got := lexer.LastOffset(ts); got != 5 {
		t.Errorf("LastOffset = %d, want 5", got)
	}
}

func TestErrors(t *testing.T) {
	if _, errs := lexer.Lex("p = 'unterminated"); errs == "" {
		t.Errorf("unterminated string should fail")
	}
	if _, errs := lexer.Lex("p = 1 @ q"); errs == "" {
		t.Errorf("stray '@' should fail")
	}
	if ts, errs := lexer.Lex("&"); errs == "" || len(ts) != 0 {
		t.Errorf("'&' should fail and produce no tokens")
	}
}
"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/lexer/lexer.go": ("lexer", _f(LEXER_GO)),
    "internal/lexer/lexer_test.go": ("lexer", _f(LEXER_TEST_GO)),
}