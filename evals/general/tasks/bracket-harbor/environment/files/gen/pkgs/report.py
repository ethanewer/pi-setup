# internal/report package, plus the alignment option added at stage
# "reportal".

REPORT_GO = """\
// Package report renders store results: aligned text tables, totals rows
// and a CSV projection. Rendering is deterministic for a given store, which
// is what lets tests compare exact layouts.
package report

import "bh/internal/store"
import "strconv"
import "strings"

// Options controls rendering.
type Options struct {
	AlignRight bool
	ShowTotals bool
	Width      int
}

// Defaults returns the base options used by the CLI.
func Defaults() Options {
	return Options{ AlignRight: false, ShowTotals: true, Width: 24 }
}

// ColumnWidths computes per-column render widths, capped at o.Width.
func (o Options) ColumnWidths(s *store.RowStore) []int {
	widths := []int{}
	if s == nil {
		return widths
	}
	for i, f := range s.Fields {
		best := len(f)
		if i == 0 && o.ShowTotals && len("total") > best {
			best = len("total")
		}
		rows := s.Scan()
		for _, row := range rows {
			if i < len(row.Values) && len(row.Values[i]) > best {
				best = len(row.Values[i])
			}
			if best > o.Width {
				best = o.Width
			}
		}
		widths = append(widths, best)
	}
	return widths
}

// Pad renders a cell to the given width inside its column, honouring the
// alignment option.
func (o Options) Pad(cell string, width int) string {
	if len(cell) >= width {
		return cell[:width]
	}
	pad := strings.Repeat(" ", width-len(cell))
	if o.AlignRight {
		return pad + cell
	}
	return cell + pad
}

// Render builds the aligned table: a header line, a rule, one line per row
// and an optional totals line.
func (o Options) Render(s *store.RowStore) string {
	if s == nil {
		return ""
	}
	widths := o.ColumnWidths(s)
	lines := []string{}
	hdr := ""
	for i, f := range s.Fields {
		if i > 0 {
			hdr += " | "
		}
		hdr += o.Pad(f, widths[i])
	}
	lines = append(lines, hdr)
	lines = append(lines, strings.Repeat("-", len(hdr)))
	for _, row := range s.Scan() {
		line := ""
		for i := range s.Fields {
			if i > 0 {
				line += " | "
			}
			cell := ""
			if i < len(row.Values) {
				cell = row.Values[i]
			}
			line += o.Pad(cell, widths[i])
		}
		lines = append(lines, line)
	}
	if o.ShowTotals {
		lines = append(lines, o.totalsLine(s, widths))
	}
	return strings.Join(lines, "\\n")
}

// totalsLine renders the numeric column sums, or "-" for non-numeric
// columns.
func (o Options) totalsLine(s *store.RowStore, widths []int) string {
	line := ""
	for i, f := range s.Fields {
		if i > 0 {
			line += " | "
		}
		if i == 0 {
			line += o.Pad("total", widths[i])
			continue
		}
		total, ok := numericTotal(s, f)
		if !ok {
			line += o.Pad("-", widths[i])
			continue
		}
		line += o.Pad(strconv.FormatFloat(total, 'G', 6, 64), widths[i])
	}
	return line
}

// numericTotal sums a numeric column and reports whether the column was
// entirely numeric.
func numericTotal(s *store.RowStore, field string) (float64, bool) {
	total := 0.0
	any := false
	for _, row := range s.Scan() {
		v := s.Cell(row, field)
		if v == "" {
			continue
		}
		f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
		if err != nil {
			return 0, false
		}
		total += f
		any = true
	}
	return total, any
}

// RenderMarkdown emits a github-flavoured table with the same cells.
func (o Options) RenderMarkdown(s *store.RowStore) string {
	if s == nil {
		return ""
	}
	widths := o.ColumnWidths(s)
	lines := []string{}
	hdr := ""
	for i, f := range s.Fields {
		if i > 0 {
			hdr += " | "
		}
		hdr += o.Pad(f, widths[i])
	}
	lines = append(lines, "| " + hdr + " |")
	ruleCells := []string{}
	for _, w := range widths {
		ruleCells = append(ruleCells, strings.Repeat("-", w))
	}
	lines = append(lines, "| " + strings.Join(ruleCells, " | ") + " |")
	for _, row := range s.Scan() {
		cells := make([]string, len(s.Fields))
		for i := range s.Fields {
			if i < len(row.Values) {
				cells[i] = o.Pad(row.Values[i], widths[i])
			} else {
				cells[i] = o.Pad("", widths[i])
			}
		}
		lines = append(lines, "| " + strings.Join(cells, " | ") + " |")
	}
	return strings.Join(lines, "\\n")
}

// RenderCsv emits a CSV projection with an optional totals row.
func (o Options) RenderCsv(s *store.RowStore) string {
	if s == nil {
		return ""
	}
	lines := []string{}
	cols := make([]string, len(s.Fields))
	for i, f := range s.Fields {
		cols[i] = csvEscape(f)
	}
	lines = append(lines, strings.Join(cols, ","))
	for _, row := range s.Scan() {
		cells := make([]string, len(s.Fields))
		for i := range s.Fields {
			cell := ""
			if i < len(row.Values) {
				cell = row.Values[i]
			}
			cells[i] = csvEscape(cell)
		}
		lines = append(lines, strings.Join(cells, ","))
	}
	if o.ShowTotals {
		tcols := make([]string, len(s.Fields))
		for i, f := range s.Fields {
			if i == 0 {
				tcols[i] = "total"
				continue
			}
			if total, ok := numericTotal(s, f); ok {
				tcols[i] = strconv.FormatFloat(total, 'G', 6, 64)
			} else {
				tcols[i] = "-"
			}
		}
		lines = append(lines, strings.Join(tcols, ","))
	}
	return strings.Join(lines, "\\n")
}

func csvEscape(v string) string {
	if strings.ContainsAny(v, ",\\"\\n") {
		return "\\"" + strings.ReplaceAll(v, "\\"", "\\"\\"") + "\\""
	}
	return v
}
"""

