# internal/conf package.

CONF_GO = r"""// Package conf loads a small sectioned key=value configuration format:
//
//	# comment
//	[section]
//	key = value
//
// Keys are namespaced as section.key; a key outside any section keeps its
// bare name. '#' starts a comment at line start or after the value.
package conf

import "strconv"
import "strings"

// Config is a parsed configuration.
type Config struct {
	Entries map[string]string
	Secs    []string
}

// New builds an empty config.
func New() *Config {
	return &Config{ Entries: map[string]string{}, Secs: []string{} }
}

// Parse parses src into a Config. The second result is an error message,
// empty on success.
func Parse(src string) (*Config, string) {
	cfg := New()
	section := ""
	lines := strings.Split(src, "\n")
	for i, raw := range lines {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") {
			sec := strings.TrimSpace(strings.Trim(line, "[]"))
			if sec == "" {
				return nil, "empty section header at line " + strconv.Itoa(i+1)
			}
			section = sec
			if !cfg.HasSection(section) {
				cfg.Secs = append(cfg.Secs, section)
			}
			continue
		}
		eq := strings.Index(line, "=")
		if eq < 0 {
			return nil, "missing '=' at line " + strconv.Itoa(i+1)
		}
		key := strings.TrimSpace(line[:eq])
		if key == "" {
			return nil, "empty key at line " + strconv.Itoa(i+1)
		}
		val := strings.TrimSpace(line[eq+1:])
		if c := strings.Index(val, "#"); c >= 0 {
			val = strings.TrimSpace(val[:c])
		}
		full := key
		if section != "" {
			full = section + "." + key
		}
		cfg.Entries[full] = val
	}
	return cfg, ""
}

// Get returns the value for a key, or def when absent.
func (c *Config) Get(key, def string) string {
	v, ok := c.Entries[key]
	if !ok {
		return def
	}
	return v
}

// HasSection reports whether the section was seen.
func (c *Config) HasSection(sec string) bool {
	for _, s := range c.Secs {
		if s == sec {
			return true
		}
	}
	return false
}

// Size returns the number of entries.
func (c *Config) Size() int {
	return len(c.Entries)
}

// Sections returns the section names in order of first appearance.
func (c *Config) Sections() []string {
	return c.Secs
}

// GetInt parses the value as an integer, returning def on absence or bad
// parse.
func (c *Config) GetInt(key string, def int) int {
	v, ok := c.Entries[key]
	if !ok {
		return def
	}
	n, err := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
	if err != nil {
		return def
	}
	return int(n)
}

// GetFloat parses the value as a float, returning def on absence or bad
// parse.
func (c *Config) GetFloat(key string, def float64) float64 {
	v, ok := c.Entries[key]
	if !ok {
		return def
	}
	f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
	if err != nil {
		return def
	}
	return f
}

// GetBool parses the value as true/false (case-insensitive), returning def
// on absence or any other spelling.
func (c *Config) GetBool(key string, def bool) bool {
	v, ok := c.Entries[key]
	if !ok {
		return def
	}
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "true":
		return true
	case "false":
		return false
	}
	return def
}

// Merge folds the entries of other into the receiver (other wins on
// conflicts) and returns how many entries changed or were added.
func (c *Config) Merge(other *Config) int {
	changed := 0
	for k, v := range other.Entries {
		if cur, ok := c.Entries[k]; !ok || cur != v {
			c.Entries[k] = v
			changed++
		}
	}
	for _, sec := range other.Secs {
		if !c.HasSection(sec) {
			c.Secs = append(c.Secs, sec)
		}
	}
	return changed
}

// Dump renders every entry as "key = value" lines in sorted order, used by
// debug output and the CLI.
func (c *Config) Dump() string {
	keys := make([]string, 0, len(c.Entries))
	for k := range c.Entries {
		keys = append(keys, k)
	}
	sortStrings(keys)
	lines := []string{}
	for _, k := range keys {
		lines = append(lines, k+" = "+c.Entries[k])
	}
	return strings.Join(lines, "\n")
}

// ByteSize is a rough footprint estimate used by debug output.
func (c *Config) ByteSize() int {
	total := 0
	for k, v := range c.Entries {
		total += len(k) + len(v)
	}
	return total
}

// KeysIn returns the bare keys that belong to a section, sorted.
func (c *Config) KeysIn(sec string) []string {
	prefix := sec + "."
	out := []string{}
	for k := range c.Entries {
		if strings.HasPrefix(k, prefix) {
			out = append(out, strings.TrimPrefix(k, prefix))
		}
	}
	sortStrings(out)
	return out
}

func sortStrings(a []string) {
	for i := 1; i < len(a); i++ {
		for j := i; j > 0 && a[j] < a[j-1]; j-- {
			a[j], a[j-1] = a[j-1], a[j]
		}
	}
}
"""

