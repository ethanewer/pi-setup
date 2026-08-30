# Procedural image renderer

Build a small, well-documented procedural renderer. You will write one program
that turns a JSON "scene description" into a **P6 binary PPM image** by filling
in primitive shapes in painter order. Your program must be a **reusable tool**
that works on any scene JSON following the documented contract below, not just
on the one shipped example.

## Working environment

- You work inside `/app`. A scene description is at `/app/scene.json`.
- Python 3.12 is available. You may write the program in any language, but
  Python 3 is recommended and the evaluator invokes it as `python3`.
- **Do not modify** any input file, `/app/scene.json` in particular. Your
  renderer reads it; it must never write back to it. (The verifier also feeds
  it entirely separate scene files under its own control.)

## Deliverable

- `/app/render.py` — a script runnable as:

  ```
  python3 /app/render.py <scene.json path> <output.ppm path>
  ```

  It must work for **any** valid scene file, not just the shipped one. The
  input path and output path are passed as command-line arguments (positions 1
  and 2). It should not hard-code any scene data.

Also produce `/app/output.ppm` by running your renderer on `/app/scene.json`
(so the output artifact is a real rendering of the provided scene).

## Scene format

```json
{
  "width": 8, "height": 6,
  "background": [12, 18, 24],
  "primitives": [
    {"type": "rect",   "x": 2, "y": 1, "w": 4, "h": 3, "color": [220, 80, 40]},
    {"type": "circle", "cx": 1.5, "cy": 1.5, "r": 1.5, "color": [255, 255, 0]},
    {"type": "hline",  "y": 3, "x0": 0, "x1": 7, "color": [0, 0, 255]},
    {"type": "vline",  "x": 4, "y0": 0, "y1": 5, "color": [0, 255, 0]}
  ]
}
```

The canvas `width` x `height` is the image size in pixels. `background` is the
`[R,G,B]` color filled everywhere before any primitive is drawn. The
`primitives` list is in **painter order**: later entries are drawn on top of
earlier ones. Every shape carries its own `color` `[R,G,B]`. All three-tuples
are integer RGB channels already in `0..255`.

## Supported primitives

- `rect`: filled axis-aligned rectangle covering the inclusive integer span
  `[x, x+w-1] × [y, y+h-1]` (`x`, `y`, `w`, `h` are integers).
- `circle`: filled disc centred at `(cx, cy)` with radius `r` (all floats).
  A pixel whose centre `(px+0.5, py+0.5)` is at distance `<= r` from the centre
  is inside, i.e. `(px+0.5 - cx)^2 + (py+0.5 - cy)^2 <= r^2`.
- `hline`: one-pixel-tall horizontal line at row `y` spanning columns
  `x0..x1` **inclusive**; `x0` and `x1` may appear in either order.
- `vline`: one-pixel-wide vertical line at column `x` spanning rows
  `y0..y1` **inclusive**; `y0` and `y1` may appear in either order.

## Edge cases the verifier will probe (you must handle all of these)

1. **Clipping.** Any geometry that falls partially or entirely outside
   `[0, width) × [0, height)` is clipped: only pixels inside the canvas may be
   written, and out-of-range geometry must never cause an error or wrap.
2. **Off-canvas shapes.** A shape entirely outside the canvas (for example a
   rect with negative coordinates, or one far beyond `width`/`height`) draws
   nothing but must not crash.
3. **Zero-size shapes.** `rect` with `w == 0` or `h == 0`, or `circle` with
   `r <= 0`, draw nothing and must not crash.
4. **Painter order.** Overlapping shapes must be drawn back-to-front in the
   order they appear in `primitives`.
5. **Signed / out-of-range endpoints.** Negative and out-of-range coordinates
   must be handled for the `x0/x1`, `y0/y1`, `x`, `y`, `w`, `h` fields.
6. **No hidden reference data.** Your renderer must not embed the answer for a
   specific scene; it computes pixels from whatever input scene you give it.

The hidden verification cases use fresh scenes, fresh coordinates and fresh
numbers exercising the edge cases in items 1-5, so the correct behavior on
arbitrary scenes is what is being graded.

## Output format

Write a **binary P6 PPM** file to the path given as the second argument:

```
P6
<width> <height>
255
```

followed by `width*height` RGB triples (one byte per channel) in **row-major
order, top row first, left to right**. Byte-for-byte deterministic output is
expected; the evaluator compares your `.ppm` to a reference with `cmp`.