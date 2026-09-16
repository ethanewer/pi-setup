// Hidden case, authored for capstan-quay: a long YAML front matter block
// (many keys, list values) in a dated page path. The empty page's
// RawContent must be the empty slice; nothing from the front matter may
// leak. A body page in the same dated folder keeps rendering its raw
// source. The long block makes the slice arithmetic non-trivial (the leak
// position would be far from the start of the file) and the dated path
// differs from the upstream regression test's root-level files.
package hugolib

import (
	"testing"
)

func TestCapstanQuayHiddenLongYamlDatedPage(t *testing.T) {
	files := `
-- hugo.toml --
baseURL = "https://example.org/"
-- content/posts/2023/08/30/ato.md --
---
title: "Thylacine"
date: 2023-08-30
tags: [a, b, c]
categories:
  - "Cryptozoology"
  - "Tasmania"
hiddenflag: true
---
-- content/posts/2023/08/30/bto.md --
---
title: "Quoll"
date: 2023-08-30
---
Plain **body** text.
-- layouts/_default/single.html --
@{{ .RawContent }}@
`
	b := NewIntegrationTestBuilder(
		IntegrationTestConfig{
			T:           t,
			TxtarString: files,
		},
	).Build()

	// Body page keeps its raw source.
	b.AssertFileContent("public/posts/2023/08/30/bto/index.html", "@Plain **body** text.@")

	// Front-matter-only page renders the empty slice: none of the many keys,
	// list items or delimiters may leak.
	b.AssertFileContent(
		"public/posts/2023/08/30/ato/index.html",
		"! Thylacine",
		"! Cryptozoology",
		"! hiddenflag",
		"! ---",
		"@@",
	)
}