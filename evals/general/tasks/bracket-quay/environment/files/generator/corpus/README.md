# quaydoc

quaydoc is a self-contained documentation site generator. It turns a small
set of plain-text Markdown-ish source files into a static HTML site with a
table of contents, cross-page references, a client-side search index, a
sitemap, an Atom feed, a development server, and a link-integrity checker.

It is written in pure standard-library Python and has no third-party runtime
dependencies. Python 3.9+ is required.

## Quick start

```console
$ cd examples
$ python3 -m quaydoc.cli build . -o /tmp/site
$ python3 -m quaydoc.cli check /tmp/site
No issues.
$ python3 -m quaydoc.cli serve /tmp/site --port 8000
```

`quaydoc build` reads a documentation tree (a directory of `.qd` / `.md`
files, plus an optional `quaydoc.toml` config), renders HTML pages into the
output directory, and publishes the search index, sitemap and feed. `quaydoc
check` validates the built site: every `href="#..."` fragment must resolve to
an element id on the target page, every relative link must exist, and every
image must be found.

## The markup in one screen

Blocks:

```
# H1, ## H2 ... ###### H6     headings
- a, - b, 1. x, 2. y         lists (nested by two-space indent)
> quoted paragraph
```python                     fenced code block
```                            (ends on the next ``` line)
[note] / [tip] / [warn] / [danger]   admonitions (optional text after the tag)
---                           thematic break
{% include "guide/part.qd" %} file include (paths relative to the file)
```

Inline:

```
**bold**   `code`   [[Section title]]         link to a section or page
[[Section title|label]]                       with custom link text
[link text](https://example.org)              external link
[link text](../guide/other.qd)                relative file link
![alt text](../../assets/logo.png)            image
\*  literal star                              backslash escapes
```

Front matter at the top of a file:

```
---
title: Setting up
order: 20
date: 2025-02-01
tags: [guide, setup]
draft: false
---
```

`title` becomes the page heading and the navigation label; `order` sorts the
navigation; `draft: true` files are skipped at build time.

## Table of contents and references

Every heading inside a page gets an `id` attribute, and `[[...]]` references
resolve heading titles to `#fragment` links. The heading ids and the
fragment links are produced by two separate parts of the pipeline, and
their docstrings document that the two sides must stay in lock-step: a
heading must always be reachable at the fragment its references claim.

## Commands

| command | effect |
|---|---|
| `build [root] [-o OUT]` | render the documentation tree at `root` into `OUT` (default `root`/`site`, configurable via `quaydoc.toml`) |
| `check [OUTDIR]` | validate every fragment link, page link and image in a built site |
| `serve OUTDIR [--port N] [--host H]` | static dev server over the built site |
| `watch [root]` | rebuild on file changes |
| `search TERMS... [OUTDIR]` | query a built search index |
| `init [root]` | scaffold a new documentation tree |
| `--version` | print the version |

`quaydoc build --archive path.tar.gz` also bundles the output into a tar
archive.

## Configuration

An optional `quaydoc.toml` at the documentation root:

```toml
[site]
title = "Quaydoc Manual"
base_url = "https://docs.example.test/quaydoc"
pretty_urls = true

[build]
output_dir = "site"
search = true
rss = true

[determ]
default_lang = "python"
```

Unknown keys are reported as warnings by `quaydoc check`.

## Development

```console
$ python3 -m pytest -q tests
```

The test suite covers the lexer, parser, inline markup, slug/anchor logic,
link resolution, table of contents, renderers, template engine, config,
search index, checker and the CLI.
