FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

WORKDIR /app

RUN pip install numpy

RUN python3 - <<'PY'
import json, numpy, os, sys

# Write input files
with open('/app/input.json','w') as f:
    json.dump({"x": [0.5, -1.0, 2.0]}, f)
with open('/app/shard_a.json','w') as f:
    json.dump({"W1": [[1.0, 2.0, 0.5], [0.0, -1.0, 3.0]], "b1": [0.1, -0.2]}, f)
with open('/app/shard_b.json','w') as f:
    json.dump({"W2": [[2.0, -1.0], [0.5, 1.0]], "b2": [0.0, 0.5]}, f)

import numpy
PY