# tb3-vellum-poster — a deterministic parametric SVG poster renderer

The **Lamp Room** print gallery wants one tiny, deterministic program that
turns a JSON "poster spec" into a finished SVG poster. The same spec must
always produce byte-identical output — no timestamps, no random ids, no
environment-dependent values — because the gallery pre-flights hundreds of
layouts offline.

Your job: write the renderer and run it once on the visible spec.

## Environment

- Python 3.12, **stdlib only** (`json`, `sys`, and the `xml` modules are all
  you need). Do not `pip install` anything; there is no network.
- The visible fixture is already in the image:
  - `/app/specs/poster_spec.json` — the only spec you get to see (contents
    below, verbatim).

## The spec format (v1) — exact shape

```json
{
  "canvas":  {"width": 900, "height": 1200},
  "palette": {
    "bg": "#141a2b", "band": "#1e2940", "card": "#293552",
    "title": "#f2e9d8", "heading": "#ffc94d", "body": "#d9e0ee",
    "footer": "#97a3ba", "accent": "#e4572e"
  },
  "title":    "THE LAMP ROOM - WINTER PRINT SERIES",
  "sections": [
    {"heading": "About the series",
     "body": "Eight original linocuts by the Lamp Room collective.\nEach print is pulled by hand from maple blocks\nand signed in pencil in an edition of forty.\nSubscribers receive a proof before release."},
    {"heading": "Dates",
     "body": "Exhibition opens Friday 3 November at 18:00.\nEvening hours run through December."},
    {"heading": "How to visit",
     "body": "Entry is free and no booking is required.\nThe press room is open to visitors on Mondays."}
  ],
  "layout": {
    "title_band_fraction": 0.22, "margin_top": 42, "margin_left": 56,
    "margin_right": 56, "margin_bottom": 56, "gap_vertical": 26,
    "title_font_size": 54, "heading_font_size": 26, "body_font_size": 17,
    "heading_line_height": 34, "body_line_height": 26, "heading_body_gap": 12,
    "card_padding_x": 22, "accent_rule_height": 5, "footer_font_size": 14,
    "footer_text": "Set and proofed at the Lamp Room press, 2024"
  }
}
```

Key rules:

- `canvas.width` and `canvas.height` are **positive integers**.
- `palette` always contains exactly these eight keys, each a `#rrggbb` hex
  string: `bg`, `band`, `card`, `title`, `heading`, `body`, `footer`,
  `accent`.
- `title` is a string (may contain `&`, `<`, `"`, … — any text).
- `sections` is a list of `{"heading": str, "body": str}` objects. **It may
  be empty.** Each `body` uses only `\n` as the line separator.
- `layout` always contains exactly these keys (ints **or** floats):
  `title_band_fraction`, `margin_top`, `margin_left`, `margin_right`,
  `margin_bottom`, `gap_vertical`, `title_font_size`, `heading_font_size`,
  `body_font_size`, `heading_line_height`, `body_line_height`,
  `heading_body_gap`, `card_padding_x`, `accent_rule_height`,
  `footer_font_size`, and the string `footer_text`.

## Deliverables

1. `/app/render_poster.py` — the renderer. CLI:
   ```
   python3 /app/render_poster.py <spec.json> <out.svg>
   ```
   - Reads the spec, writes the SVG to `<out.svg>` (UTF-8), prints nothing
     on success.
   - Exit codes: `0` success · `1` usage or I/O error · `2` malformed or
     unreadable spec. The grader treats any non-zero exit on a valid spec as
     a failure.
   - Output must be a **pure function of the spec**: identical input ⇒
     byte-identical file. No current time, no random ids, no absolute paths,
     no host/user names.
   - Attribute **order within an element is not graded**; everything else
     below is graded exactly.

2. `/app/poster.svg` — the rendered poster: run your renderer on the visible
   spec and leave the result here:
   ```
   python3 /app/render_poster.py /app/specs/poster_spec.json /app/poster.svg
   ```

## Number formatting (used by every formula below)

- `r1(x)` = Python’s built-in `round(x, 1)` (half-to-even — this matters:
  e.g. `r1(68.25) == 68.2`).
- `fmt(x)` = `format(r1(x), "g")` — the shortest decimal form, no trailing
  zeros:
  - `fmt(84.0)` → `84`, `fmt(164.3)` → `164.3`, `fmt(360.5)` → `360.5`,
    `fmt(205.8)` → `205.8`, `fmt(68.25)` → `68.2`, `fmt(24)` → `24`.
- `canvas` integers are written verbatim as integers (e.g. `900`, `1200`).

## Line-count rule (bodies)

For a body string `s`:

1. `lines = s.split("\n")`
2. If the last element is empty (trailing newline), drop it: `"a\nb\n"` →
   `["a","b"]`.
