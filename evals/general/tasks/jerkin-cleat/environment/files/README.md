# jerkin-cleat workspace

What is here:

- `/app/src` — the upstream source tree of **stb**, a widely used, public-domain
  single-header C image library (project: nothings/stb, pinned to the commit the
  image was built from). Two files matter for this task:

  - `stb_image.h`   — image loading/decoding: image formats, the load API, and
    how failures are reported.
  - `stb_image_write.h` — image writing/encoding.

  Both headers are self-contained: the whole library is compiled into a program
  by defining `STB_IMAGE_IMPLEMENTATION` (resp. `STB_IMAGE_WRITE_IMPLEMENTATION`)
  before including the header. Read the headers. They document every function,
  the supported input formats, the API used to ask for a specific channel count,
  and how the library reports data it cannot decode.

- `/app/fixtures` — sample image files in several formats, plus files that were
  deliberately damaged. Use them to develop against; the graded run uses
  different directories.

- Installed toolchain: gcc / make / git. The container has no network.

See `instruction.md` for the deliverable contract. Do not modify anything in
`/app/src`.