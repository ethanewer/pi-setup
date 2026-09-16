// Probe for the hugo RawContent leak, authored for the capstan-quay task.
//
// When a content page consists of ONLY front matter (no body), Hugo must
// treat the page body as empty: any output that prints the page's raw
// content ({{ .RawContent }}) must render an EMPTY slice, never the raw
// front matter text (the delimiters and the keys). A sibling page with a
// body must keep rendering its raw source as before. While the bug is
// present the front-matter-only assertion FAILS because the raw front
// matter leaks into the output; with the fix applied every assertion passes.
//
// Copy this file into the checked-out tree and run the project's own test
// runner from the repo root (no network needed, caches are warm):
//
//   cp /app/probe_test.go hugolib/probe_test.go
//   cd /app/src && go test -vet=off ./hugolib -run TestCapstanQuayRawContentLeakProbe -v
package hugolib

import (
	"testing"
)

func TestCapstanQuayRawContentLeakProbe(t *testing.T) {
	files := `
-- hugo.toml --
baseURL = "https://example.org/"
-- content/empty.md --
---
title: "wobbegong"
tags: ["jaws"]
---
-- content/withbody.md --
---
title: "sharktail"
---
Body **here**
-- layouts/_default/single.html --
BEGIN{{ .RawContent }}END
`
	b := NewIntegrationTestBuilder(
		IntegrationTestConfig{
			T:           t,
			TxtarString: files,
		},
	).Build()

	// Front-matter-only page: RawContent must be the empty slice. The raw
	// front matter (delimiters or keys) must not leak into the output.
	b.AssertFileContent("public/empty/index.html", "! wobbegong", "! jaws", "! ---", "BEGINEND")

	// Positive control: a page with a body still renders its raw source.
	b.AssertFileContent("public/withbody/index.html", "BEGINBody **here**END")
}