REPORT_TEST_GO = """\
// Unit tests for the report renderer.
package report_test

import "bh/internal/report"
import "bh/internal/store"
import "strings"
import "testing"

func sample() *store.RowStore {
	s := store.New("t", []string{"name", "score"})
	s.Insert([]string{"alpha", "10"})
	s.Insert([]string{"beta", "20"})
	s.Insert([]string{"gamma", "30"})
	return s
}

func TestRenderBasics(t *testing.T) {
	o := report.Defaults()
	out := o.Render(sample())
	lines := strings.Split(out, "\\n")
	if len(lines) != 6 {
		t.Fatalf("table has %d lines, want 6:\\n%s", len(lines), out)
	}
	if !strings.Contains(lines[0], "name") || !strings.Contains(lines[0], "score") {
		t.Errorf("header wrong: %q", lines[0])
	}
	if !strings.Contains(lines[1], "-") {
		t.Errorf("rule missing")
	}
	if !strings.Contains(out, "alpha") || !strings.Contains(out, "gamma") {
		t.Errorf("rows missing")
	}
	if !strings.Contains(out, "total") {
		t.Errorf("totals row missing")
	}
}

func TestRenderTotalsValue(t *testing.T) {
	o := report.Defaults()
	out := o.Render(sample())
	if !strings.Contains(out, "60") {
		t.Errorf("numeric total 60 missing in:\\n%s", out)
	}
}

func TestNoTotals(t *testing.T) {
	o := report.Defaults()
	o.ShowTotals = false
	out := o.Render(sample())
	if strings.Contains(out, "total") {
		t.Errorf("totals must be omitted when disabled")
	}
}

func TestColumnCaps(t *testing.T) {
	o := report.Defaults()
	o.Width = 3
	out := o.Render(sample())
	if strings.Contains(out, "alpha") {
		t.Errorf("cell must be truncated to the column cap")
	}
}

func TestCsv(t *testing.T) {
	o := report.Defaults()
	out := o.RenderCsv(sample())
	lines := strings.Split(out, "\\n")
	if len(lines) != 5 {
		t.Fatalf("csv has %d lines:\\n%s", len(lines), out)
	}
	if lines[0] != "name,score" {
		t.Errorf("csv header = %q", lines[0])
	}
	if lines[1] != "alpha,10" {
		t.Errorf("csv row = %q", lines[1])
	}
	if lines[4] != "total,60" {
		t.Errorf("csv totals = %q", lines[4])
	}
}

func TestCsvEscaping(t *testing.T) {
	s := store.New("t", []string{"v"})
	s.Insert([]string{"a,b"})
	o := report.Defaults()
	o.ShowTotals = false
	out := o.RenderCsv(s)
	if !strings.Contains(out, "\\"a,b\\"") {
		t.Errorf("csv escaping broken: %q", out)
	}
}

func TestRenderMarkdown(t *testing.T) {
	o := report.Defaults()
	out := o.RenderMarkdown(sample())
	if !strings.HasPrefix(out, "| name") {
		t.Errorf("markdown header wrong: %q", out)
	}
	if !strings.Contains(out, "---") {
		t.Errorf("markdown rule missing")
	}
	if !strings.Contains(out, "| alpha") {
		t.Errorf("markdown row missing")
	}
}

func TestNilStore(t *testing.T) {
	o := report.Defaults()
	if got := o.Render(nil); got != "" {
		t.Errorf("nil store renders %q", got)
	}
}
"""

