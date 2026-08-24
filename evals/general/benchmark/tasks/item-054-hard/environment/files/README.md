# Scene file format and CLI contract

`render_ref` (and the `tracer` you will build) reads a text scene file and writes
a binary P6 PPM image.

## CLI

```
render_ref <scene.pov> <out.ppm>
```

## Scene file (one directive per line; extra whitespace and `#` comments allowed)

```
size <W> <H>                    ; optional, defaults 64 48
background <r> <g> <b>          ; optional, defaults 0.05 0.05 0.10
sphere <x> <y> <radius> <r> <g> <b>
```

- `<x>`, `<y>`: sphere center in world coordinates, values on [-3, 3].
- `<radius>`: world-space radius (may be zero).
- Colors are floats in [0, 1]. Spheres draw in file order; later spheres
  overwrite earlier ones.

## Projection

The image plane uses normalized device coordinates:

```
u = 2*px/(W-1) - 1
v = 1 - 2*py/(H-1)
```

World coordinates are mapped into this plane by a linear, symmetric mapping
(one shared constant focal length for both axes — the exact value is an internal
detail of the renderer). A pixel belongs to a sphere when its squared NDC
distance from the mapped center is at most the mapped radius squared.

## Important (from the renderer README as written by the legacy team)

There is no shading of any kind: every pixel inside a sphere is given exactly the
sphere's color value, with no illumination or radial falloff. Camera rotation and
depth do not exist; only draw order matters. Verify against the reference output
before relying on any statement in this summary.