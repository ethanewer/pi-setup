"""The default theme: assets and templates shipped with quaydoc.

The theme is deliberately small — one stylesheet, one script, one sidebar
template.  Custom themes can provide their own ``assets/`` and
``templates/`` next to a ``quaydoc.toml``; the default is used when a theme
is not configured.
"""

from __future__ import annotations

import os

from quaydoc.util import ensure_dir, write_text

ASSET_DIR = "assets"

DEFAULT_CSS = """/* quaydoc default theme */
:root {
  --ink: #1f2937;
  --muted: #6b7280;
  --accent: #0f766e;
  --bg: #ffffff;
  --panel: #f3f4f6;
  --border: #e5e7eb;
  --code-bg: #f8f8f8;
}
* { box-sizing: border-box; }
html { color-scheme: light; }
body {
  margin: 0;
  font-family: ui-sans-serif, system-ui, "Segoe UI", Helvetica, Arial, sans-serif;
  font-size: 16px;
  line-height: 1.6;
  color: var(--ink);
  background: var(--bg);
  display: grid;
  grid-template-columns: 16rem 1fr 15rem;
  grid-template-rows: auto 1fr auto;
  grid-template-areas:
    "header header header"
    "sidebar main toc"
    "footer footer footer";
  min-height: 100vh;
}
.site-header { grid-area: header; padding: 0.75rem 1.5rem; border-bottom: 1px solid var(--border); }
.brand { font-weight: 700; letter-spacing: 0.02em; }
.nav-toggle { display: none; }
.sidebar {
  grid-area: sidebar; padding: 1.25rem 1rem; align-self: start;
  overflow: auto; position: sticky; top: 0;
}
.nav-row { padding: 0.1rem 0 0.1rem 0; }
.nav-depth-1 a { font-weight: 600; }
.nav-depth-2 a { color: var(--muted); }
.nav-depth-3 a { color: var(--muted); font-size: 0.92rem; }
a.nav-link.active { color: var(--accent); font-weight: 700; }
.main { grid-area: main; padding: 1.5rem 2rem; min-width: 0; }
.content { max-width: 46rem; }
h1 { font-size: 1.85rem; margin-top: 0; }
h2 { font-size: 1.4rem; border-bottom: 1px solid var(--border); padding-bottom: 0.2rem; }
h3 { font-size: 1.2rem; }
h4, h5, h6 { font-size: 1.05rem; }
p { margin: 0.9rem 0 0.9rem 0; }
ul, ol { padding-left: 1.5rem; }
li { margin: 0.25rem 0; }
blockquote {
  margin: 1rem 0; padding: 0.5rem 1rem;
  border-left: 4px solid var(--border); color: var(--muted);
  background: var(--panel); border-radius: 0.25rem;
}
code { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
code:not(.language-*) { background: var(--code-bg); padding: 0.1em 0.35em; border-radius: 0.2em; }
pre.highlight { background: var(--code-bg); padding: 0.9rem 1rem; border-radius: 0.4rem; overflow-x: auto; }
pre.highlight code { background: transparent; display: block; }
.tok { font-weight: 600; }
.tok-keyword { color: #7c3aed; }
.tok-string { color: #16a34a; }
.tok-number { color: #d97706; }
.admonition { border-radius: 0.4rem; margin: 1rem 0; padding: 0.75rem 1rem; }
.admonition-title { margin: 0 0 0.4rem 0; font-weight: 700; }
.admonition-note { background: #eef2ff; border-left: 4px solid #6366f1; }
.admonition-tip { background: #ecfdf5; border-left: 4px solid #22c55e; }
.admonition-info { background: #eff6ff; border-left: 4px solid #0ea5e9; }
.admonition-warn { background: #fffbeb; border-left: 4px solid #f59e0b; }
.admonition-danger { background: #fef2f2; border-left: 4px solid #ef4444; }
hr { border: none; border-top: 1px solid var(--border); margin: 1.5rem 0; }
a.missing { text-decoration: underline wavy #ef4444; }
img { max-width: 100%; }
.toc-panel { grid-area: toc; padding: 1.25rem 1rem; position: sticky; top: 0; align-self: start; }
.toc-panel h2 { font-size: 0.95rem; border: none; }
ul.toc { list-style: none; padding-left: 0.85rem; font-size: 0.9rem; }
ul.toc a.current { color: var(--accent); }
.site-footer { grid-area: footer; padding: 0.75rem 1.5rem; color: var(--muted); font-size: 0.85rem; }
@media (max-width: 860px) {
  body { grid-template-columns: 1fr; grid-template-areas: "header" "main" "footer"; }
  .sidebar, .toc-panel { display: none; }
  .nav-toggle { display: inline-block; margin-left: 1rem; }
}
@media print {
  body { grid-template-areas: "header" "main" "footer"; }
  .sidebar, .toc-panel, .site-header { display: none; }
  .main { padding: 1rem 2rem; }
  pre.highlight { white-space: pre-wrap; }
}
.section-number { color: var(--muted); font-weight: 500; margin-right: 0.35em; }
table.doc-table {
  border-collapse: collapse; margin: 1rem 0; font-size: 0.95em;
  width: 100%; background: var(--bg);
}
table.doc-table th, table.doc-table td {
  border: 1px solid var(--border); padding: 0.4rem 0.75rem; text-align: left;
}
table.doc-table th { background: var(--panel); }
table.doc-table tr:nth-child(even) td { background: #fafafa; }
dl.definition-list dt { font-weight: 600; margin-top: 0.4rem; }
dl.definition-list dd { margin: 0 0 0.6rem 1.4rem; color: var(--muted); }
section.footnotes { border-top: 1px solid var(--border); margin-top: 2rem; font-size: 0.9rem; }
section.footnotes ol { padding-left: 1.2rem; }
sup.footnote-ref { font-size: 0.75em; }
input.task-check { margin-right: 0.4rem; vertical-align: middle; }
aside.toc-panel ul.toc .current { font-weight: 600; }
div.diagram { border: 1px dashed var(--border); border-radius: 0.4rem; padding: 0.6rem 1rem; }
div.diagram pre.diagram-source { font-size: 0.9rem; color: var(--muted); }
"""

