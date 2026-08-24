# Scene parameter inference

`/app/render.ppm` contains a rendered grayscale scene in **P2 (text) PPM format**. The scene shows exactly one object: a **sphere** rendered as a bright disc against a dark background, lit by a **single distant light source** with **Lambertian (diffuse) shading** plus a constant ambient term.

Your job: infer the sphere's scene parameters from the pixel data alone and write them to `/app/scene_params.json`.

## Background

Each pixel's grayscale value `v` is

```
v = ambient + K * max(0, dot(n, L))
```

where `n` is the unit sphere surface normal at that pixel (pointing out of the sphere toward the camera) and `L` is the unit vector pointing **from the sphere center toward the light**. The brightest point on the sphere is where `n` is most aligned with `L`: the light source's bearing is the bearing from the sphere center to that brightest pixel.

The image is `80 x 80` pixels. The background is a flat dark gray `15`. Pixels inside the sphere have values of at least `30` (the ambient term), so any pixel with value `> 20` belongs to the sphere disc.

## What to compute

Write a Python program at `/app/infer.py` that reads `/app/render.ppm` and computes, using exactly this procedure:

1. Parse the P2 PPM (header: `P2`, width, height, maxval 255, then row-major values).
2. Collect "disc pixels": all pixels whose value is `> 20`.
3. From the bounding box of the disc pixels:
   - `cx = round((min_x + max_x) / 2)`
   - `cy = round((min_y + max_y) / 2)`
   - `radius = round((max_x - min_x) / 2)`
4. Find the pixel with the **maximum** grayscale value. If several pixels tie, take the one that appears **first** when scanning rows top-to-bottom, then columns left-to-right (smallest `y`, then smallest `x`). Call it the light pixel `(bx, by)`.
5. Compute the light's bearing from the sphere center in degrees, in the image plane (positive x = east, positive y = south):
   ```
   azimuth_deg = round(degrees(atan2(by - cy, bx - cx)) mod 360, 1)
   ```
   (`atan2` from the `math` module.)

## Output

Write `/app/scene_params.json`:

```json
{
  "cx": 40,
  "cy": 45,
  "radius": 15,
  "azimuth_deg": 233.1
}
```

(a real example — your values must come from inferring the actual image). `cx`, `cy`, `radius` are integers; `azimuth_deg` is a float rounded to 1 decimal place. Only the Python standard library is required. Run the program so the JSON file exists at the end.