"""Hidden case: with a forced explicit numeric offset, the formatter must
write tick labels relative to that offset (the user-visible point of the
feature). Drives the formatter's own set_locs machinery, exactly like a real
axis does; no rendering involved."""
from matplotlib.ticker import ScalarFormatter

# Forced offset of 1: labels must be the residual values 0,2,4,6.
f = ScalarFormatter()
f.create_dummy_axis()
f.axis.set_data_interval(0, 10)
f.axis.set_view_interval(0, 10)
f.set_useOffset(1)
f.set_locs([1, 3, 5, 7])
labels = [f(v) for v in (1, 3, 5, 7)]
assert labels == ["0", "2", "4", "6"], labels

# Same path with a non-unit numeric offset.
f2 = ScalarFormatter()
f2.create_dummy_axis()
f2.axis.set_data_interval(0, 20)
f2.axis.set_view_interval(0, 20)
f2.set_useOffset(10)
f2.set_locs([10, 12, 14])
assert [f2(v) for v in (10, 12, 14)] == ["0", "2", "4"]

print("ok: tick labels are written relative to the forced offset")