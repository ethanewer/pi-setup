# internal/schema package.

SCHEMA_GO = """\
// Package schema is the column type registry for stores. A Registry fixes
// the field set of a table: names, types, allowed enum values and mask
// formats. Values are validated and coerced before they hit the store.
package schema

import "strconv"
import "strings"

// Kind labels the supported column types.
type Kind int

// Column kinds.
const (
	TextKind  Kind = 1
	IntKind   Kind = 2
	FloatKind Kind = 3
	BoolKind  Kind = 4
	EnumKind  Kind = 5
	MaskKind  Kind = 6
)

// Label returns the type name for diagnostics and reports.
func (k Kind) Label() string {
	switch k {
	case TextKind:
		return "text"
	case IntKind:
		return "int"
	case FloatKind:
		return "float"
	case BoolKind:
		return "bool"
	case EnumKind:
		return "enum"
	case MaskKind:
		return "mask"
	}
	return "unknown"
}

// ParseKind resolves a type name to a Kind; unknown returns zero.
func ParseKind(name string) Kind {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "text":
		return TextKind
	case "int":
		return IntKind
	case "float":
		return FloatKind
	case "bool":
		return BoolKind
	case "enum":
		return EnumKind
	case "mask":
		return MaskKind
	}
	return 0
}

// Field describes one column.
type Field struct {
	Name  string
	Kind  Kind
	Enums []string // allowed values for EnumKind
	Mask  string   // marker string for MaskKind
}

// Renders a one-line description of the field type.
func (f Field) TypeString() string {
	switch f.Kind {
	case EnumKind:
		return "enum(" + strings.Join(f.Enums, "|") + ")"
	case MaskKind:
		return "mask"
	}
	return f.Kind.Label()
}

// Registry is a validated schema: a list of Fields plus a name index.
type Registry struct {
	Fields []Field
	index  map[string]int
}

// New builds an empty registry.
func New() *Registry {
	return &Registry{ Fields: []Field{}, index: map[string]int{} }
}

// Add registers a new field. Duplicate names, empty names and empty enum
// lists for enum fields are rejected.
func (r *Registry) Add(f Field) bool {
	if f.Name == "" {
		return false
	}
	if f.Kind == EnumKind && len(f.Enums) == 0 {
		return false
	}
	if _, taken := r.index[strings.ToLower(f.Name)]; taken {
		return false
	}
	r.Fields = append(r.Fields, f)
	r.index[strings.ToLower(f.Name)] = len(r.Fields) - 1
	return true
}

// Count returns the number of registered fields.
func (r *Registry) Count() int {
	return len(r.Fields)
}

// Field returns the registered field by name (case-insensitive).
func (r *Registry) Field(name string) (Field, bool) {
	i, ok := r.index[strings.ToLower(name)]
	if !ok {
		return Field{}, false
	}
	return r.Fields[i], true
}

// Rename renames a field; returns false for unknown names or a collision.
func (r *Registry) Rename(oldName, newName string) bool {
	if newName == "" {
		return false
	}
	i, ok := r.index[strings.ToLower(oldName)]
	if !ok {
		return false
	}
	lower := strings.ToLower(newName)
	if other, exists := r.index[lower]; exists && other != i {
		return false
	}
	delete(r.index, strings.ToLower(oldName))
	r.index[lower] = i
	r.Fields[i].Name = newName
	return true
}

// Validate reports whether value coerces to the field's kind.
func (r *Registry) Validate(name, value string) bool {
	f, ok := r.Field(name)
	if !ok {
		return false
	}
	switch f.Kind {
	case TextKind:
		return true
	case IntKind:
		_, err := strconv.ParseInt(strings.TrimSpace(value), 10, 64)
		return err == nil
	case FloatKind:
		_, err := strconv.ParseFloat(strings.TrimSpace(value), 64)
		return err == nil
	case BoolKind:
		v := strings.ToLower(strings.TrimSpace(value))
		return v == "true" || v == "false"
	case EnumKind:
		v := strings.ToLower(strings.TrimSpace(value))
		for _, e := range f.Enums {
			if strings.ToLower(e) == v {
				return true
			}
		}
		return false
	case MaskKind:
		return strings.TrimSpace(value) != ""
	}
	return false
}

// Coerce returns the canonical stored form of value for the field kind.
// Masked values are normalised to the field's marker string; everything else
// is trimmed. ok reports whether the value was valid.
func (r *Registry) Coerce(name, value string) (string, bool) {
	f, ok := r.Field(name)
	if !ok {
		return "", false
	}
	if !r.Validate(name, value) {
		return "", false
	}
	switch f.Kind {
	case MaskKind:
		return f.Mask, true
	case BoolKind:
		return strings.ToLower(strings.TrimSpace(value)), true
	case EnumKind:
		return strings.ToLower(strings.TrimSpace(value)), true
	}
	return strings.TrimSpace(value), true
}

// CoerceMany validates and coerces a whole row. ok is false when any cell
// fails its column's rules.
func (r *Registry) CoerceMany(values []string) ([]string, bool) {
	if len(values) != len(r.Fields) {
		return nil, false
	}
	out := make([]string, len(values))
	for i := range values {
		c, ok := r.Coerce(r.Fields[i].Name, values[i])
		if !ok {
			return nil, false
		}
		out[i] = c
	}
	return out, true
}

// IndexOf returns the registration position of a field, or -1.
func (r *Registry) IndexOf(name string) int {
	i, ok := r.index[strings.ToLower(name)]
	if !ok {
		return -1
	}
	return i
}

// Remove deletes a registered field and reindexes the remainder.
func (r *Registry) Remove(name string) bool {
	i, ok := r.index[strings.ToLower(name)]
	if !ok {
		return false
	}
	r.Fields = append(r.Fields[:i], r.Fields[i+1:]...)
	r.index = map[string]int{}
	for j, f := range r.Fields {
		r.index[strings.ToLower(f.Name)] = j
	}
	return true
}

// Summary renders a compact schema listing for diagnostics: "4 fields:
// id=int, name=text".
func (r *Registry) Summary() string {
	cells := []string{}
	for _, f := range r.Fields {
		cells = append(cells, f.Name+"="+f.TypeString())
	}
	return strconv.Itoa(len(r.Fields)) + " fields: " + strings.Join(cells, ", ")
}

// ValidateRow validates a whole row of values against the schema.
func (r *Registry) ValidateRow(values []string) bool {
	if len(values) != len(r.Fields) {
		return false
	}
	for i := range values {
		if !r.Validate(r.Fields[i].Name, values[i]) {
			return false
		}
	}
	return true
}

// Names returns the field names in registration order.
func (r *Registry) Names() []string {
	out := make([]string, len(r.Fields))
	for i := range r.Fields {
		out[i] = r.Fields[i].Name
	}
	return out
}
"""

