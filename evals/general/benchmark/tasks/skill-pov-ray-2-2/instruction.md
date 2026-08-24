# POV-Ray scene description

Write a **POV-Ray** scene source file at `/app/scene.pov`. POV-Ray (Persistence of Vision Raytracer, including the 2.x/3.x SDL "scene description language") describes a 3-D scene that the renderer traces to an image.

The file must satisfy all of these structural checks (case-insensitive):

1. It must start with a `#include` directive that loads a POV-Ray include file — e.g. `#include "colors.inc"`.
2. It must contain a **`camera`** declaration block that names a viewing `location` and a `look_at` point (e.g. `` camera { location <0,0,-10> look_at <0,0,0> } ``).
3. It must contain at least one **`light_source`** declaration (e.g. `` light_source { <0,10,-20> color rgb <1,1,1> } ``).
4. It must contain at least one **`sphere`** object declaration (e.g. `sphere { <0,0,0>, 1 }`), and that sphere block must include a **`pigment`** sub-block whose color is written with the `rgb` keyword before packed intensity values (e.g. `pigment { color rgb <1,0,0> }`).

Write the file to `/app/scene.pov`. The verifier inspects it as plain text for the elements above; it does not run a renderer. Use standard POV-Ray 2.x/3.x SDL syntax so the scene would be parseable by a real POV-Ray interpreter.