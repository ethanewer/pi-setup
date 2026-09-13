// Hidden case, authored for capstan-quay: TOML (+++) front matter in a
// section directory. A page that is nothing but TOML front matter must
// render an EMPTY .RawContent, while a sibling page with a body in the same
// section keeps rendering its raw source. The upstream regression test only
// uses YAML (---) front matter at the site root, so the front-matter
// format, the keys and the location all differ from what it exercises.
package hugolib

import (
	"testing"
)

func TestCapstanQuayHiddenTomlSectionEmptyPage(t *testing.T) {
	files := `
-- hugo.toml --
baseURL = "https://example.org/"
-- content/notes/empty1.md --
+++
title = "Quandongberry"
tags = ["scrub"]
+++
-- content/notes/full1.md --
+++
title = "Bush tucker"
tags = ["fruit"]
+++
Intro paragraph **bold**.
-- layouts/_default/single.html --
[{{ .RawContent }}]
`
	b := NewIntegrationTestBuilder(
		IntegrationTestConfig{
			T:           t,
			TxtarString: files,
		},
	).Build()

	// Section page with a body: raw source must render unchanged.
	b.AssertFileContent("public/notes/full1/index.html", "[Intro paragraph **bold**.]")

	// Front-matter-only page: empty slice, no leak of the TOML blocks or keys.
	b.AssertFileContent("public/notes/empty1/index.html", "! Quandongberry", "! scrub", "! +++", "[]")
}