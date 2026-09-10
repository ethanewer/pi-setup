# internal/idx package, plus the planner hints added at stage "planner".

IDX_GO = """\
// Package idx provides canonical-key inverted indexes over store fields.
// Keys are folded with token.CanonKey at both write and probe time, so
// values written as "Edge Storage" and probed as "edge  storage" meet on
// the same entry. '*' acts as a run wildcard in probe keys.
package idx

import "bh/internal/store"
import "bh/internal/token"
import "strings"

// Index maps canonical keys of one field to the row numbers carrying them.
type Index struct {
	Field   string
	Entries map[string][]int
}

// New builds an empty index over field.
func New(field string) *Index {
	return &Index{ Field: field, Entries: map[string][]int{} }
}

// Add appends row to the entry list for the canonical form of key.
func (ix *Index) Add(key string, row int) {
	k := token.CanonKey(key)
	ix.Entries[k] = append(ix.Entries[k], row)
}

// Size returns the total number of index entries (posting count).
func (ix *Index) Size() int {
	total := 0
	for _, rows := range ix.Entries {
		total += len(rows)
	}
	return total
}

// Distinct returns the number of distinct canonical keys indexed.
func (ix *Index) Distinct() int {
	return len(ix.Entries)
}

// Coverage is the distinct/rows ratio, a cheap selectivity estimate.
func (ix *Index) Coverage(totalRows int) float64 {
	if totalRows <= 0 {
		return 0
	}
	return float64(ix.Distinct()) / float64(totalRows)
}

// Lookup returns the row numbers matching a canonical query key. A probe
// key containing '*' matches any run of characters; plain keys hit the
// exact entry. Results are sorted ascending for deterministic callers.
func (ix *Index) Lookup(key string) []int {
	want := token.CanonKey(key)
	if !strings.Contains(want, "*") {
		rows := ix.Entries[want]
		out := make([]int, len(rows))
		for i := 0; i < len(rows); i++ {
			out[i] = rows[i]
		}
		return out
	}
	out := []int{}
	for k, rows := range ix.Entries {
		if WildMatch(k, want) {
			out = append(out, rows...)
		}
	}
	sortInts(out)
	return out
}

// Empty reports whether the index carries no entries.
func (ix *Index) Empty() bool {
	return len(ix.Entries) == 0
}

// Clear empties the index, preserving the field name.
func (ix *Index) Clear() {
	ix.Entries = map[string][]int{}
}

// Has reports whether the exact canonical key is indexed.
func (ix *Index) Has(key string) bool {
	_, ok := ix.Entries[token.CanonKey(key)]
	return ok
}

// Rows returns the full posting list (all row numbers, sorted, unique),
// used for full-index scans.
func (ix *Index) Rows() []int {
	seen := map[int]bool{}
	out := []int{}
	for _, rows := range ix.Entries {
		for _, r := range rows {
			if !seen[r] {
				seen[r] = true
				out = append(out, r)
			}
		}
	}
	sortInts(out)
	return out
}

// Prefix returns the rows whose canonical key starts with the prefix.
func (ix *Index) Prefix(prefix string) []int {
	want := token.CanonKey(prefix)
	out := []int{}
	for k, rows := range ix.Entries {
		if strings.HasPrefix(k, want) {
			out = append(out, rows...)
		}
	}
	sortInts(out)
	return out
}

// Keys returns the canonical keys sorted ascending.
func (ix *Index) Keys() []string {
	out := make([]string, 0, len(ix.Entries))
	for k := range ix.Entries {
		out = append(out, k)
	}
	sortStrings(out)
	return out
}

// BuildIndex builds a value index over field of the store rows. Rows with an
// empty cell are not indexed.
func BuildIndex(s *store.RowStore, field string) *Index {
	ix := New(field)
	if s == nil {
		return ix
	}
	rows := s.Scan()
	for i, row := range rows {
		v := s.Cell(row, field)
		if v == "" {
			continue
		}
		ix.Add(v, i)
	}
	return ix
}

// WildMatch implements '*' as a run wildcard. It is the probing comparitor
// used by wildcard lookups.
func WildMatch(s, pat string) bool {
	i, j := 0, 0
	for j < len(pat) {
		if pat[j] == '*' {
			if j == len(pat)-1 {
				return true
			}
			for k := i; k <= len(s); k++ {
				if WildMatch(s[k:], pat[j+1:]) {
					return true
				}
			}
			return false
		}
		if i >= len(s) || s[i] != pat[j] {
			return false
		}
		i++
		j++
	}
	return i == len(s)
}

// sortInts sorts ascending in place (insertion sort; posting lists are
// short).
func sortInts(a []int) {
	for i := 1; i < len(a); i++ {
		for j := i; j > 0 && a[j] < a[j-1]; j-- {
			a[j], a[j-1] = a[j-1], a[j]
		}
	}
}

// sortStrings sorts ascending in place.
func sortStrings(a []string) {
	for i := 1; i < len(a); i++ {
		for j := i; j > 0 && a[j] < a[j-1]; j-- {
			a[j], a[j-1] = a[j-1], a[j]
		}
	}
}
"""