3. `line_count = max(1, len(lines))` — every section has at least one body
   line slot. When `lines` is empty (the body is empty or only newlines), the
   body renders as a **single `<text>` element with empty content**.

## The SVG skeleton

The file must open with exactly this first line:
`<?xml version="1.0" encoding="utf-8"?>` (no BOM, no leading spaces), then a
single root element on its own line:

```
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}">
```

where `{W}`/`{H}` are the canvas integers. The document must be
well-formed XML — escape `&`, `<`, `>` in every text content (the standard
`xml.sax.saxutils.escape` does exactly this). Idents/blank lines between
elements are fine, but **no text content may wrap across lines** and no
extra elements, attributes, `id`s, `class`es, `style`s, comments, or
namespaces (beyond the default one) may appear.

## Element order and exact formulas

Below, `W`, `H` = canvas; `p` = palette; `L` = layout. Every numeric
attribute value is `fmt(...)`. Elements appear in exactly this order:

| # | element | attributes and text |
|---|---------|---------------------|
| 1 | `rect` | `x="0" y="0" width=fmt(W) height=fmt(H) fill=p["bg"]` — background |
| 2 | `rect` | `x="0" y="0" width=fmt(W) height=fmt(hb) fill=p["band"]` — title band, `hb = r1(L["title_band_fraction"] * H)` |
| 3 | `rect` | `x=fmt(L["margin_left"]) y=fmt(hb) width=fmt(rw) height=fmt(arh) fill=p["accent"]` — accent rule; `rw = r1(W - L["margin_left"] - L["margin_right"])`, `arh = r1(L["accent_rule_height"])` |
| 4 | `text` | `x=fmt(W/2) y=fmt(ty) text-anchor="middle" fill=p["title"] font-size=fmt(L["title_font_size"])`, text = title; `ty = r1(hb/2 + 0.35*L["title_font_size"])` |

Then, for each section in order, with cursor `by` starting at
`by = r1(hb + arh + L["margin_top"])`:

| # | element | attributes and text |
|---|---------|---------------------|
| 5a | `rect` | `x=fmt(L["margin_left"]) y=fmt(by) width=fmt(rw) height=fmt(sh) fill=p["card"]`; `sh = r1(L["heading_line_height"] + L["heading_body_gap"] + L["body_line_height"]*line_count)` |
| 5b | `text` | `x=fmt(L["margin_left"] + L["card_padding_x"]) y=fmt(hy) text-anchor="start" fill=p["heading"] font-size=fmt(L["heading_font_size"])`, text = heading; `hy = r1(by + 0.5*L["heading_line_height"] + 0.35*L["heading_font_size"])` |
| 5c | `text` | one per body line `j` (`0..line_count-1`): `x=fmt(L["margin_left"] + L["card_padding_x"]) y=fmt(bj) text-anchor="start" fill=p["body"] font-size=fmt(L["body_font_size"])`, text = lines[j] (empty string when `lines` is empty); `bj = r1(by + L["heading_line_height"] + L["heading_body_gap"] + (j + 0.5)*L["body_line_height"] + 0.35*L["body_font_size"])` |

After each section: `by = r1(by + sh + L["gap_vertical"])`.

Finally, the footer:

| # | element | attributes and text |
|---|---------|---------------------|
| 6 | `text` | `x=fmt(W/2) y=fmt(fy) text-anchor="middle" fill=p["footer"] font-size=fmt(L["footer_font_size"])`, text = `L["footer_text"]`; `fy = r1(H - L["margin_bottom"])` |

Worked example (first section of the visible spec): `hb = 264`,
`by = 264 + 5 + 42 = 311`, `sh = 34 + 12 + 26*4 = 150`,
`hy = 311 + 17 + 9.1 = 337.1`, body line 0 `bj = 311 + 34 + 12 + 13 + 5.95
= 375.95 → 375.9`.

## How the grader probes it

- Runs `/app/render_poster.py` on the visible spec **and on hidden specs**
  you have not seen (other canvas sizes incl. odd widths, other palettes,
  other layout constants incl. floats, other section counts incl. **zero
  sections**, empty bodies, trailing-newline bodies, and text containing
  `&`/`<`/quotes).
- Parses each produced SVG with `xml.etree.ElementTree` and **independently
  recomputes the full expected element tree from the spec** with its own
  implementation of the formulas above — same `r1`/`fmt`/line-count rules —
  then compares every element: tag, every attribute value as an exact
  string, and the text content exactly.
- Requires the first bytes to be the exact XML declaration and requires the
  default `xmlns` declaration on the root.
- Reads `/app/poster.svg`, parses it, and requires it to equal the
  recomputed visible poster (a hardcoded or stale poster fails).
- Re-runs one spec and requires **byte-identical** output (determinism).
- A renderer that ignores the `<spec>` argument, returns the visible poster
  for every input, or hardcodes a `poster.svg` cannot pass the hidden specs.