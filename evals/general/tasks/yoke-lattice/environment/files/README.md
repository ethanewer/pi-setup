# yoke

A small lattice-grid toolkit used as the demo repository for the local CI
runner in the `yoke-lattice` task.

The package exposes:

- `yoke.lattice.Grid` — parse, render, transpose and join fixed-width tile
  grids, and find *yokes* (rows fully covered by a single tile code).
- `python -m yoke lint <paths...>` — a trivial style gate (trailing
  whitespace, tabs, CRLF, unresolved merge markers, malformed `.grid` files).
- `python -m yoke build` — assemble a reproducible `dist/yoke-<version>.tar.gz`.
- `python -m yoke render <file.grid>` — render a grid with its yokes annotated.

```
$ python3 -m pytest -q tests
$ make all
```

Everything here is intentionally plain-ASCII, tab-free and merge-marker-free;
the lint gate above is designed to pass on this tree.