IDX_TEST_GO = """\
// Unit tests for the index.
package idx_test

import "bh/internal/idx"
import "bh/internal/store"
import "bh/internal/token"
import "testing"

func fixture(t *testing.T) *store.RowStore {
	s := store.New("devices", []string{"device", "label", "region"})
	s.Insert([]string{"alpha", "Edge Storage", "EUR"})
	s.Insert([]string{"beta-2", "Core", "US"})
	s.Insert([]string{"gamma", "Edge Storage", "US"})
	return s
}

func TestBuildAndSize(t *testing.T) {
	s := fixture(t)
	ix := idx.BuildIndex(s, "label")
	if ix.Distinct() != 2 {
		t.Errorf("Distinct = %d, want 2", ix.Distinct())
	}
	if ix.Size() != 3 {
		t.Errorf("Size = %d, want 3", ix.Size())
	}
	if got := token.CanonKey("edge storage"); got != "edge storage" {
		t.Errorf("canon = %q", got)
	}
}

func TestExactLookup(t *testing.T) {
	s := fixture(t)
	ix := idx.BuildIndex(s, "label")
	rows := ix.Lookup("edge storage")
	if len(rows) != 2 {
		t.Errorf("Lookup(edge storage) = %v, want 2 rows", rows)
	}
	if rows[0] != 0 || rows[1] != 2 {
		t.Errorf("Lookup row numbers = %v", rows)
	}
	if got := ix.Lookup("Core"); len(got) != 1 || got[0] != 1 {
		t.Errorf("Lookup(Core) = %v", got)
	}
	if got := ix.Lookup("nope"); len(got) != 0 {
		t.Errorf("Lookup(nope) = %v", got)
	}
}

func TestWildcardLookup(t *testing.T) {
	byIP := store.New("hosts", []string{"ip", "name"})
	byIP.Insert([]string{"10.0.0.1", "a"})
	byIP.Insert([]string{"10.0.0.2", "b"})
	byIP.Insert([]string{"192.168.1.5", "c"})
	ix := idx.BuildIndex(byIP, "ip")
	got := ix.Lookup("10.*")
	if len(got) != 2 {
		t.Errorf("Lookup(10.*) = %v, want 2", got)
	}
	if got := ix.Lookup("*"); len(got) != 3 {
		t.Errorf("Lookup(*) = %v, want 3", got)
	}
	if got := ix.Lookup("10.0.*"); len(got) != 2 {
		t.Errorf("mid wildcard = %v", got)
	}
}

func TestUnderscoreKeysStayDistinct(t *testing.T) {
	s := store.New("t", []string{"key", "v"})
	s.Insert([]string{"user_name", "1"})
	s.Insert([]string{"user.name", "1"})
	ix := idx.BuildIndex(s, "key")
	if ix.Distinct() != 2 {
		t.Errorf("user_name and user.name must stay distinct: %v", ix.Keys())
	}
	if got := ix.Lookup("User_Name"); len(got) != 1 || got[0] != 0 {
		t.Errorf("case-insensitive underscore lookup = %v", got)
	}
}

func TestEmptyClear(t *testing.T) {
	ix := idx.New("label")
	if !ix.Empty() {
		t.Errorf("fresh index must be empty")
	}
	ix.Add("a", 1)
	ix.Clear()
	if !ix.Empty() || ix.Size() != 0 {
		t.Errorf("Clear failed")
	}
}

func TestHasRowsPrefix(t *testing.T) {
	s := fixture(t)
	ix := idx.BuildIndex(s, "label")
	if !ix.Has("edge storage") || ix.Has("core storage") {
		t.Errorf("Has() wrong")
	}
	all := ix.Rows()
	if len(all) != 3 || all[0] != 0 || all[2] != 2 {
		t.Errorf("Rows = %v", all)
	}
	byIP := store.New("h", []string{"ip", "n"})
	byIP.Insert([]string{"10.0.0.1", "a"})
	byIP.Insert([]string{"10.0.0.2", "b"})
	byIP.Insert([]string{"192.168.1.5", "c"})
	ix2 := idx.BuildIndex(byIP, "ip")
	if got := ix2.Prefix("10."); len(got) != 2 {
		t.Errorf("Prefix(10.) = %v", got)
	}
}

func TestCoverageAndKeys(t *testing.T) {
	s := fixture(t)
	ix := idx.BuildIndex(s, "region")
	kv := ix.Keys()
	if len(kv) != 2 {
		t.Errorf("Keys = %v", kv)
	}
	if kv[0] != "eur" || kv[1] != "us" {
		t.Errorf("Keys order = %v", kv)
	}
	if got := ix.Coverage(s.Count()); got <= 0 || got > 1.1 {
		t.Errorf("Coverage = %v", got)
	}
}

func TestWildMatchInternal(t *testing.T) {
	ok := []struct{ s, p string }{
		{"abc", "abc"},
		{"abc", "*"},
		{"abc", "a*"},
		{"abc", "*c"},
		{"abc", "a*c"},
		{"abc", "a*b*c"},
		{"", "*"},
	}
	for _, c := range ok {
		if !idx.WildMatch(c.s, c.p) {
			t.Errorf("WildMatch(%q, %q) = false, want true", c.s, c.p)
		}
	}
	for _, c := range []struct{ s, p string }{
		{"abc", "ab"},
		{"abc", "b*"},
		{"abc", "a*bb"},
	} {
		if idx.WildMatch(c.s, c.p) {
			t.Errorf("WildMatch(%q, %q) = true, want false", c.s, c.p)
		}
	}
}
"""

