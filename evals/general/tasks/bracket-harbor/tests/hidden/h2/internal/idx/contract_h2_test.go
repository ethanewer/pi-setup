// Hidden contract suite H2 for the index package: canonical keys, wildcard
// probes and prefix matching. These hold under any correct implementation
// and catch fixes that repair grouping by weakening field-key folding.
package idx_test

import "bh/internal/idx"
import "bh/internal/store"
import "bh/internal/token"
import "testing"

func TestHiddenIndexCanonicalKeys(t *testing.T) {
	s := store.New("devices", []string{"device", "label", "region"})
	s.Insert([]string{"alpha", "Edge Storage", "EUR"})
	s.Insert([]string{"beta_2", "Core", "US"})
	s.Insert([]string{"gamma", "Edge Storage", "US"})
	ix := idx.BuildIndex(s, "label")

	// Probes fold spacing and case, so uneven input still hits the entry.
	rows := ix.Lookup("  edge  storage ")
	if len(rows) != 2 {
		t.Errorf("hidden h2: ragged probe = %v, want 2 rows", rows)
	}
	// Underscores and dots must stay distinct keys.
	if got := token.CanonKey("beta_2"); got != "beta_2" {
		t.Errorf("hidden h2: underscore key mangled: %q", got)
	}
	if got := token.CanonKey(" Beta_2 "); got != "beta_2" {
		t.Errorf("hidden h2: canonicalized underscore key = %q", got)
	}
	under := idx.BuildIndex(s, "device")
	if under.Distinct() != 3 {
		t.Errorf("hidden h2: device keys must stay distinct: %v", under.Keys())
	}
	if got := under.Lookup("BETA_2"); len(got) != 1 || got[0] != 1 {
		t.Errorf("hidden h2: case-folded underscore probe = %v", got)
	}
}

func TestHiddenWildcardsAndPrefix(t *testing.T) {
	byIP := store.New("hosts", []string{"ip", "name"})
	byIP.Insert([]string{"10.0.0.1", "a"})
	byIP.Insert([]string{"10.0.0.2", "b"})
	byIP.Insert([]string{"192.168.1.5", "c"})
	ix := idx.BuildIndex(byIP, "ip")
	if got := ix.Lookup("10.0.*"); len(got) != 2 {
		t.Errorf("hidden h2: 10.0.* = %v", got)
	}
	if got := ix.Lookup("*"); len(got) != 3 {
		t.Errorf("hidden h2: * = %v", got)
	}
	if got := ix.Prefix("192."); len(got) != 1 || got[0] != 2 {
		t.Errorf("hidden h2: Prefix(192.) = %v", got)
	}
}

func TestHiddenMatchWildSemantics(t *testing.T) {
	ok := []struct{ s, p string }{
		{"a.b.c", "a*"},
		{"a.b.c", "*c"},
		{"a.b.c", "a*b*c"},
		{"a.b.c", "a.*.*"},
		{"10.0.0.1", "10.*.1"},
		{"", "*"},
	}
	for _, c := range ok {
		if !idx.WildMatch(c.s, c.p) {
			t.Errorf("hidden h2: WildMatch(%q, %q) = false, want true", c.s, c.p)
		}
	}
	bad := []struct{ s, p string }{
		{"a.b.c", "a*."},
		{"a.b.c", "b*"},
		{"10.0.0.1", "10.*.9"},
	}
	for _, c := range bad {
		if idx.WildMatch(c.s, c.p) {
			t.Errorf("hidden h2: WildMatch(%q, %q) = true, want false", c.s, c.p)
		}
	}
}