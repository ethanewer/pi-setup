"""Hidden case: on a single formatter, booleans and numeric offsets
(including 0, 1.0 and 3.5) must be distinguishable inputs with stable state
transitions. The numeric value 0/0.0/1.0 must never be taken for the booleans
False/True, and toggling back and forth must keep working."""
from matplotlib.ticker import ScalarFormatter

f = ScalarFormatter()

# automatic mode on
f.set_useOffset(True)
assert f.get_useOffset() is True and f.offset == 0, (f.get_useOffset(), f.offset)

# the numeric value 0 is a number, not 'disable offset notation'
f.set_useOffset(0)
assert f.get_useOffset() is False and f.offset == 0, (f.get_useOffset(), f.offset)

# back to automatic mode
f.set_useOffset(True)
assert f.get_useOffset() is True and f.offset == 0, (f.get_useOffset(), f.offset)

# a real boolean turns it off
f.set_useOffset(False)
assert f.get_useOffset() is False and f.offset == 0, (f.get_useOffset(), f.offset)

# leftover state must not leak into the next numeric set
f.set_useOffset(3.5)
assert f.offset == 3.5 and f.get_useOffset() is False, (f.offset, f.get_useOffset())

# the numeric float 1.0 must be a number (this is the value-equality trap)
f.set_useOffset(1.0)
assert f.offset == 1.0 and f.get_useOffset() is False, (f.offset, f.get_useOffset())

print("ok: bool flags and numeric offsets (incl. 0, 1.0, 3.5) are distinct, stateful inputs")