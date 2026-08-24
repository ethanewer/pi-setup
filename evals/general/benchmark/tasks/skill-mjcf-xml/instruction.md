In `/app/model` there is a MuJoCo model file `pendulum.xml` (MJCF). It is well-formed XML, but it describes the wrong kinematics for the intended system: the `slider` body should slide along an axis, so its joint must be a `slide` joint, not a `hinge` joint.

Edit `/app/model/pendulum.xml` so that:

1. It remains **well-formed XML** (parsable with Python's `xml.etree.ElementTree`).
2. The `joint` element with `name="j0"` inside `body name="slider"` has `type="slide"` (instead of `type="hinge"`).
3. The `body name="slider"` still contains a geometry child element whose `type` attribute is one of the valid MuJoCo geom types (`box`, `sphere`, or `capsule`).

Do not remove or rename the `<mujoco>` root, the `<default>` block, or the `<worldbody>`/`slider` structure. Do not add attributes beyond those already described.

Then also create `/app/report.txt` containing exactly the single line:

```
joint type slide
```