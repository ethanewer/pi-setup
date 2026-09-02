# Ivory Shoal — design a circular plasmid tag under a window-composition rule

The Ivory Shoal estuary survey attaches synthetic DNA tags to its sampling
beacons. Each tag is a **circular** plasmid read: there is no origin, so
composition constraints apply to every sliding window **including the ones
that wrap around the ends**. You must write a reusable tag-designer program
and run it once to produce the shipped tag.

## Deliverables (both required)

1. `/app/plasmid.py` — the designer with exactly this CLI:
   ```
   python3 /app/plasmid.py <out_path> <length> <window> <lo> <hi> <pair>
   ```
2. `/app/plasmid_out.txt` — the tag produced by the visible run:
   ```
   python3 /app/plasmid.py /app/plasmid_out.txt 1200 80 32 44 GC
   ```

## Required output format

`<out_path>` receives a text file whose entire content is **exactly one line
of `<length>` characters** drawn from `A`, `C`, `G`, `T`, followed by a single
trailing newline. No other whitespace anywhere.

## Composition constraint

Let `<pair>` be two distinct letters from `{A,C,G,T}` (e.g. `GC`; the order
of the two letters does not matter — `CG` and `GC` mean the same set). For
**every** contiguous circular window of exactly `<window>` bases — there are
`<length>` such windows, one starting at each position, and windows that run
past the end wrap around to the beginning — the percentage

```
100 * (number of bases from <pair> inside the window) / <window>
```

must lie within `[lo, hi]` **inclusive**. `lo` and `hi` are decimal numbers
(e.g. `32`, `55.5`).

## Additional hard constraints

- **All four bases appear** at least once in the tag.
- **No homopolymer run longer than 4**: you never see the same letter more
  than 4 times consecutively (checking across the circular seam too).

## Input guarantees (a valid tag always exists)

- `length` is an integer `>= 100`; `5 <= window <= length`.
- `0 <= lo <= hi <= 100`.
- There exists an integer `k` with
  `max(2, ceil(lo*window/100)) <= k <= min(window-3, floor(hi*window/100))`.
- `<pair>` is two distinct letters of `ACGT`, uppercase.

## A correct construction recipe (you may use any method)

Tile a **period-block of length `window`** containing exactly `k` pair-bases
(the guaranteed integer above), then repeat the block and truncate to
`<length>`. Because the tag is periodic with period `window`, every circular
window is a rotation of the block and therefore contains exactly `k`
pair-bases. Inside the block, alternate the two pair letters at the chosen
pair positions and fill remaining positions by alternating the two other
letters — this keeps every homopolymer run short. Self-check your output
before writing it.

## Edge cases the grader probes with hidden runs

- Different `length` / `window` combinations (including `window` close to
  `length`, and much smaller).
- Fractional percentage bounds (e.g. `55.5`), and tight ranges where only a
  couple of integer counts `k` are feasible.
- Pair sets beyond `GC` (e.g. `AG`, `CA`) — the two **constrained** bases are
  whichever the argument names; the other two bases just need to appear.
- The circular seam: a window that starts near position `length-1` and wraps
  to the beginning is checked exactly like any other.

## Constraints

- The grader runs `/app/plasmid.py` **unchanged** with hidden arguments — do
  not hard-code the visible parameters or the pair `GC`.
- Exit status `0` on success.
- No network access; Python 3.12 standard library only.
