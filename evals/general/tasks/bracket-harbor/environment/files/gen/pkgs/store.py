# internal/store package. The typed accessor and numeric aggregate families
# are generated from TYPE_ROWS to keep the fixture's bulk plausible and
# uniform.

import string as _string

STORE_HEAD = """\
// Package store provides the fixed-schema, in-memory row store shared by the
// index, planner, query and report packages. Rows are a parallel pair of
// slices (fields, values); cells are text and typed accessors parse on
// demand, falling back to a caller-supplied default.
package store

import "strconv"
import "strings"

// Row is one record: a field list and matching values.
type Row struct {
	Fields []string
	Values []string
}

// RowStore is a named, fixed-schema table.
type RowStore struct {
	Name   string
	Fields []string
	Rows   []*Row
}

// New builds an empty store with the given schema.
func New(name string, fields []string) *RowStore {
	return &RowStore{ Name: name, Fields: fields, Rows: []*Row{} }
}

// Count returns the number of rows.
func (s *RowStore) Count() int {
	return len(s.Rows)
}

// FieldIndex returns the schema position of a field, or -1.
func (s *RowStore) FieldIndex(field string) int {
	for i, f := range s.Fields {
		if f == field {
			return i
		}
	}
	return -1
}

// HasField reports whether the schema lists the field.
func (s *RowStore) HasField(field string) bool {
	return s.FieldIndex(field) >= 0
}

// Insert appends a row if the value count matches the schema.
func (s *RowStore) Insert(values []string) bool {
	if len(values) != len(s.Fields) {
		return false
	}
	row := &Row{ Fields: s.Fields, Values: values }
	s.Rows = append(s.Rows, row)
	return true
}

// InsertMany inserts rows in bulk and returns how many were accepted.
func (s *RowStore) InsertMany(rows [][]string) int {
	if rows == nil {
		return 0
	}
	added := 0
	for _, r := range rows {
		if s.Insert(r) {
			added++
		}
	}
	return added
}

// Get fetches row by index. The bool reports presence.
func (s *RowStore) Get(i int) (*Row, bool) {
	if i < 0 || i >= len(s.Rows) {
		return nil, false
	}
	return s.Rows[i], true
}

// Scan materialises the current rows as a fresh slice.
func (s *RowStore) Scan() []*Row {
	return s.Rows
}

// Delete removes row i, shifting later rows left. Returns false when the
// index is out of range.
func (s *RowStore) Delete(i int) bool {
	if i < 0 || i >= len(s.Rows) {
		return false
	}
	out := make([]*Row, len(s.Rows)-1)
	for j := 0; j < i; j++ {
		out[j] = s.Rows[j]
	}
	for j := i; j < len(s.Rows)-1; j++ {
		out[j] = s.Rows[j+1]
	}
	s.Rows = out
	return true
}

// Cell returns the value for a field of a row, or "" when the field is
// absent. Field lookups honour the raw spelling.
func (s *RowStore) Cell(row *Row, field string) string {
	if row == nil {
		return ""
	}
	for i, f := range row.Fields {
		if f == field {
			return row.Values[i]
		}
	}
	return ""
}

// Values returns the column values for a field, in row order.
func (s *RowStore) Values(field string) []string {
	out := []string{}
	for _, row := range s.Rows {
		out = append(out, s.Cell(row, field))
	}
	return out
}

// Distinct returns the distinct values of a field in first-seen order.
func (s *RowStore) Distinct(field string) []string {
	out := []string{}
	for _, v := range s.Values(field) {
		seen := false
		for _, prev := range out {
			if prev == v {
				seen = true
			}
		}
		if !seen {
			out = append(out, v)
		}
	}
	return out
}

// Filter returns the rows for which pred is true.
func (s *RowStore) Filter(pred func(row *Row) bool) []*Row {
	out := []*Row{}
	for _, row := range s.Rows {
		if pred(row) {
			out = append(out, row)
		}
	}
	return out
}

// AppendFrom merges rows from another store, skipping rows whose value count
// does not match this store's schema. Returns the number merged.
func (s *RowStore) AppendFrom(other *RowStore) int {
	if other == nil {
		return 0
	}
	merged := 0
	for _, row := range other.Rows {
		if s.Insert(row.Values) {
			merged++
		}
	}
	return merged
}

"""

