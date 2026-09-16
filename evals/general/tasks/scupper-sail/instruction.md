# scupper-sail: build a responsive dashboard shell from a written spec

Your job is to produce a **responsive dashboard shell** as two static files, from
the spec below, with **no browser and no renderer** in the environment. A
verifier decides correctness by *parsing your stylesheet and resolving the
cascade* against four hidden viewport fixtures, using the semantics documented
here. Everything that is checkable is listed explicitly in
[What is checkable](#what-is-checkable); the contract is fair by design.

## Deliverables

| file | what it is |
|---|---|
| `/app/styles.css` | a plain CSS stylesheet implementing the shell |
| `/app/dashboard.html` | the minimal HTML page the stylesheet styles |

Both files must exist at the end. The verifier runs, effectively:

```
python3 /tests/resolver.py /app/styles.css /app/dashboard.html /tests/hidden
```

The image has Python 3.12 and `tinycss2==1.5.1` installed; there is no network.
`/app/fixtures/` contains a visible example of the viewport-fixture document
the hidden fixtures follow; read it, but never modify it (the verifier ignores
it).

---

## 1. The dashboard shell — markup

`/app/dashboard.html` must be a minimal, well-formed single page with **exactly
this element vocabulary** (extra text, attributes such as `lang`, and cosmetic
content elements are allowed):

```
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>...</title>
    <link rel="stylesheet" href="styles.css">
  </head>
  <body>
    <div id="app" class="app">
      <div class="shell">
        <header class="topbar">...</header>
        <aside class="sidebar">
          <div class="stat">...</div>   <!-- at least 2 -->
        </aside>
        <main class="main">
          <div class="card-grid">
            <div class="card">...</div> <!-- at least 8 -->
          </div>
        </main>
      </div>
    </div>
  </body>
</html>
```

Requirements:

- `<!DOCTYPE html>` present.
- `<link rel="stylesheet" href="styles.css">` in the head.
- one element with `id="app"` (the page root element carries class `app`).
- the single `div.shell` directly contains `header.topbar`, `aside.sidebar`
  and `main.main`.
- `main.main` contains a single `div.card-grid`, which contains at least eight
  `div.card` elements.
- `aside.sidebar` contains at least two `div.stat` elements.
- Tags are balanced and close in order.

## 2. The shell behaviour

This is a classic dashboard grid:

- **12-column grid.** `.shell` is a grid with 12 columns, a `16px` gutter
  (`gap`), and establishes a *container* (CSS Containment: it has
  `container-type: inline-size`).
- **Top bar.** `.topbar` spans the full width.
- **Sidebar.** `.sidebar` spans **1 of 12 columns by default** (the collapsed
  "rail" state). Below `768px` it is removed from layout (`display: none`).
  At `1280px` and wider it expands to span **4 of 12 columns**. When an
  element has the extra class `sidebar open` the sidebar uses an "active"
  background colour; the `open` state must override the resting background
  through **selector specificity**, not through placement in the file.
- **Main pane.** `.main` spans the remaining columns: **11** by default
  (rail state), **8** at `1280px` and wider, **12** below `768px`.
- **Card grid.** `.card-grid` spans the whole main pane, is itself a
  *container* with `container-type: inline-size`, and lays out its `.card`
  children: **1 column** by default, **2** once the card-grid's own width (its
  container size) reaches `720px`, **3** once it reaches `960px`.
- **Stats.** `.sidebar` establishes a container too. Its `.stat` children sit
  in **1 column** by default and reflow into **2 columns** once the
  *sidebar's own width* reaches `480px`.

Note the two axes: media queries answer *"how wide is the viewport?"*,
container queries answer *"how wide is the sidebar / the card-grid?"*.

## 3. The stylesheet contract

Write `/app/styles.css` in the following subset: qualified rules, `@media`
blocks whose condition(s) use `(min-width: …)` / `(max-width: …)`, `@container`
blocks likewise, and comments. Selectors may use: an element type (e.g. `div`),
`#id`, `.class` (several allowed, e.g. `.sidebar.open`), the `:root`
pseudo-class, and the descendant (space) and child (`>`) combinators. Anything
else in the file is skipped with a warning — it cannot help you and it cannot
satisfy a requirement.

### 3.1 Custom properties (`:root`)

Declare **all of these, with exactly these values**, in a rule with the
selector `:root` (not `html`):

```css
:root {
  --scupper-grid-cols: 12;
  --scupper-gap: 16px;
  --scupper-bp-sm: 768px;
  --scupper-bp-lg: 1280px;
  --scupper-sidebar-span: 4;
  --scupper-rail-span: 1;
  --scupper-main-span-lg: 8;
  --scupper-main-span-tablet: 11;
  --scupper-main-span-mobile: 12;
  --scupper-bg-sidebar: #1e293b;
  --scupper-bg-sidebar-open: #0f172a;
  --scupper-bg-main: #f8fafc;
  --scupper-bg-card: #ffffff;
  --scupper-bg-stat: #e2e8f0;
}
```

