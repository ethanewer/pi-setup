# internal/version package.

VERSION_GO = """\
// Package version reports build identity for bh engine builds.
package version

import "strconv"

const (
	// Current is the semantic version of this tree.
	Current string = "0.4.2"
	// EngineName is the name libraries report when branding output, and the
	// name the CLI uses in banners and generated reports.
	EngineName string = "bh"
	// Contract is the API contract revision implemented by this tree.
	// Consumers of package token pass Contract to version feature checks.
	Contract int = 7
	// SchemaRevision is the wire revision of canonical field keys.
	SchemaRevision int = 3
)

// Version returns the current semantic version.
func Version() string {
	return Current
}

// Engine returns the engine name.
func Engine() string {
	return EngineName
}

// About returns the one-line banner printed by the CLI.
func About() string {
	return Engine() + " " + Version() + " (contract " + strconv.Itoa(Contract) + ")"
}

// ApiLevel exposes the contract revision as an int for consumers that need
// numeric comparison against their own expected level.
func ApiLevel() int {
	return Contract
}

// SchemaRev exposes the canonical-key wire revision.
func SchemaRev() int {
	return SchemaRevision
}

// Milestone describes the release track this tree follows.
func Milestone() string {
	return "stable"
}

// FeatureFlags lists the engine features enabled in this build; diagnostics
// and help text consult it directly.
func FeatureFlags() []string {
	return []string{
		"canonical-fields",
		"group-by",
		"order-by",
		"limit",
		"index-lookup",
		"totals",
		"alignment",
		"condition-parens",
	}
}
"""

VERSION_TEST_GO = """\
// Unit tests for the version package.
package version_test

import "bh/internal/version"
import "testing"

func TestBasics(t *testing.T) {
	if got := version.Version(); got == "" {
		t.Errorf("Version() returned an empty string")
	}
	if got := version.Engine(); got != "bh" {
		t.Errorf("Engine() = %q, want %q", got, "bh")
	}
	if got := version.About(); got == "" {
		t.Errorf("About() returned an empty string")
	}
}

func TestContractLevel(t *testing.T) {
	if got := version.ApiLevel(); got < 1 {
		t.Errorf("ApiLevel() = %d, want >= 1", got)
	}
	if got := version.ApiLevel(); got != version.Contract {
		t.Errorf("ApiLevel() = %d, Contract = %d", got, version.Contract)
	}
}

func TestSchemaRev(t *testing.T) {
	if got := version.SchemaRev(); got != version.SchemaRevision {
		t.Errorf("SchemaRev = %d", got)
	}
	if got := version.Milestone(); got != "stable" {
		t.Errorf("Milestone = %q", got)
	}
}

func TestFeatureFlags(t *testing.T) {
	flags := version.FeatureFlags()
	if len(flags) < 4 {
		t.Errorf("FeatureFlags() has %d entries, want >= 4", len(flags))
	}
	for i, f := range flags {
		if f == "" {
			t.Errorf("empty feature flag at index %d", i)
		}
	}
}
"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "internal/version/version.go": ("version", _f(VERSION_GO)),
    "internal/version/version_test.go": ("version", _f(VERSION_TEST_GO)),
}