ALIGN_GO = """\
// Alignment helpers for the table renderer, added with the alignment cap
// option.
package report

import "bh/internal/store"
import "strings"

// Align is a column alignment position.
type Align string

// Alignment positions.
const (
	Left  Align = "left"
	Right Align = "right"
)

// ValidAlign reports whether the alignment is a known position.
func ValidAlign(a Align) bool {
	return a == Left || a == Right
}

// Justify pads s to width using align.
func Justify(s string, width int, align Align) string {
	if len(s) >= width {
		return s
	}
	pad := strings.Repeat(" ", width-len(s))
	if align == Right {
		return pad + s
	}
	return s + pad
}

// TableAlign derives per-column alignments: numeric columns right-justified,
// text columns left-justified. When force is valid it overrides the
// per-column choice.
func TableAlign(s *store.RowStore, force Align) []Align {
	out := []Align{}
	if s == nil {
		return out
	}
	for _, f := range s.Fields {
		a := Left
		if columnNumeric(s, f) {
			a = Right
		}
		if ValidAlign(force) {
			a = force
		}
		out = append(out, a)
	}
	return out
}

func columnNumeric(s *store.RowStore, field string) bool {
	any := false
	for _, row := range s.Scan() {
		v := s.Cell(row, field)
		if v == "" {
			continue
		}
		if !isPlainNumber(v) {
			return false
		}
		any = true
	}
	return any
}

func isPlainNumber(v string) bool {
	if v == "" {
		return false
	}
	i := 0
	if v[0] == '-' {
		i = 1
		if len(v) == 1 {
			return false
		}
	}
	digits := 0
	for ; i < len(v); i++ {
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
"""

ALIGN_TEST_GO = """\
// Unit tests for the alignment helpers.
package report_test

import "bh/internal/report"
import "bh/internal/store"
import "testing"

func TestJustify(t *testing.T) {
	if got := report.Justify("ab", 4, report.Left); got != "ab  " {
		t.Errorf("left justify = %q", got)
	}
	if got := report.Justify("ab", 4, report.Right); got != "  ab" {
		t.Errorf("right justify = %q", got)
	}
	if got := report.Justify("abcd", 2, report.Left); got != "abcd" {
		t.Errorf("no padding when wider")
	}
}

func TestTableAlign(t *testing.T) {
	s := store.New("t", []string{"num", "txt"})
	s.Insert([]string{"10", "a"})
	s.Insert([]string{"20", "b"})
	al := report.TableAlign(s, "")
	if al[0] != report.Right || al[1] != report.Left {
		t.Errorf("TableAlign = %v", al)
	}
	al2 := report.TableAlign(s, report.Left)
	if al2[0] != report.Left {
		t.Errorf("forced align ignored: %v", al2)
	}
	if !report.ValidAlign(report.Right) || report.ValidAlign("sideways") {
		t.Errorf("ValidAlign wrong")
	}
}
"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/report/report.go": ("report", _f(REPORT_GO)),
    "internal/report/report_test.go": ("report", _f(REPORT_TEST_GO)),
    "internal/report/alignment.go": ("reportal", _f(ALIGN_GO)),
    "internal/report/alignment_test.go": ("reportal", _f(ALIGN_TEST_GO)),
}