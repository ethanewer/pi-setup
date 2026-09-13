#!/bin/bash
# Oracle for chainplate-drift: applies the minimal upstream fix to the
# scikit-image checkout at /app/src (guard EllipseModel.estimate against
# fewer than five data points), then proves the fix with the exact issue
# reproductions and with the project's own test suite.
set -e

python3 /solution/fix_fit.py /app/src/skimage/measure/fit.py

echo "== issue reproduction: 4 arbitrary points must refuse, with a warning =="
cd /app/src && python3 -c "
import numpy as np
from skimage.measure import EllipseModel
m = EllipseModel()
ok = m.estimate(np.array([[0., 0.], [1., 2.], [3., 1.], [4., 5.]]))
print('4-point estimate ->', ok, ' params ->', m.params)
assert ok is False
assert m.params is None, 'estimate fabricated parameters without 5 points'
" && python3 -c "
import warnings

import numpy as np
from skimage.measure import EllipseModel

with warnings.catch_warnings(record=True) as w:
    warnings.simplefilter('always')
    m = EllipseModel()
    ok = m.estimate(np.array([[50., 80.], [51., 81.], [52., 80.]]))
print('3-collinear estimate ->', ok, ' warnings ->', [str(x.message) for x in w])
assert ok is False
assert any('Need at least 5 data points to estimate an ellipse.' in str(x.message) for x in w)
"

echo "== the project's own regression test for this bug (from the fix commit) =="
cd /app/src && python3 -m pytest \
    /opt/golden/test_fit.py::test_ellipse_model_estimate_failers \
    -o addopts= -p no:cacheprovider -q

echo "== the project's own estimator tests stay green (golden test_fit.py) =="
cd /app/src && python3 -m pytest /opt/golden/test_fit.py \
    -o addopts= -p no:cacheprovider -q