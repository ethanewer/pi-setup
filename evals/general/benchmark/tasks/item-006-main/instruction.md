In `/app/pov2/` there is a legacy renderer from the POV-Ray-2.2 era (mid-1990s C++). It reads a small POV-style scene file (`scene.pov`), renders flat-shaded spheres, and writes a binary P6 PPM image. It compiled fine in the 1990s, but the legacy C++ no longer compiles with a modern C++ compiler. Your job: make it build, run it, and produce the artifact it is supposed to produce.

Layout:

```
/app/pov2/
  configure        legacy build-script (generates Makefile from Makefile.in)
  Makefile.in
  render.cpp       the renderer source (legacy style - does not compile yet)
  scene.pov        the input scene - IMMUTABLE input, never modify it
  validate.py      rendered-artifact checker - DO NOT MODIFY
  README.md
```

Task:

1. **Fix the legacy source so it compiles** with the installed C++ compiler. The `render.cpp` is written in pre-ANSI C++ style and a modern compiler rejects it. Diagnose each compile error (e.g. functions called without prior declarations, ancient function-definition syntax, a missing standard header) and patch `render.cpp` minimally. Do not change the rendering algorithm or the scene format — only fix the language issues.

2. **Build with the legacy autoconf-style flow**:

   ```
   cd /app/pov2
   ./configure
   make
   ```

   (This produces the `render` binary.)

3. **Render the scene** (the renderer reads `scene.pov` from the current directory and writes `out.ppm` by default):

   ```
   cd /app/pov2
   ./render
   ```

4. **Validate with the rendered artifact**. Run the supplied checker:

   ```
   python3 validate.py
   ```

   It re-derives the expected image from `scene.pov` independently and compares every pixel of `out.ppm`. It prints `PERFECT MATCH` on success and a mismatch description otherwise. Keep fixing until it reports a perfect match.

Constraints:

- `scene.pov` and `validate.py` must not be modified (immutable inputs).
- Do not install additional packages — the compiler and python3 already exist.
- Final state: `./configure && make` builds `render`, running `./render` produces `/app/pov2/out.ppm`, and `python3 validate.py` reports `PERFECT MATCH`.