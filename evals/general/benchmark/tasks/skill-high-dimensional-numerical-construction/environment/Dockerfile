FROM bench-base:python-3.12

WORKDIR /app

# Generate an exact linear dataset with 5 features.
RUN pip install --quiet numpy
RUN python3 - <<'PYEOF'
import numpy as np
rng = np.random.RandomState(7)
X = rng.randint(-3, 5, size=(20, 5)).astype(float)
beta = np.array([2.0, -1.5, 3.0, 0.25, -2.0])
y = X @ beta
np.savetxt('/app/regression.csv', np.column_stack([X, y]),
           delimiter=',', header='x0,x1,x2,x3,x4,y', comments='', fmt='%.10g')
PYEOF