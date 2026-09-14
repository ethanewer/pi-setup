"""Hidden case: all-zero inputs combined with pie keyword paths the upstream
regression test never uses (explode, startangle, counterclock, labels,
autopct, plus a numpy zeros array) must all be rejected with the clean
message 'All wedge sizes are zero', while normal pies with the same keyword
paths must still render successfully."""
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
expect_clean_error(ax, [0, 0], explode=[0.2, 0.1], startangle=90,
                   counterclock=False, labels=['a', 'b'])
expect_clean_error(ax, np.zeros(3), autopct='%1.1f%%')

# Sanity: the same keyword paths on non-zero data must keep working.
fig, ax = plt.subplots()
wedges, texts, autotexts = ax.pie([10, 20, 30], explode=[0.0, 0.1, 0.0],
                                  startangle=90, counterclock=False,
                                  labels=['a', 'b', 'c'], autopct='%1.1f%%')
assert len(wedges) == 3 and len(texts) == 3 and len(autotexts) == 3

print("ok: all-zero inputs through explode/startangle/autopct paths are rejected cleanly; keyword paths still work on non-zero data")