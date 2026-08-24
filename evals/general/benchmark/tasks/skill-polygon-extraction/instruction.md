# Extract a polygon from SVG

`/app/shape.svg` is an SVG file containing exactly one `<polygon>` element whose `points` attribute lists vertex coordinates as `"x,y x,y ..."`.

Do the following **polygon extraction**:

1. Parse the SVG and extract the polygon's vertex coordinates (integer x,y pairs, in the order they appear in the `points` attribute).
2. Write every vertex to `/app/polygon.txt`, one per line, as `x,y` ("x" comma "y", no spaces). Order does not matter here — the verifier compares this as a **set** (so also sort yours for tidiness if you like).
3. Compute the polygon's **area** using the shoelace formula over the vertices **in their original order**:
   `area = 0.5 * | Σ (x_i * y_{i+1} − x_{i+1} * y_i) |` (with wrap-around from the last vertex back to the first).
4. Compute the **perimeter** as the sum of Euclidean edge lengths between consecutive vertices (with wrap-around).
5. Write the area to `/app/area.txt` and the perimeter to `/app/perimeter.txt`, each formatted as a decimal rounded to exactly 4 places after the point (e.g. `900.0000`).

The verifier re-parses `shape.svg` independently, recomputes the expected vertex set, area, and perimeter from the original point order, and checks `/app/polygon.txt` (set match), `/app/area.txt`, and `/app/perimeter.txt` (each within a small tolerance).

Python's standard library is sufficient (`re`, `math`).