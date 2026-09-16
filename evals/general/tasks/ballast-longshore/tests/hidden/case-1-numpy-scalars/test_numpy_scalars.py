"""Hidden case: the offset setter must treat numpy numeric scalars whose
value equals 0 or 1 as *numbers*, not as booleans (the bug matched by value
equality, so np.int64(1) == True and np.float64(1.0) == True fell into the
boolean branch and reset the offset to 0)."""
import numpy as np
from matplotlib.ticker import ScalarFormatter

# np.int64(1) compares equal to True; must still be a numeric offset.
f = ScalarFormatter()
f.set_useOffset(np.int64(1))
assert f.offset == 1, f.offset
assert f.get_useOffset() is False, f.get_useOffset()

# np.float64(1.0) == True as well.
f = ScalarFormatter()
f.set_useOffset(np.float64(1.0))
assert f.offset == 1.0, f.offset
assert f.get_useOffset() is False, f.get_useOffset()

# np.float64(0.0) == False; must still be a numeric offset.
f = ScalarFormatter()
f.set_useOffset(np.float64(0.0))
assert f.offset == 0.0, f.offset
assert f.get_useOffset() is False, f.get_useOffset()

# Non-unit numerics must keep working too.
f = ScalarFormatter()
f.set_useOffset(np.int64(2))
assert f.offset == 2 and f.get_useOffset() is False, (f.offset, f.get_useOffset())

print("ok: numpy numeric scalars are treated as numbers, not booleans")