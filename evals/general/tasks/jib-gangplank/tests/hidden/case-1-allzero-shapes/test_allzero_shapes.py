"""Hidden case: all-zero wedge inputs of shapes the upstream regression test
does not use (three slices, a numpy float array, labelled floats) must be
rejected up front with the clean message 'All wedge sizes are zero', and a
normal non-zero pie must still draw without any error."""
import numpy as np

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def expect_clean_error(ax, x, **kwargs):
    try:
        ax.pie(x, **kwargs)
    except ValueError as e:
        assert 'All wedge sizes are zero' in str(e), \
            'unexpected ValueError message: %r' % str(e)
        return
    raise AssertionError(
        'pie(%r, %r) did not raise: all-zero input was not rejected' % (x, kwargs))


fig, ax = plt.subplots()
expect_clean_error(ax, [0, 0, 0])
expect_clean_error(ax, np.zeros(4))
expect_clean_error(ax, [0.0, 0.0], labels=['x', 'y'])

# Sanity: ordinary pie data keeps drawing.
fig, ax = plt.subplots()
wedges, texts = ax.pie([15, 30, 45, 10])
assert len(wedges) == 4 and len(texts) == 4

print("ok: all-zero inputs of other shapes are rejected cleanly; normal pies still draw")