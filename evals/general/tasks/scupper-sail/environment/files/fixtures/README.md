# /app/fixtures — input documentation

These files describe the *viewport fixtures* the verifier resolves your
stylesheet against. They are reference material only: the verifier never reads
them, and the hidden fixtures it does read follow the same schema with
different values. Do not modify this directory.

## Schema

```json
{
  "viewport_width": 1440,
  "root": {
    "tag": "div", "id": "app", "class": "app",
    "children": [ { "tag": "div", "class": "shell", "children": [
      { "tag": "header", "class": "topbar" },
      { "tag": "aside", "class": "sidebar", "width": 480, "children": [
        { "tag": "div", "class": "stat" }
      ]},
      { "tag": "main", "class": "main", "children": [
        { "tag": "div", "class": "card-grid", "width": 1280, "children": [
          { "tag": "div", "class": "card" }
        ]}
      ]}
    ]}
  ]}
}
```

- `viewport_width` — the viewport used to evaluate `@media` conditions.
- Every node may carry `tag` (default `div`), `id`, `class` (space-separated)
  and `children`. The first node is the document root (`:root` matches it; the
  `#app` element).
- Container nodes carry `width` — the inline size the layout engine reports
  for them, used to evaluate `@container` conditions against the **nearest
  ancestor** whose resolved `container-type` is `inline-size`. Nodes without a
  `width` use the viewport width.

`visible.json` below is a desktop-regime example (1920px viewport): work
through the section-5 table of the instruction against it to check your
understanding of the resolution semantics.