PLANNER_GO = """\
// Planner hints. A Plan carries the decision whether an equality probe is
// served by an index and the expected candidate count. The query package
// consults these before falling back to a scan.
package idx

import "bh/internal/token"
import "strconv"
import "strings"

// Plan is one probe decision for an equality condition.
type Plan struct {
	Field     string // canonical field key
	Key       string // canonical probe key
	Indexed   bool
	Estimated int
}

// Suggest builds a probe plan for an equality on field with a literal
// value. The probe is indexed only when an index on the same canonical
// field exists and carries the exact key.
func Suggest(ix *Index, field string, value string) Plan {
	fkey := token.CanonKey(field)
	p := Plan{ Field: fkey, Key: token.CanonKey(value) }
	if ix == nil {
		return p
	}
	if token.CanonKey(ix.Field) != fkey {
		return p
	}
	rows := ix.Lookup(value)
	p.Indexed = len(rows) > 0
	p.Estimated = len(rows)
	return p
}

// Describe renders the plan for diagnostics: e.g.
// "indexed user.name=alice (~3)".
func (p Plan) Describe() string {
	if !p.Indexed {
		return "scan " + p.Field + "=" + p.Key
	}
	return "indexed " + p.Field + "=" + p.Key + " (~" + strconv.Itoa(p.Estimated) + ")"
}

// Recommend returns the candidate row numbers for an indexed plan, or nil
// when the plan is not indexed.
func (p Plan) Recommend(ix *Index) []int {
	if ix == nil || !p.Indexed {
		return nil
	}
	return ix.Lookup(p.Key)
}

// MatchWild picks the index best suited to a wildcard probe: the one whose
// key set overlaps the pattern most. Returns nil when none overlap.
func MatchWild(indexes []*Index, pattern string) *Index {
	want := token.CanonKey(pattern)
	if !strings.Contains(want, "*") {
		return nil
	}
	var best *Index
	bestHits := -1
	for _, ix := range indexes {
		hits := 0
		for k := range ix.Entries {
			if WildMatch(k, want) {
				hits++
			}
		}
		if hits > 0 && hits > bestHits {
			best = ix
			bestHits = hits
		}
	}
	return best
}
"""