SCHEMA_TEST_GO = """\
// Unit tests for the schema registry.
package schema_test

import "bh/internal/schema"
import "strings"
import "testing"

func TestAddFields(t *testing.T) {
	r := schema.New()
	r.Add(schema.Field{ Name: "id", Kind: schema.IntKind })
	r.Add(schema.Field{ Name: "name", Kind: schema.TextKind })
	r.Add(schema.Field{ Name: "tier", Kind: schema.EnumKind, Enums: []string{"a", "b", "c"} })
	r.Add(schema.Field{ Name: "secret", Kind: schema.MaskKind, Mask: "***" })
	if r.Count() != 4 {
		t.Errorf("Count = %d, want 4", r.Count())
	}
	if r.Add(schema.Field{ Name: "id", Kind: schema.TextKind }) {
		t.Errorf("duplicate name must be rejected")
	}
	if r.Add(schema.Field{ Name: "", Kind: schema.TextKind }) {
		t.Errorf("empty name must be rejected")
	}
	if r.Add(schema.Field{ Name: "emptyEnum", Kind: schema.EnumKind }) {
		t.Errorf("enum without values must be rejected")
	}
	if _, ok := r.Field("ID"); !ok {
		t.Errorf("case-insensitive lookup failed")
	}
}

func TestValidateAndCoerce(t *testing.T) {
	r := schema.New()
	r.Add(schema.Field{ Name: "id", Kind: schema.IntKind })
	r.Add(schema.Field{ Name: "pct", Kind: schema.FloatKind })
	r.Add(schema.Field{ Name: "ok", Kind: schema.BoolKind })
	r.Add(schema.Field{ Name: "note", Kind: schema.TextKind })
	r.Add(schema.Field{ Name: "tier", Kind: schema.EnumKind, Enums: []string{"gold", "silver"} })
	r.Add(schema.Field{ Name: "secret", Kind: schema.MaskKind, Mask: "***" })

	if !r.Validate("id", "42") || !r.Validate("pct", "3.5") {
		t.Errorf("numeric validation failed")
	}
	if r.Validate("id", "abc") || r.Validate("ok", "maybe") {
		t.Errorf("invalid values must fail validation")
	}
	if !r.Validate("tier", "GOLD") {
		t.Errorf("enum must validate case-insensitively")
	}
	if r.Validate("tier", "platinum") {
		t.Errorf("unknown enum value must fail")
	}
	c, ok := r.Coerce("secret", "s3cr3t")
	if !ok || c != "***" {
		t.Errorf("mask coerce = %q, %v", c, ok)
	}
	c, ok = r.Coerce("tier", "Silver")
	if !ok || c != "silver" {
		t.Errorf("enum coerce = %q, %v", c, ok)
	}
	_, ok = r.Coerce("missing", "x")
	if ok {
		t.Errorf("unknown field must not coerce")
	}
}

func TestCoerceMany(t *testing.T) {
	r := schema.New()
	r.Add(schema.Field{ Name: "id", Kind: schema.IntKind })
	r.Add(schema.Field{ Name: "name", Kind: schema.TextKind })
	out, ok := r.CoerceMany([]string{" 7 ", "  alice "})
	if !ok || out[0] != "7" || out[1] != "alice" {
		t.Errorf("CoerceMany = %v, %v", out, ok)
	}
	if _, ok := r.CoerceMany([]string{"x", "alice"}); ok {
		t.Errorf("bad cell must fail the row")
	}
	if _, ok := r.CoerceMany([]string{"1"}); ok {
		t.Errorf("arity mismatch must fail the row")
	}
}

func TestSummary(t *testing.T) {
	r := schema.New()
	r.Add(schema.Field{ Name: "id", Kind: schema.IntKind })
	r.Add(schema.Field{ Name: "tier", Kind: schema.EnumKind, Enums: []string{"a", "b"} })
	sum := r.Summary()
	if !strings.Contains(sum, "id=int") || !strings.Contains(sum, "tier=enum(a|b)") {
		t.Errorf("Summary = %q", sum)
	}
}

func TestIndexRemoveValidateRow(t *testing.T) {
	r := schema.New()
	r.Add(schema.Field{ Name: "id", Kind: schema.IntKind })
	r.Add(schema.Field{ Name: "name", Kind: schema.TextKind })
	r.Add(schema.Field{ Name: "dead", Kind: schema.BoolKind })
	if r.IndexOf("name") != 1 {
		t.Errorf("IndexOf(name) = %d", r.IndexOf("name"))
	}
	if r.IndexOf("nope") != -1 {
		t.Errorf("IndexOf(nope) must be -1")
	}
	if !r.ValidateRow([]string{"1", "x", "true"}) {
		t.Errorf("valid row rejected")
	}
	if r.ValidateRow([]string{"x", "y", "true"}) {
		t.Errorf("invalid row accepted")
	}
	if r.ValidateRow([]string{"1"}) {
		t.Errorf("short row accepted")
	}
	if !r.Remove("dead") || r.Count() != 2 {
		t.Errorf("Remove failed")
	}
	if r.Remove("dead") {
		t.Errorf("double Remove must fail")
	}
}

func TestRenameAndParseKind(t *testing.T) {
	r := schema.New()
	r.Add(schema.Field{ Name: "a", Kind: schema.IntKind })
	if !r.Rename("a", "b") || r.Count() != 1 {
		t.Errorf("rename failed")
	}
	if _, ok := r.Field("a"); ok {
		t.Errorf("old name must vanish after rename")
	}
	if r.Rename("a", "c") {
		t.Errorf("renaming an unknown field must fail")
	}
	if got := schema.ParseKind("INT"); got != schema.IntKind {
		t.Errorf("ParseKind(INT) = %d", got)
	}
	if got := schema.ParseKind("nope"); got != 0 {
		t.Errorf("ParseKind(nope) = %d", got)
	}
	names := r.Names()
	if len(names) != 1 || names[0] != "b" {
		t.Errorf("Names = %v", names)
	}
	if got := r.Fields[0].TypeString(); got != "int" {
		t.Errorf("TypeString = %q", got)
	}
}
"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/schema/schema.go": ("schema", _f(SCHEMA_GO)),
    "internal/schema/schema_test.go": ("schema", _f(SCHEMA_TEST_GO)),
}