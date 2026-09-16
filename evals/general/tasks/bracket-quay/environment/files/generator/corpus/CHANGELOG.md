# Changelog

All notable changes to quaydoc are documented here. Versions follow
semantic versioning.

## 0.9.0 (2025-03-20)

### Added
- `quaydoc build --archive` bundles the output directory into a gzip tar.
- `quaydoc init` scaffolds a new documentation tree with a config and an
  example page.
- `quaydoc check` now also reports duplicated element ids within a page
  (`duplicate-id`).
- Atom feed now includes a per-entry `id` based on the canonical page URL.

### Changed
- Heading anchors for punctuation-heavy titles were reworked so generated
  ids read more naturally.
- The dev server default host is now 127.0.0.1 and advertises a stable
  favicon.
- The default theme is refreshed; navigation collapses below 768px.

### Fixed
- Includes can no longer escape the documentation root via `../..` paths.
- Search index omits draft pages.

## 0.8.0 (2025-01-12)

### Added
- `quaydoc check`: link-integrity checker over a built site (fragments,
  page links, images).
- Polling watcher and live rebuild.
- Search index generation and `quaydoc search`.
- Sitemap and Atom feed generation.

### Fixed
- Front matter `tags` is normalised to a list.
- Fenced code blocks preserve interior blank lines.

## 0.7.0 (2024-11-30)

### Added
- Template engine with `{{ }}` interpolation, `{% if %}` / `{% for %}` and
  `{% include %}`.
- Config validation with warnings for unknown keys.
- This CHANGELOG.

### Fixed
- Ordered lists inside block quotes render correctly.
- HTML escaping in code spans.

## 0.6.0 (2024-10-15)

### Added
- Nested lists (two-space indent).
- Front matter: title, order, date, tags, draft.
- Admonition blocks.

### Fixed
- Lexer no longer mis-starts a fence on ```` ``` ```` indented under a list.

## 0.5.0 (2024-09-01)

### Added
- First public release: lexer, parser, inline markup, HTML renderer, theme,
  pages and site builder, dev server.