PLANNER_TEST_GO = """\
// Unit tests for planner hints.
package idx_test

import "bh/internal/idx"
import "bh/internal/store"
import "testing"

func TestSuggestIndexed(t *testing.T) {
	s := store.New("u", []string{"name", "city"})
	s.Insert([]string{"alice", "berlin"})
	s.Insert([]string{"bob", "rome"})
	ix := idx.BuildIndex(s, "city")
	p := idx.Suggest(ix, "city", "berlin")
	if !p.Indexed {
		t.Errorf("plan not indexed: %s", p.Describe())
	}
	if p.Estimated != 1 {
		t.Errorf("estimate = %d", p.Estimated)
	}
	if got := p.Recommend(ix); len(got) != 1 || got[0] != 0 {
		t.Errorf("Recommend = %v", got)
	}
}

func TestSuggestMisses(t *testing.T) {
	s := store.New("u", []string{"name", "city"})
	s.Insert([]string{"alice", "berlin"})
	ix := idx.BuildIndex(s, "city")
	if p := idx.Suggest(ix, "city", "oslo"); p.Indexed {
		t.Errorf("missing key must not be indexed")
	}
	// different field -> scan
	if p := idx.Suggest(ix, "name", "alice"); p.Indexed {
		t.Errorf("wrong field must not be indexed")
	}
	if p := idx.Suggest(ix, "CITY", "BERLIN"); !p.Indexed {
		t.Errorf("canonical folding must align probe and index")
	}
	if p := idx.Suggest(nil, "city", "berlin"); p.Indexed {
		t.Errorf("nil index must scan")
	}
}

func TestMatchWild(t *testing.T) {
	a := store.New("a", []string{"ip", "v"})
	a.Insert([]string{"10.0.0.1", "x"})
	a.Insert([]string{"10.0.0.2", "y"})
	ia := idx.BuildIndex(a, "ip")
	b := store.New("b", []string{"ip6", "v"})
	b.Insert([]string{"fe80::1", "x"})
	ib := idx.BuildIndex(b, "ip6")
	got := idx.MatchWild([]*idx.Index{ib, ia}, "10.*")
	if got == nil || got.Field != "ip" {
		t.Errorf("MatchWild picked %v", got)
	}
	if got := idx.MatchWild([]*idx.Index{ib}, "10.*"); got != nil {
		t.Errorf("MatchWild must return nil when nothing overlaps")
	}
}
"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/idx/idx.go": ("idx", _f(IDX_GO)),
    "internal/idx/idx_test.go": ("idx", _f(IDX_TEST_GO)),
    "internal/idx/planner.go": ("planner", _f(PLANNER_GO)),
    "internal/idx/planner_test.go": ("planner", _f(PLANNER_TEST_GO)),
}