# cmd/bh package: CLI front-end, banner help (stage head).

CMD_MAIN_GO = r"""// Command bh is the command-line front-end of the query engine: it renders
// the banner, canonicalizes conditions, and projects queries over its
// built-in probe store.
package main

import (
	"bh/internal/parser"
	"bh/internal/query"
	"bh/internal/report"
	"bh/internal/store"
	"bh/internal/version"
	"fmt"
	"os"
	"strings"
)

// canonicalize parses and normalizes a condition to its canonical form.
func canonicalize(expr string) (string, string) {
	n, errs := parser.ParseCondition(expr)
	if errs != "" {
		return "", errs
	}
	return query.NormalizeCondition(n).Format(), ""
}

// probeStore is the small built-in fixture used by the select command.
func probeStore() *store.RowStore {
	s := store.New("probe", []string{"a", "b"})
	s.Insert([]string{"1", "alpha"})
	s.Insert([]string{"2", "beta"})
	s.Insert([]string{"3", "gamma"})
	return s
}

// runQuery parses, normalizes and projects a SELECT over the probe store,
// returning the rendered table.
func runQuery(q string) (string, string) {
	n, errs := parser.ParseQuery(q)
	if errs != "" {
		return "", errs
	}
	s := probeStore()
	sel := query.SelectRows(s, query.NormalizeQuery(n))
	view := store.New("result", s.Fields)
	for _, row := range sel {
		view.Insert(row.Values)
	}
	return report.Defaults().Render(view), ""
}

func main() {
	args := os.Args
	if len(args) < 2 {
		fmt.Println(version.About())
		fmt.Println("usage: bh version | bh canon <condition> | bh select <query>")
		return
	}
	switch args[1] {
	case "version":
		fmt.Println(version.About())
	case "canon":
		got, errs := canonicalize(strings.Join(args[2:], " "))
		if errs != "" {
			fmt.Fprintln(os.Stderr, "error: " + errs)
			os.Exit(1)
		}
		fmt.Println(got)
	case "select":
		got, errs := runQuery(strings.Join(args[2:], " "))
		if errs != "" {
			fmt.Fprintln(os.Stderr, "error: " + errs)
			os.Exit(1)
		}
		fmt.Println(got)
	default:
		fmt.Fprintln(os.Stderr, "unknown command " + args[1])
		fmt.Fprintln(os.Stderr, "usage: bh version | bh canon <condition> | bh select <query>")
		os.Exit(2)
	}
}
"""

CMD_BANNER_GO = r"""// Banner helpers, added during the CLI polish pass.
package main

import "bh/internal/version"
import "strconv"
import "strings"

// banner assembles the CLI banner line.
func banner() string {
	return strings.Join([]string{
		version.Engine(),
		version.Version(),
		"contract",
		strconv.Itoa(version.ApiLevel()),
	}, " ")
}

// flagExists reports whether the arguments contain a supported flag.
func flagExists(args []string, flag string) bool {
	for _, a := range args {
		if a == flag {
			return true
		}
	}
	return false
}

// hasHelp reports whether the arguments ask for help.
func hasHelp(args []string) bool {
	return flagExists(args, "-h") || flagExists(args, "--help")
}

// summary renders a one-line command summary.
func summary() string {
	return "bh: " + version.Engine() + " " + version.Version() + " (" +
		version.About() + ")"
}
"""

CMD_TEST_GO = r"""// Unit tests for the command package. The mixed-precedence grouping
// assertions live in the query package; these tests pin the CLI plumbing.
package main

import "bh/internal/version"
import "strings"
import "testing"

func TestCanonicalize(t *testing.T) {
	got, errs := canonicalize("p = 1 OR q = 2")
	if errs != "" {
		t.Fatalf("canonicalize failed: %s", errs)
	}
	if got != "or(eq(p, 1), eq(q, 2))" {
		t.Errorf("canonicalize = %q", got)
	}
	if _, errs := canonicalize("p ="); errs == "" {
		t.Errorf("bad condition must error")
	}
}

func TestRunQuery(t *testing.T) {
	got, errs := runQuery("SELECT * FROM probe WHERE a = 1")
	if errs != "" {
		t.Fatalf("runQuery failed: %s", errs)
	}
	if !strings.Contains(got, "alpha") || strings.Contains(got, "beta") {
		t.Errorf("projection wrong:\n%s", got)
	}
	if !strings.Contains(got, "total") {
		t.Errorf("totals missing:\n%s", got)
	}
}

func TestBanner(t *testing.T) {
	b := banner()
	if !strings.Contains(b, "bh") || !strings.Contains(b, "0.4.2") {
		t.Errorf("banner = %q", b)
	}
	if !flagExists([]string{"--help", "x"}, "--help") {
		t.Errorf("flagExists failed")
	}
	if flagExists([]string{"x"}, "-h") {
		t.Errorf("flagExists false positive")
	}
	if !hasHelp([]string{"bh", "-h"}) {
		t.Errorf("hasHelp failed")
	}
	if !strings.Contains(summary(), version.About()) {
		t.Errorf("summary = %q", summary())
	}
}
"""


def _f(content):
    return lambda stage, buggy: content


FILES = {
    "cmd/bh/main.go": ("cmd", _f(CMD_MAIN_GO)),
    "cmd/bh/banner.go": ("head", _f(CMD_BANNER_GO)),
    "cmd/bh/main_test.go": ("head", _f(CMD_TEST_GO)),
}