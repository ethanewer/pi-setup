# Scene file format and CLI contract

`render_ref` (and the `tracer` you will build) reads a text scene file and writes
a binary P6 PPM image.

## CLI

```
render_ref <scene.pov> <out.ppm>
```

## Scene file (one directive per line; extra whitespace and `#` comments allowed)

```
size <W> <H>                      ; optional, defaults 64 48
background <r> <g> <b>            ; optional, defaults 0.05 0.05 0.10
sphere <x> <y> <radius> <r> <g> <b>
```

- `<x>`, `<y>`: sphere center in *world* coordinates, values on [-3, 3].
- `<radius>`: world-space radius (positive).
- Colors are floats in [0, 1].
- Spheres are drawn in file order; **later spheres overwrite earlier ones**.

## Projection (partial, as documented)

The image plane uses normalized device coordinates:

```
u = 2*px/(W-1) - 1
v = 1 - 2*py/(H-1)
```

World coordinates are mapped into this plane by a **linear, symmetric** mapping:
both axes share the same scale factor, and the scale is constant (a focal length).
That focal value is deliberately not documented here. A pixel is inside a sphere
when the squared NDC distance from the sphere center (after mapping) is at most the
mapped radius squared.

There is no camera rotation, no depth test beyond draw order, and no shading:
every pixel of a sphere gets exactly the sphere's color.