### 3.2 Required rules

```css
.shell {
  display: grid;
  grid-template-columns: repeat(var(--scupper-grid-cols), 1fr);
  gap: var(--scupper-gap);
  container-type: inline-size;
}

.topbar {
  grid-column: 1 / -1;
}

.sidebar {
  grid-column: span var(--scupper-rail-span);
  container-type: inline-size;
  background: var(--scupper-bg-sidebar);
}

.sidebar.open {
  background: var(--scupper-bg-sidebar-open);
}

.main {
  grid-column: span var(--scupper-main-span-tablet);
  background: var(--scupper-bg-main);
}

.card-grid {
  container-type: inline-size;
}

.card {
  grid-column: span 1;
  background: var(--scupper-bg-card);
}

.stat {
  grid-column: span 1;
  background: var(--scupper-bg-stat);
}
```

You may add other properties to these rules (e.g. `display: grid` and
`gap` on `.sidebar`/`.card-grid`, colors on `.topbar`) and extra rules of your
own, provided none of them changes a resolved value that is checked (see the
table below).

### 3.3 Container queries

```css
@container (min-width: 480px) {
  .stat { grid-column: span 2; }
}

@container (min-width: 720px) {
  .card { grid-column: span 2; }
}

@container (min-width: 960px) {
  .card { grid-column: span 3; }
}
```

The `720px` and `960px` blocks both target `.card` with equal specificity, so
their **source order matters**: the `960px` rule must come *after* the `720px`
rule, otherwise a card that satisfies both conditions resolves to 2 columns
instead of 3.

### 3.4 Media queries

```css
@media (min-width: 1280px) {
  .sidebar { grid-column: span var(--scupper-sidebar-span); }
  .main { grid-column: span var(--scupper-main-span-lg); }
}

@media (max-width: 767px) {
  .sidebar { display: none; }
  .main { grid-column: span var(--scupper-main-span-mobile); }
}
```

The breakpoint conditions are **literal px tokens matched against the custom
properties**: `--scupper-bp-lg` is `1280px`, so the expanded band opens at
`min-width: 1280px`; `--scupper-bp-sm` is `768px`, so the collapsed band is
`max-width: 767px` (note the off-by-one — the band strictly below 768px).
CSS media queries cannot use `var()`; the verifier checks the literals against
the two properties.

## 4. How the verifier resolves your cascade

For each viewport fixture (DOM tree + `viewport_width`, plus explicit
engine-reported widths on container nodes), the verifier:

1. **Parses** `/app/styles.css` with tinycss2 into plain / `@media` /
   `@container` layers.
2. **Media layers.** A `@media` layer is active at a viewport iff *every* one
   of its conditions holds: `min-width` compares the viewport `≥` the value,
   `max-width` `≤`.
3. **Container layers.** A `@container` layer is active *for a given node* iff
   the node's **nearest ancestor whose resolved `container-type` is
   `inline-size`** has a width (from the fixture, falling back to the viewport
   width) satisfying all of the layer's conditions. (So `.stat` queries
   resolve against `.sidebar`; `.card` queries against `.card-grid`.)
4. **Matching.** A rule applies to a node when its selector matches: `.class`
   must be present on the node, `#id` must equal it, a type must equal the tag,
   `:root` matches only the document root (the `#app` element in the
   fixtures); combinators are evaluated against ancestors.
5. **Winning declaration.** For each property, among all applying declarations
   from active layers, the winner is the one with the **highest selector
   specificity**, ties broken by **later source position** in the file.
   Specificity is a triple (number of `#id`s, number of `.class`es + `:root`,
   number of types), compared left to right — so `.sidebar.open` is
   `(0, 2, 0)` and beats `.sidebar` `(0, 1, 0)` *no matter where each rule
   sits*.