CONF_TEST_GO = r"""// Unit tests for the configuration loader.
package conf_test

import "bh/internal/conf"
import "testing"

func sampleText() string {
	return "# engine tuneables\n" +
		"[query]\n" +
		"timeout = 2500\n" +
		"cache = true\n" +
		"mode = fast\n" +
		"\n" +
		"[report]\n" +
		"width = 40\n" +
		"title = q1 # trailing comment\n"
}

func TestParse(t *testing.T) {
	cfg, errs := conf.Parse(sampleText())
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	if cfg.Size() != 5 {
		t.Errorf("Size = %d, want 5", cfg.Size())
	}
	if !cfg.HasSection("query") || !cfg.HasSection("report") {
		t.Errorf("sections missing")
	}
	secs := cfg.Sections()
	if len(secs) != 2 || secs[0] != "query" || secs[1] != "report" {
		t.Errorf("Sections = %v", secs)
	}
}

func TestTypedGetters(t *testing.T) {
	cfg, _ := conf.Parse(sampleText())
	if got := cfg.GetInt("query.timeout", 0); got != 2500 {
		t.Errorf("GetInt = %d", got)
	}
	if !cfg.GetBool("query.cache", false) {
		t.Errorf("GetBool = false")
	}
	if got := cfg.GetFloat("report.width", 0); got != 40 {
		t.Errorf("GetFloat = %v", got)
	}
	if got := cfg.Get("report.title", ""); got != "q1" {
		t.Errorf("trailing comment not stripped: %q", got)
	}
	if got := cfg.GetInt("query.missing", 7); got != 7 {
		t.Errorf("missing default = %d", got)
	}
}

func TestErrors(t *testing.T) {
	if _, errs := conf.Parse("a"); errs == "" {
		t.Errorf("bare line must error")
	}
	if _, errs := conf.Parse("= 1"); errs == "" {
		t.Errorf("empty key must error")
	}
	if _, errs := conf.Parse("[]\nx = 1"); errs == "" {
		t.Errorf("empty section must error")
	}
}

func TestKeysIn(t *testing.T) {
	cfg, _ := conf.Parse(sampleText())
	keys := cfg.KeysIn("query")
	if len(keys) != 3 {
		t.Errorf("KeysIn(query) = %v", keys)
	}
	if keys[0] != "cache" || keys[2] != "timeout" {
		t.Errorf("KeysIn order: %v", keys)
	}
}

func TestDump(t *testing.T) {
	cfg, _ := conf.Parse("b = 2\na = 1")
	d := cfg.Dump()
	if d != "a = 1\nb = 2" {
		t.Errorf("Dump = %q", d)
	}
}

func TestMerge(t *testing.T) {
	a, _ := conf.Parse("x = 1\n[sec]\ny = 2")
	b, _ := conf.Parse("x = 9\nz = 3")
	n := a.Merge(b)
	if n != 2 {
		t.Errorf("Merge changed %d entries", n)
	}
	if a.Get("x", "") != "9" {
		t.Errorf("Merge must keep other on conflict")
	}
	if a.Get("z", "") != "3" {
		t.Errorf("Merge must add new keys")
	}
	if a.ByteSize() <= 0 {
		t.Errorf("ByteSize = %d", a.ByteSize())
	}
}

func TestMalevolentParse(t *testing.T) {
	cfg, errs := conf.Parse("\n\n# only comments\n")
	if errs != "" || cfg.Size() != 0 {
		t.Errorf("empty config parse failed: %q", errs)
	}
	cfg, errs = conf.Parse("a=1\nb =  2  ")
	if errs != "" {
		t.Fatalf("parse failed: %s", errs)
	}
	if cfg.Get("a", "") != "1" || cfg.Get("b", "") != "2" {
		t.Errorf("values not trimmed")
	}
}
"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/conf/conf.go": ("conf", _f(CONF_GO)),
    "internal/conf/conf_test.go": ("conf", _f(CONF_TEST_GO)),
}