SEARCH_JS = """/* quaydoc search page */
(function () {
  "use strict";
  var input = document.getElementById("search-input");
  var results = document.getElementById("search-results");
  var data = [];
  function load() {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", "/search_index.json", true);
    xhr.onreadystatechange = function () {
      if (xhr.readyState === 4 && xhr.status === 200) {
        try { data = JSON.parse(xhr.responseText); } catch (e) { data = []; }
        run();
      }
    };
    xhr.send();
  }
  function run() {
    var q = (input.value || "").toLowerCase().split(/\\s+/).filter(Boolean);
    if (!q.length) { results.innerHTML = ""; return; }
    var hits = data
      .map(function (entry) {
        var text = (entry.title + " " + entry.text).toLowerCase();
        var score = 0;
        q.forEach(function (term) {
          if (text.indexOf(term) >= 0) { score += 1; }
        });
        return { entry: entry, score: score };
      })
      .filter(function (hit) { return hit.score > 0; })
      .sort(function (a, b) { return b.score - a.score; });
    results.innerHTML = hits
      .slice(0, 20)
      .map(function (hit) {
        return '<li><a href="' + hit.entry.url + '">' +
          hit.entry.title + "</a></li>";
      })
      .join("");
  }
  input.addEventListener("input", run);
  load();
})();
"""

DEFAULT_JS = """/* quaydoc default theme: mobile nav toggle */
(function () {
  "use strict";
  var sidebar = document.querySelector(".sidebar");
  var toggle = document.querySelector(".nav-toggle");
  if (!sidebar || !toggle) { return; }
  toggle.addEventListener("click", function () {
    var visible = sidebar.style.display === "block";
    sidebar.style.display = visible ? "none" : "block";
  });
})();
"""

NAV_TEMPLATE = """{% for item in nav %}<div class="nav-row nav-depth-{{ item.depth }}">
<a class="nav-link{% if item.url == current %} active{% endif %}" href="{{ item.url|escape }}">{{ item.title|escape }}</a>
</div>
{% endfor %}"""

SEARCH_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Search · {{ site_title|escape }}</title>
<link rel="stylesheet" href="/assets/style.css">
</head>
<body>
<header class="site-header"><span class="brand">quaydoc</span></header>
<main class="content">
<h1>Search</h1>
<form id="search-form" action="#" method="get">
  <input id="search-input" type="search" name="q" placeholder="Search the docs" autofocus>
  <button type="submit">Search</button>
</form>
<ul id="search-results"></ul>
</main>
<script src="/assets/quaydoc.js"></script>
<script src="/assets/search.js"></script>
</body></html>
"""

TEMPLATES = {
    "nav.html": NAV_TEMPLATE,
    "search.html": SEARCH_TEMPLATE,
}

JS_FILES = {"quaydoc.js": DEFAULT_JS, "search.js": SEARCH_JS}
CSS_FILES = {"style.css": DEFAULT_CSS}


def write_assets(outdir):
    """Copy the default stylesheet and script into ``outdir``/assets."""
    target = ensure_dir(os.path.join(outdir, ASSET_DIR))
    for name, body in CSS_FILES.items():
        write_text(os.path.join(target, name), body)
    for name, body in JS_FILES.items():
        write_text(os.path.join(target, name), body)
