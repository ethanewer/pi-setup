Legacy POV-Ray-2.2-era renderer ("pov") with a rendering defect.

* `render.cpp` - pre-ANSI C++ renderer (does not compile on a modern C++ compiler)
* `configure` + `Makefile.in` - the legacy build flow
* `scene.pov` - input scene (IMMUTABLE)
* `validate.py` - independently rebuilds the expected image from `scene.pov`
  and compares with `out.ppm`

There are two classes of problems to solve (validate.py tells you when you are
done):
1. Legacy C++ language errors (functions without prior prototypes, ancient K&R
   function definition syntax, a missing standard header).
2. A *rendering defect* in the code (the rendered spheres are not the correct
   size). validate.py reports pixel mismatches; diagnose what is wrong with the
   apparent-sphere math and patch it minimally. Do not change the scene.

    ./configure && make && ./render && python3 validate.py
