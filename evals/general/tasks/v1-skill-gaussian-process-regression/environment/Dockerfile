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
import json
json.dump([-2.0,-1.0,0.0,1.0,2.0,3.0], open('/app/xtrain.json','w'))
json.dump([4.5,0.5,1.5,0.5,4.5,22.0], open('/app/ytrain.json','w'))
json.dump([0.5,1.5,2.5], open('/app/xtest.json','w'))
PY