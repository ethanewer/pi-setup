# Loomsign mural firmware — compressed parametric renderer

Loomsign builds marquee signboards. Each board's firmware renders a "dither
mural" from a tiny parametric spec, and the renderer source is pushed to the
boards over a very narrow radio link: the **gzip-compressed source must fit a
hard byte budget**, and the source must compute the mural from arithmetic — it
must **not carry the image inside itself** (no embedded pixel rows, no embedded
palette art).

## Deliverables (all three required)

1. `/app/mural.py` — the renderer:
   ```
   python3 /app/mural.py <spec.json> <out.txt>
   ```
   It reads a spec and writes the mural to `<out.txt>` as **UTF-8 text**. It
   must work on **any** spec conforming to the contract below, not only the
   shipped one.

2. `/app/frame.txt` — the mural your renderer produces for the shipped
   `/app/spec.json`:
   ```
   python3 /app/mural.py /app/spec.json /app/frame.txt
   ```

3. `/app/mural-sizes.json` — the **real measured sizes** of your
   `/app/mural.py`, as a JSON object with exactly these keys:
   ```json
   { "source_bytes": 331, "gzip_bytes": 214 }
   ```
   * `source_bytes` = byte length of `/app/mural.py`.
   * `gzip_bytes` = `len(gzip.compress(source_bytes))` using Python's `gzip`
     module defaults (compresslevel 9).

## Spec format

A spec is a JSON object:
```json
{
  "width": 64,
  "height": 24,
  "palette": " .,:;i1tfLCG08@",
  "coef": [3, 5, 1, -2, 7, 4],
  "mods": [7, 5]
}
```

* `palette` — the character ramp (length `P` >= 1, may be any non-empty
  Unicode string, may contain spaces).
* `coef` — exactly six integers `[c0, c1, c2, c3, c4, c5]` (may be negative).
* `mods` — exactly two integers `[m3, m4]`, each **>= 1**.

## Output contract (byte-exact)

For row `y` in `0 .. height-1` and column `x` in `0 .. width-1`, the character
is:

```
i(x, y) = ( c0*x + c1*y + c2*x*y + c3*(x*x mod m3) + c4*(y*y mod m4) + c5 ) mod P
char(x, y) = palette[i(x, y)]
```

(`mod` is Python's `%` on integers; the `(x*x mod m3)` and `(y*y mod m4)`
terms are computed with Python's non-negative `%` on the squared values.)

The output file contains exactly `height` lines, each line exactly `width`
characters, and **every** line (including the last) is terminated by a single
`\n`. Nothing else may be written.

## Size and content gates (enforced by the verifier)

* **Raw gate:** the byte size of `/app/mural.py` must be **<= 800**.
* **Gzip gate:** `gzip_bytes` of `/app/mural.py` (as defined above) must be
  **<= 320**.
* **No-embedding rule:** the source of `/app/mural.py` must not contain any
  complete output line of a mural it renders (any rendered line of length >= 8
  that mixes at least two distinct characters), and must not contain any
  palette literal of length >= 8 (e.g. the shipped palette string may not
  appear verbatim in the source). The mural must come from arithmetic at run
  time.
* `/app/mural-sizes.json` must equal the **actually measured** sizes of the
  final `/app/mural.py` — stale or faked numbers fail.

## Edge cases the verifier probes (hidden specs)

* A **1x1** mural (single character, single line).
* A **single-row** mural (`height = 1`, wide).
* A **single-character palette** (`P = 1` — every cell is the same char).
* A **Unicode palette** (multi-byte characters; output is UTF-8).
* A **large** mural (e.g. 80x48) with **negative coefficients** — the `% P`
  normalization must handle negative sums exactly as Python does.

## Constraints

* Deterministic, standard library only, no network at run or verify time.
* Do not modify `/app/spec.json`.
* The verifier re-runs `/app/mural.py` unchanged on the hidden specs and
  compares the output byte-for-byte against the contract above, and re-checks
  both size gates, the sizes report, and the no-embedding rule each time.