TYPE_ROWS = [
    # (type_name, go_type, zero_default, numeric, parse_stmt, body)
    ("Int64", "int64", "int64(0)", True,
     "n, err := strconv.ParseInt(v, 10, 64)",
     "if err != nil {\n\t\treturn def\n\t}\n\treturn n\n"),
    ("Uint64", "uint64", "uint64(0)", True,
     "n, err := strconv.ParseUint(v, 10, 64)",
     "if err != nil {\n\t\treturn def\n\t}\n\treturn n\n"),
    ("Float64", "float64", "0.0", True,
     "f, err := strconv.ParseFloat(v, 64)",
     "if err != nil {\n\t\treturn def\n\t}\n\treturn f\n"),
    ("Bool", "bool", "false", False,
     "b, err := strconv.ParseBool(v)",
     "if err != nil {\n\t\treturn def\n\t}\n\treturn b\n"),
    ("Text", "string", '""', False,
     "",
     "return v\n"),
]

ACCESSOR = """\
// Get$Type returns the value of field for row parsed as $go, falling back
// to def on missing cells, empty strings and parse failures.
func (s *RowStore) Get$Type(row *Row, field string, def $go) $go {
	if row == nil {
		return def
	}
	v := s.Cell(row, field)
	if v == "" {
		return def
	}
$body}\n"""

AGGREGATE = """\
// Sum$Type sums the numeric value of field across all rows; rows that do
// not parse as a number contribute zero.
func (s *RowStore) Sum$Type(field string) $go {
	total := $zero
	for _, row := range s.Rows {
		total += s.Get$Type(row, field, $zero)
	}
	return total
}

// Max$Type returns the largest numeric value of field, or def when there
// are no rows.
func (s *RowStore) Max$Type(field string, def $go) $go {
	best := def
	first := true
	for _, row := range s.Rows {
		v := s.Get$Type(row, field, $zero)
		if first || v > best {
			best = v
		}
		first = false
	}
	return best
}

// Min$Type returns the smallest numeric value of field, or def when there
// are no rows.
func (s *RowStore) Min$Type(field string, def $go) $go {
	best := def
	first := true
	for _, row := range s.Rows {
		v := s.Get$Type(row, field, $zero)
		if first || v < best {
			best = v
		}
		first = false
	}
	return best
}

"""

STORE_TAIL = """\
// CountOf counts rows whose field equals want (string compare).
func (s *RowStore) CountOf(field string, want string) int {
	n := 0
	for _, row := range s.Rows {
		if s.Cell(row, field) == want {
			n++
		}
	}
	return n
}

// Paginate returns the rows of one page (1-based page number).
func (s *RowStore) Paginate(page, size int) []*Row {
	if page < 1 || size <= 0 {
		return []*Row{}
	}
	from := (page - 1) * size
	return s.Slice(from, from+size)
}

// Slice returns rows [from, to).
func (s *RowStore) Slice(from, to int) []*Row {
	if from < 0 {
		from = 0
	}
	if to > len(s.Rows) {
		to = len(s.Rows)
	}
	out := []*Row{}
	for i := from; i < to; i++ {
		out = append(out, s.Rows[i])
	}
	return out
}

// Top returns the first n rows.
func (s *RowStore) Top(n int) []*Row {
	return s.Slice(0, n)
}

// CountNonempty counts rows where field has a non-empty value.
func (s *RowStore) CountNonempty(field string) int {
	n := 0
	for _, row := range s.Rows {
		if s.Cell(row, field) != "" {
			n++
		}
	}
	return n
}

// PickIndex returns the row number of the first row whose field equals
// want, or -1.
func (s *RowStore) PickIndex(field string, want string) int {
	for i, row := range s.Rows {
		if s.Cell(row, field) == want {
			return i
		}
	}
	return -1
}

// RenameField renames a schema field, carrying the change through the
// field lists of every row. Returns false when the name is not present.
func (s *RowStore) RenameField(oldName, newName string) bool {
	idx := s.FieldIndex(oldName)
	if idx < 0 {
		return false
	}
	s.Fields[idx] = newName
	for _, row := range s.Rows {
		row.Fields[idx] = newName
	}
	return true
}

// Describe renders a one-line schema summary, e.g. "t(a, b, c)".
func (s *RowStore) Describe() string {
	if s == nil {
		return "<nil>"
	}
	return s.Name + "(" + strings.Join(s.Fields, ", ") + ")"
}

// SortRowsBy returns a copy of rows ordered by the values of field. The
// comparison is numeric when both sides parse as numbers, lexicographic
// otherwise.
func (s *RowStore) SortRowsBy(rows []*Row, field string) []*Row {
	out := make([]*Row, len(rows))
	for i := 0; i < len(rows); i++ {
		out[i] = rows[i]
	}
	for i := 1; i < len(out); i++ {
		for j := i; j > 0; j-- {
			if numLess(s.Cell(out[j], field), s.Cell(out[j-1], field)) {
				out[j], out[j-1] = out[j-1], out[j]
			}
		}
	}
	return out
}

func numLess(a, b string) bool {
	af, aok := parseFloatSafe(a)
	bf, bok := parseFloatSafe(b)
	if aok && bok {
		return af < bf
	}
	return a < b
}

func parseFloatSafe(v string) (float64, bool) {
	if v == "" {
		return 0, false
	}
	f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
	return f, err == nil
}

"""


