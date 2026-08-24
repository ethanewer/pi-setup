Legacy POV-Ray-2.2-era renderer ("pov").

* `render.cpp` - pre-ANSI C++ renderer: reads `scene.pov` (spheres + background),
  renders flat-shaded spheres to a binary P6 PPM, writes `out.ppm`.
* `configure` + `Makefile.in` - the legacy build flow (generates `Makefile`).
* `validate.py` - independently rebuilds the expected image from `scene.pov`
  and compares it pixel-by-pixel with `out.ppm` ("PERFECT MATCH" on success).

The source compiles only with an old C++ compiler; a modern compiler rejects
it. Fix the legacy language issues (do not change the algorithm), then:

    ./configure && make && ./render && python3 validate.py