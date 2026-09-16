# kedge-lattice

## Situation

`/app/src` holds the source checkout of **libvips** (`https://github.com/libvips/libvips`),
a real, widely used C image-processing library, pinned to release **v8.18.6**
(commit `426af3f44246fce9cfa8dd51a353aa4dfd48c553`). The checkout is clean:
the project has **not** been built or installed anywhere on this machine.
There is no vips binary on this container yet — part of your job is to
produce one from this source.

This trial has **no network access** and exactly **1 CPU**. Everything the
build needs is already installed in the image; it must not fetch anything
(and cannot).

### Preinstalled
- Build toolchain: gcc (build-essential), make, **meson 1.3.1**, **ninja
  1.11.1**, pkg-config, git
- C development libraries (the project's optional dependencies): libglib2.0-dev,
  libexpat1-dev, libjpeg-dev, libpng-dev, libtiff-dev, libwebp-dev, liblcms2-dev,
  libfftw3-dev
- Utilities: file, binutils (readelf), md5sum, python3

`/app/fixtures/` contains two 8-bit RGBA PNG test images:
`vis1.png` (40 × 30) and `vis2.png` (32 × 44). Do not modify them.

## Deliverables

1. **`/app/vips`** — a full install of the library you built, under the
   prefix `/app/vips`:
   - the command-line tools (including `vips` and `vipsheader`) in
     `/app/vips/bin/`,
   - the shared library `libvips.so.42` somewhere under `/app/vips/lib/`,
   - the C headers under `/app/vips/include/`,
   - the pkg-config file `vips.pc` under `/app/vips/lib/`.
   The install must be genuinely usable: a C program compiled with
   `gcc prog.c $(pkg-config --cflags --libs vips)` must link, and must run
   with `LD_LIBRARY_PATH` pointing at the directory meson placed your
   `libvips.so.42` in. `/app/vips` must contain real ELF binaries built from
   `/app/src` — a wrapper script or a copied binary is not an install.
2. **`/app/out/`** — six processed images produced with the vips toolchain
   you installed, one per step below.

## Task

Navigate the project in `/app/src`, build it the way its own build system
expects, and install it to the prefix `/app/vips`. A correct build of just
what the project itself needs is quick: on one CPU, configuration plus a
single-threaded compile is on the order of a couple of minutes. If what you
are doing takes far longer than that, you are building more than the task
needs (`vips --list-all` names every operation the library offers, and the
library's own `docs/` directory in the checkout describes the command-line
interface).

Then use the **installed** `vips` command-line tool on the two fixtures.
For each `<stem>`.png in `/app/fixtures/` produce three output files:

1. `/app/out/<stem>-rot90.png` — the input image **rotated 90 degrees
   clockwise** (content that was at the top ends up at the right edge; the
   dimensions swap).
2. `/app/out/<stem>-crop.png` — the region of `<stem>-rot90.png` whose
   origin is the top-left corner of that rotated image and which spans
   **exactly half of that rotated image's width and half of its height**
   (keep the top-left half of the rotated image; discard the rest).
3. `/app/out/<stem>-half.png` — `<stem>-crop.png` resampled to **exactly
   half its size in both axes** (scale factor 0.5) using **nearest-neighbour
   sampling**. The dimensions must be the integer results of that 0.5
   rescale of the crop's dimensions.

All six outputs must be 8-bit RGBA PNG files (4 bands, uchar).

The vips CLI exposes each operation as `vips <operation> ...`; running a
vips operation without enough arguments prints its exact usage, and
`vips --list-all` lists the available operation names. You may write helper
scripts anywhere under `/app` (they are yours; only `/app/vips` and
`/app/out` are judged).

## How your work is judged

- The verifier checks that `/app/vips` really is a built install: an ELF
  `vips` binary reporting version 8.18.6, a `libvips.so.42` whose SONAME is
  `libvips.so.42`, headers, and a working pkg-config file.
- The verifier **recomputes** all three outputs from each fixture with your
  installed `vips` binary — the same operations, on the same inputs — and
  compares the resulting pixels with the files you placed in `/app/out`.
  Only a pipeline that produces bit-exact pixels for all three steps
  (rotation, half-crop from the top-left of the rotated image, 0.5
  nearest-neighbour rescale) passes. It also asserts width, height and
  band count of your files.
- The verifier then runs the same three operations with your binary on
  hidden images it supplies, and checks pixel checksums and metadata
  against values computed from an independent build of the same pinned
  source version.
- Finally the verifier compiles a small C program of its own against your
  installed library (using pkg-config) and runs it on those hidden images;
  it must link against your `libvips.so.42` and produce the correct image
  data.

## Constraints

- **Single CPU**: keep parallel compilation at one job (an explicit
  `-j1`-equivalent). 
- Do not alter the fixtures, and do not replace, move, or edit the content
  of `/app/src`: it stays the pinned upstream checkout.
- Do not modify anything outside `/app`. There is no package manager
  activity at trial time: the image already contains every piece the build
  needs.