def _accessors():
    parts = []
    for typ, go, zero, numeric, stmt, body in TYPE_ROWS:
        if stmt == "":
            body = "\treturn v\n"
        else:
            body = "\t" + stmt + "\n\tif err != nil {\n\t\treturn def\n\t}\n\t" + body
        tpl = _string.Template(ACCESSOR)
        parts.append(tpl.substitute(Type=typ, go=go, body=body))
    return "".join(parts)


def _aggregates():
    parts = []
    for typ, go, zero, numeric, _, _ in TYPE_ROWS:
        if not numeric:
            continue
        tpl = _string.Template(AGGREGATE)
        parts.append(tpl.substitute(Type=typ, go=go, zero=zero))
    return "".join(parts)


def _store(stage, buggy):
    return STORE_HEAD + _accessors() + STORE_TAIL + _aggregates()


STORE_TEST_GO = """\
// Unit tests for the row store.
package store_test

import "bh/internal/store"
import "testing"

func TestInsertAndCount(t *testing.T) {
	s := store.New("events", []string{"a", "b"})
	if s.Count() != 0 {
		t.Errorf("fresh store count = %d", s.Count())
	}
	if !s.Insert([]string{"1", "x"}) {
		t.Errorf("insert with matching arity must succeed")
	}
	if s.Insert([]string{"2"}) {
		t.Errorf("insert with wrong arity must fail")
	}
	if s.Count() != 1 {
		t.Errorf("count = %d, want 1", s.Count())
	}
	if got := s.InsertMany([][]string{
		{"2", "y"}, {"3", "z"}, {"4", "w"},
	}); got != 3 {
		t.Errorf("InsertMany merged %d, want 3", got)
	}
	if s.Count() != 4 {
		t.Errorf("count = %d, want 4", s.Count())
	}
}

func TestCellAndAccessors(t *testing.T) {
	s := store.New("t", []string{"id", "score", "ok", "label"})
	s.Insert([]string{"7", "3.50", "true", "alpha"})
	row, ok := s.Get(0)
	if !ok {
		t.Errorf("row 0 missing")
	}
	if got := s.Cell(row, "id"); got != "7" {
		t.Errorf("Cell(id) = %q", got)
	}
	if got := s.GetInt64(row, "id", 0); got != 7 {
		t.Errorf("GetInt64 = %d", got)
	}
	if got := s.GetFloat64(row, "score", 0); got != 3.5 {
		t.Errorf("GetFloat64 = %v", got)
	}
	if !s.GetBool(row, "ok", false) {
		t.Errorf("GetBool = false")
	}
	if got := s.GetText(row, "label", ""); got != "alpha" {
		t.Errorf("GetText = %q", got)
	}
	if got := s.GetInt64(row, "missing", 9); got != 9 {
		t.Errorf("missing field default = %d", got)
	}
	s.Insert([]string{"nope", "x", "no", ""})
	other, ok := s.Get(1)
	if !ok {
		t.Errorf("row 1 missing")
	}
	if got := s.GetInt64(other, "id", 3); got != 3 {
		t.Errorf("unparsable default = %d", got)
	}
}

func TestAggregates(t *testing.T) {
	s := store.New("n", []string{"v", "t"})
	s.Insert([]string{"10", "a"})
	s.Insert([]string{"20", "b"})
	s.Insert([]string{"30", "c"})
	if got := s.SumInt64("v"); got != 60 {
		t.Errorf("SumInt64 = %d", got)
	}
	if got := s.MaxInt64("v", 0); got != 30 {
		t.Errorf("MaxInt64 = %d", got)
	}
	if got := s.MinInt64("v", 0); got != 10 {
		t.Errorf("MinInt64 = %d", got)
	}
	if got := s.SumFloat64("v"); got != 60.0 {
		t.Errorf("SumFloat64 = %v", got)
	}
	if got := s.CountOf("t", "b"); got != 1 {
		t.Errorf("CountOf = %d", got)
	}
	empty := store.New("n", []string{"v"})
	if got := empty.MaxInt64("v", 5); got != 5 {
		t.Errorf("empty MaxInt64 default = %d", got)
	}
}

func TestDistinctFilterDelete(t *testing.T) {
	s := store.New("t", []string{"k", "v"})
	s.Insert([]string{"a", "1"})
	s.Insert([]string{"b", "2"})
	s.Insert([]string{"a", "3"})
	ds := s.Distinct("k")
	if len(ds) != 2 || ds[0] != "a" || ds[1] != "b" {
		t.Errorf("Distinct(k) = %v", ds)
	}
	f := s.Filter(func(row *store.Row) bool { return row.Values[0] == "a" })
	if len(f) != 2 {
		t.Errorf("Filter count = %d", len(f))
	}
	if got := s.PickIndex("k", "b"); got != 1 {
		t.Errorf("PickIndex(b) = %d", got)
	}
	if !s.Delete(1) || s.Count() != 2 {
		t.Errorf("Delete failed")
	}
	if got := s.PickIndex("k", "b"); got != -1 {
		t.Errorf("deleted row still present at %d", got)
	}
	if len(s.Top(1)) != 1 {
		t.Errorf("Top(1) wrong size")
	}
}

func TestPaginate(t *testing.T) {
	s := store.New("t", []string{"v"})
	for i := 0; i < 7; i++ {
		s.Insert([]string{"r"})
	}
	if got := len(s.Paginate(2, 3)); got != 3 {
		t.Errorf("page 2 size = %d", got)
	}
	if got := len(s.Paginate(3, 3)); got != 1 {
		t.Errorf("last page size = %d", got)
	}
	if got := len(s.Paginate(0, 3)); got != 0 {
		t.Errorf("page 0 must be empty")
	}
	if got := len(s.Paginate(2, 0)); got != 0 {
		t.Errorf("size 0 must be empty")
	}
	if got := s.GetUint64(nil, "v", 5); got != 5 {
		t.Errorf("GetUint64 default = %d", got)
	}
	if got := s.SumUint64("v"); got != 0 {
		t.Errorf("SumUint64 = %d", got)
	}
}

func TestRenameAndDescribe(t *testing.T) {
	s := store.New("t", []string{"a", "b"})
	s.Insert([]string{"1", "x"})
	if !s.RenameField("a", "aa") {
		t.Errorf("rename failed")
	}
	if s.RenameField("zz", "q") {
		t.Errorf("unknown field rename must fail")
	}
	if got := s.Describe(); got != "t(aa, b)" {
		t.Errorf("Describe = %q", got)
	}
	row, _ := s.Get(0)
	if got := s.Cell(row, "aa"); got != "1" {
		t.Errorf("cell after rename = %q", got)
	}
}

func TestAppendFrom(t *testing.T) {
	s := store.New("a", []string{"x", "y"})
	s.Insert([]string{"1", "2"})
	other := store.New("b", []string{"x", "y"})
	other.Insert([]string{"3", "4"})
	other.Insert([]string{"5"})
	if got := s.AppendFrom(other); got != 1 {
		t.Errorf("AppendFrom merged %d, want 1", got)
	}
	if s.Count() != 2 {
		t.Errorf("count = %d", s.Count())
	}
	row, ok := s.Get(1)
	if !ok || s.Cell(row, "x") != "3" {
		t.Errorf("merged row is not the expected one")
	}
}

func TestSortRows(t *testing.T) {
	s := store.New("t", []string{"v", "tag"})
	s.Insert([]string{"30", "a"})
	s.Insert([]string{"10", "b"})
	s.Insert([]string{"20", "c"})
	rows := s.SortRowsBy(s.Scan(), "v")
	if s.Cell(rows[0], "v") != "10" || s.Cell(rows[2], "v") != "30" {
		t.Errorf("numeric sort broken: %v", rows)
	}
}

"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/store/store.go": ("store", _store),
    "internal/store/store_test.go": ("store", _f(STORE_TEST_GO)),
}