6. **Custom properties.** `--*` declarations cascade with inheritance (a node
   inherits its parent's map; `:root` declarations reach every node). A value
   such as `span var(--scupper-sidebar-span)` is resolved by substituting the
   `--scupper-sidebar-span` value of the node that consumes it, recursively.
7. **Comparison.** Final property values are compared after normalization:
   lowercased, whitespace collapsed, spaces around `( ) , : ; /` removed —
   `repeat(12, 1fr)` and `1 / -1` compare equal to their forms above.

## 5. What is checkable

### 5.1 Structural checks (against the stylesheet alone)

1. The `:root` rule declares **all 14 `--scupper-*` properties above with
   exactly the values listed**.
2. The stylesheet contains a `@media` block whose conditions include
   `(min-width: 1280px)` and one whose conditions include
   `(max-width: 767px)` — consistent with the two `--scupper-bp-*` values.
3. The stylesheet contains `@container` blocks with `(min-width: 480px)`
   targeting `.stat`, and with `(min-width: 720px)` and `(min-width: 960px)`
   targeting `.card` — and in each such block the rule targeting the class
   must actually declare the contracted `grid-column` value (resolving to
   `span 2` for the 480px/.stat and 720px/.card blocks, `span 3` for the
   960px/.card block, through custom properties if you like). A block at a
   wrong threshold, or one that does not carry the declaration, does not
   satisfy this check.
4. Every named `--scupper-*` property **except the two `--scupper-bp-*`
   aliases** is consumed by at least one `var(...)` reference somewhere in
   the sheet (theme-ability: the layout must be driven by the tokens, not
   literals).
5. The selectors `.sidebar` and `.sidebar.open` both exist, and the computed
   specificity `(0, 2, 0)` of `.sidebar.open` strictly exceeds `(0, 1, 0)` of
   `.sidebar`.
6. `/app/dashboard.html` meets every markup requirement in section 1.

### 5.2 Behavioural checks (four hidden viewport fixtures)

Each hidden fixture documents a viewport plus a DOM tree and the
engine-reported widths of the container nodes. The verifier resolves your
stylesheet for each fixture and requires the resolved values below.

| fixture | viewport | sidebar width | card-grid width | resolved values required |
|---|---|---|---|---|
| **desktop** | 1440 | 480 | 960 | `shell`: `display: grid`; `grid-template-columns: repeat(12, 1fr)`; `gap: 16px`; `container-type: inline-size`. `topbar`: `grid-column: 1 / -1`. `sidebar`: `grid-column: span 4`; `background: #1e293b`; `container-type: inline-size`. `main`: `grid-column: span 8`. `card-grid`: `container-type: inline-size`. `card`: `grid-column: span 3`; `background: #ffffff`. `stat`: `grid-column: span 2`; `background: #e2e8f0` |
| **tablet** | 1024 | 84 | 939 | `sidebar`: `grid-column: span 1`; `background: #1e293b`. `main`: `grid-column: span 11`. `card`: `grid-column: span 2`. `stat`: `grid-column: span 1`; `background: #e2e8f0` |
| **mobile-open** | 600 | 90 | 600 | `sidebar`: `display: none`; `background: #0f172a`. `main`: `grid-column: span 12`. `card`: `grid-column: span 1`; `background: #ffffff`. `stat`: `grid-column: span 1` |
| **desktop-mixed** | 1440 | 460 | 880 | `sidebar`: `grid-column: span 4`; `background: #1e293b`. `main`: `grid-column: span 8`. `card`: `grid-column: span 2`; `background: #ffffff`. `stat`: `grid-column: span 1`; `background: #e2e8f0` |

Read those rows as final resolved values after media layering, container
resolution, specificity, inheritance and `var()` substitution — e.g. *tablet*
`sidebar grid-column` is `span 1` because only the base rule applies (the
1280px band is off), and it resolves to `span 1` through
`var(--scupper-rail-span)`; *mobile-open* proves the specificity override
because the resting background (`#1e293b`) must lose to `.sidebar.open`
(`#0f172a`) despite the `open` class sitting on the same element. In the
desktop row the two container queries both fire for `.card`; the required
`span 3` is the *source-order* winner. The *desktop-mixed* row has an
*expanded viewport* (1440px: media band ≥1280 applies, so the sidebar spans 4
and `.main` spans 8) but *sub-threshold containers* (sidebar 460px < 480px =>
stats stay 1-up; card-grid 880px in the 720px..959px band => cards 2-up). The
container widths there are engine-reported, not derivable from the viewport;
this is the row that makes it impossible to fake the container-query axis
with viewport-keyed media rules.

## 6. Tolerance and failure policy

The verifier **tolerates**: comment blocks; arbitrary whitespace, line breaks
and casing (`1280PX` = `1280px`); extra custom properties; extra rules in the
supported subset; `*` or `@keyframes`-style constructs you add (skipped with a
notice — they satisfy nothing). It **fails** on: any missing/incorrect named
custom property, any missing required media/container condition, any mismatch
in the behavioural table above, a missing `.sidebar`/`.sidebar.open` (or a
specificity tie), a required container block that does not carry the
contracted declaration (section 5.1.3), an HTML document that violates
section 1, an unreadable required rule, or a missing deliverable. There is no
partial credit.

## 7. Working notes

- Design the layering first (base vs `@media` vs `@container`), then check your
  cascade against every cell of the behavioural table by hand — five resolved
  outcomes (rail/expanded/hidden sidebar, 2-up/3-up cards, 2-up stats) hang
  off a few rules.
- You can validate locally with a small Python script using the installed
  `tinycss2` if you like, but be careful to implement the *same* semantics
  documented in section 4; the simplest reliable check is reading section 5
  against your file.
- Do not modify anything under `/app/fixtures/`; the verifier reads only your
  two deliverables and its own hidden fixtures.